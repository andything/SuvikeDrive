//
//  MountManager.swift
//  SuvikeDrive
//
//  功能: 挂载管理器（配合 ProtocolModuleManager）
//  通信: 全部通过 EventBus
//  修复: 每条连接独立状态，挂载任务正确重置
//  新增: 删除连接时删除挂载文件夹
//  新增: WebDAV 挂载状态检测（扫描 /Volumes 目录 + 符号链接）
//  安全: 只删除符号链接，不删除普通文件/目录
//

import AppKit
import Foundation
import Combine

// MARK: - 挂载类型

enum MountType {
    case webdavVolume
    case symbolicLink
}

// MARK: - 挂载信息

struct MountInfo {
    let mountPath: String
    let type: MountType
    let port: Int?
    let targetPath: String?
    let isMounted: Bool
    
    init(mountPath: String, type: MountType, port: Int? = nil, targetPath: String? = nil, isMounted: Bool = true) {
        self.mountPath = mountPath
        self.type = type
        self.port = port
        self.targetPath = targetPath
        self.isMounted = isMounted
    }
}

// MARK: - MountManager

class MountManager: ObservableObject {
    static let shared = MountManager()
    
    @Published private(set) var mountedServers: Set<String> = []
    @Published private(set) var mountErrors: [String: String] = [:]
    
    private var mountingTasks: [String: Bool] = [:]
    private var mountPaths: [String: String] = [:]
    private let mountQueue = DispatchQueue(label: "com.suvikedrive.mountmanager", attributes: .concurrent)
    private var scanTimer: Timer?
    private var eventTokens: [SubscriptionToken] = []
    
    private let forbiddenNames: Set<String> = ["", "/", "Users", "Desktop", "SuvikeDrive", "Applications", "System", "Library", "Volumes", "Documents", "Downloads", "Pictures", "Movies", "Music"]
    
    private init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.verifyMountStatesEnhanced()
        }
        startPeriodicScan()
        setupEventListeners()
    }
    
    deinit {
        stopPeriodicScan()
        eventTokens.forEach { $0.unsubscribe() }
        eventTokens.removeAll()
    }
    
    // MARK: - EventBus 监听
    
    private func setupEventListeners() {
        let token = EventBus.shared.subscribe(to: UnmountDesktopSymlinkRequest.self) { [weak self] event in
            self?.deleteDesktopSymlink(byName: event.volumeName)
        }
        eventTokens.append(token)
        
        let configToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .medium
        ) { [weak self] event in
            if event.key == "app.showDesktop" {
                DispatchQueue.main.async {
                    self?.refreshDesktopSymlinks()
                }
            }
        }
        eventTokens.append(configToken)
    }
    
    // MARK: - 定时扫描
    
    func startPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.verifyMountStatesEnhanced()
        }
    }
    
    func stopPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = nil
    }
    
    // MARK: - 挂载状态检测
    
    func scanAllMounts() -> [String: MountInfo] {
        var result: [String: MountInfo] = [:]
        
        guard let mountedVolumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else {
            return result
        }
        
        for volume in mountedVolumes where volume.hasPrefix("www.yiqipro.com_") {
            let mountPath = "/Volumes/\(volume)"
            if isMountedPath(mountPath) {
                let portString = volume.replacingOccurrences(of: "www.yiqipro.com_", with: "")
                let port = Int(portString) ?? 0
                result[volume] = MountInfo(
                    mountPath: mountPath,
                    type: .webdavVolume,
                    port: port,
                    targetPath: nil,
                    isMounted: true
                )
            }
        }
        
        let home = NSHomeDirectory()
        let suvikeDrivePath = "\(home)/SuvikeDrive"
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: suvikeDrivePath) {
            for item in contents {
                let fullPath = "\(suvikeDrivePath)/\(item)"
                let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath)
                if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                    if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: fullPath),
                       FileManager.default.fileExists(atPath: target) {
                        result[item] = MountInfo(
                            mountPath: fullPath,
                            type: .symbolicLink,
                            port: nil,
                            targetPath: target,
                            isMounted: true
                        )
                    }
                }
            }
        }
        
        return result
    }
    
    func verifyMountStatesEnhanced() {
        let allMounts = scanAllMounts()
        
        for (key, info) in allMounts {
            var foundServerID: String?
            let allServers = ConfigurationManager.shared.getServers()
            for server in allServers {
                let sanitizedName = WebDAVHelper.sanitizeVolumeName(server.name)
                if key == server.name || key == sanitizedName {
                    foundServerID = server.id
                    break
                }
            }
            
            if foundServerID == nil {
                for (serverID, path) in mountPaths {
                    if path == info.mountPath || path == info.targetPath {
                        foundServerID = serverID
                        break
                    }
                }
            }
            
            if let serverID = foundServerID {
                if !mountedServers.contains(serverID) {
                    DispatchQueue.main.async {
                        self.mountedServers.insert(serverID)
                        self.mountPaths[serverID] = info.mountPath
                        self.mountErrors[serverID] = nil
                        EventBus.shared.publish(MountCompleted(serverID: serverID, mountPath: info.mountPath, success: true))
                    }
                }
            }
        }
        
        for (serverID, mountPath) in mountPaths {
            let isActuallyMounted = allMounts.values.contains { info in
                info.mountPath == mountPath || info.targetPath == mountPath
            }
            
            if !isActuallyMounted && mountedServers.contains(serverID) {
                DispatchQueue.main.async {
                    self.mountedServers.remove(serverID)
                    self.mountPaths.removeValue(forKey: serverID)
                    self.mountingTasks[serverID] = false
                    EventBus.shared.publish(UnmountCompleted(serverID: serverID))
                }
            }
        }
    }
    
    func isMountedEnhanced(serverID: String, config: ServerConfig) -> Bool {
        if mountedServers.contains(serverID) {
            if let mountPath = mountPaths[serverID],
               FileManager.default.fileExists(atPath: mountPath) {
                return true
            }
            DispatchQueue.main.async {
                self.mountedServers.remove(serverID)
                self.mountPaths.removeValue(forKey: serverID)
                self.mountingTasks[serverID] = false
            }
            return false
        }
        
        let port = config.getPort()
        let mountPointName = "www.yiqipro.com_\(port)"
        let mountPath = "/Volumes/\(mountPointName)"
        
        if FileManager.default.fileExists(atPath: mountPath) && isMountedPath(mountPath) {
            DispatchQueue.main.async {
                self.mountedServers.insert(serverID)
                self.mountPaths[serverID] = mountPath
                self.mountErrors[serverID] = nil
            }
            return true
        }
        
        let home = NSHomeDirectory()
        let symlinkPath = "\(home)/SuvikeDrive/\(config.name)"
        
        if FileManager.default.fileExists(atPath: symlinkPath) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: symlinkPath)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath),
                   FileManager.default.fileExists(atPath: target) {
                    DispatchQueue.main.async {
                        self.mountedServers.insert(serverID)
                        self.mountPaths[serverID] = symlinkPath
                        self.mountErrors[serverID] = nil
                    }
                    return true
                }
            }
        }
        
        return false
    }
    
    private func isMountedPath(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        
        var stats = stat()
        var parentStats = stat()
        
        if stat(path, &stats) == 0 {
            let parentPath = (path as NSString).deletingLastPathComponent
            if stat(parentPath, &parentStats) == 0 {
                return stats.st_dev != parentStats.st_dev
            }
        }
        return false
    }
    
    // MARK: - 挂载
    
    func mount(serverID: String, config: ServerConfig, completion: @escaping (Result<String, Error>) -> Void) {
        mountQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            if self.isMountedEnhanced(serverID: serverID, config: config) {
                let mountPath = self.mountPaths[serverID] ?? config.getMountPath()
                DispatchQueue.main.async {
                    self.mountedServers.insert(serverID)
                    self.mountingTasks[serverID] = false
                    self.createDesktopSymlink(volumeName: config.name, targetPath: mountPath)
                    EventBus.shared.publish(MountCompleted(serverID: serverID, mountPath: mountPath, success: true))
                    completion(.success(mountPath))
                }
                return
            }
            
            DispatchQueue.main.async {
                EventBus.shared.publish(MountStarted(serverID: serverID))
            }
            
            if self.mountingTasks[serverID] == true {
                DispatchQueue.main.async {
                    let error = ProtocolError.connectionFailed("正在挂载中")
                    EventBus.shared.publish(MountFailed(serverID: serverID, error: error.localizedDescription))
                    completion(.failure(error))
                }
                return
            }
            
            let mountPath = config.getMountPath()
            self.mountingTasks[serverID] = true
            
            do {
                try ProtocolModuleManager.shared.connect(serverID: serverID, config: config)
                try ProtocolModuleManager.shared.mount(serverID: serverID, mountPath: mountPath)
                
                var retryCount = 0
                let maxRetries = 10
                
                func checkMountPath() {
                    if self.mountingTasks[serverID] == false { return }
                    
                    if FileManager.default.fileExists(atPath: mountPath) {
                        self.mountedServers.insert(serverID)
                        self.mountPaths[serverID] = mountPath
                        self.mountErrors[serverID] = nil
                        self.mountingTasks[serverID] = false
                        self.createDesktopSymlink(volumeName: config.name, targetPath: mountPath)
                        EventBus.shared.publish(MountCompleted(serverID: serverID, mountPath: mountPath, success: true))
                        completion(.success(mountPath))
                    } else {
                        retryCount += 1
                        if retryCount < maxRetries {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { checkMountPath() }
                        } else {
                            self.mountingTasks[serverID] = false
                            self.mountErrors[serverID] = "挂载路径不存在"
                            self.mountPaths.removeValue(forKey: serverID)
                            EventBus.shared.publish(MountFailed(serverID: serverID, error: "挂载路径不存在"))
                            completion(.failure(ProtocolError.mountFailed("挂载路径不存在")))
                        }
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { checkMountPath() }
                
            } catch {
                ProtocolModuleManager.shared.removeInstance(serverID: serverID)
                DispatchQueue.main.async {
                    self.mountingTasks[serverID] = false
                    self.mountErrors[serverID] = error.localizedDescription
                    self.mountPaths.removeValue(forKey: serverID)
                    EventBus.shared.publish(MountFailed(serverID: serverID, error: error.localizedDescription))
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 桌面符号链接
    
    private func createDesktopSymlink(volumeName: String, targetPath: String) {
        guard !volumeName.isEmpty, !targetPath.isEmpty else { return }
        
        let showDesktop = ConfigurationManager.shared.get(key: "app.showDesktop", defaultValue: false)
        if !showDesktop { return }
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop")
        let symlinkPath = desktop.appendingPathComponent(volumeName).path
        
        if FileManager.default.fileExists(atPath: symlinkPath) {
            try? FileManager.default.removeItem(atPath: symlinkPath)
        }
        
        do {
            try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)
        } catch {
            // 静默失败
        }
    }
    
    func deleteDesktopSymlink(byName name: String) {
        guard !name.isEmpty else { return }
        if forbiddenNames.contains(name) { return }
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop")
        let targetPath = desktop.appendingPathComponent(name).path
        
        if FileManager.default.fileExists(atPath: targetPath) {
            try? FileManager.default.removeItem(atPath: targetPath)
        }
    }
    
    func refreshDesktopSymlinks() {
        let showDesktop = ConfigurationManager.shared.get(key: "app.showDesktop", defaultValue: false)
        let allServers = ConfigurationManager.shared.getServers()
        let mountedServerIDs = getMountedServers()
        
        for server in allServers {
            guard mountedServerIDs.contains(server.id) else { continue }
            let mountPath = mountPaths[server.id] ?? server.getMountPath()
            if showDesktop {
                createDesktopSymlink(volumeName: server.name, targetPath: mountPath)
            } else {
                deleteDesktopSymlink(byName: server.name)
            }
        }
    }
    
    // MARK: - 卸载
    
    func unmount(serverID: String, force: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        mountQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var volumeName = ""
            if let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) {
                volumeName = config.name
            } else if let mountPath = self.mountPaths[serverID] {
                volumeName = (mountPath as NSString).lastPathComponent
            }
            
            guard !volumeName.isEmpty else {
                DispatchQueue.main.async {
                    self.mountingTasks[serverID] = false
                    EventBus.shared.publish(UnmountFailed(serverID: serverID, error: "无法获取卷名"))
                    completion(.failure(NSError(domain: "MountManager", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: "无法获取卷名"])))
                }
                return
            }
            
            if self.forbiddenNames.contains(volumeName) {
                DispatchQueue.main.async {
                    self.mountingTasks[serverID] = false
                    EventBus.shared.publish(UnmountFailed(serverID: serverID, error: "禁止操作系统目录"))
                    completion(.failure(NSError(domain: "MountManager", code: -2,
                                                userInfo: [NSLocalizedDescriptionKey: "禁止操作系统目录: \(volumeName)"])))
                }
                return
            }
            
            // ✅ 1. 暂停重连监控任务
            DispatchQueue.main.async {
                TaskScheduler.shared.pauseTask(taskID: "reconnect_monitor")
                Logger.shared.info("[\(serverID)] 已暂停重连监控任务", module: "MountManager")
            }
            
            // ✅ 2. 同步移除协议实例（取消所有网络请求）
            ProtocolModuleManager.shared.removeInstanceSync(serverID: serverID)
            Logger.shared.info("[\(serverID)] 协议实例已移除，所有网络请求已取消", module: "MountManager")
            
            let home = FileManager.default.homeDirectoryForCurrentUser
            let mountPath = self.mountPaths[serverID] ?? ""
            
            // 3. 删除桌面符号链接
            self.deleteDesktopSymlink(byName: volumeName)
            
            // 4. 删除 SuvikeDrive 目录下的符号链接
            let symlinkInSuvikeDrive = home.appendingPathComponent("SuvikeDrive").appendingPathComponent(volumeName).path
            if FileManager.default.fileExists(atPath: symlinkInSuvikeDrive) {
                try? FileManager.default.removeItem(atPath: symlinkInSuvikeDrive)
            }
            
            // 5. 等待任务取消
            Thread.sleep(forTimeInterval: 0.5)
            
            // 6. 发送卸载开始事件
            DispatchQueue.main.async {
                EventBus.shared.publish(UnmountStarted(serverID: serverID))
            }
            
            // 7. 检查挂载点是否存在
            if !FileManager.default.fileExists(atPath: mountPath) {
                DispatchQueue.main.async {
                    self.mountedServers.remove(serverID)
                    self.mountPaths.removeValue(forKey: serverID)
                    self.mountErrors[serverID] = nil
                    self.mountingTasks[serverID] = false
                    EventBus.shared.publish(UnmountCompleted(serverID: serverID))
                    // ✅ 恢复重连监控
                    TaskScheduler.shared.resumeTask(taskID: "reconnect_monitor")
                    completion(.success(()))
                }
                return
            }
            
            // 8. 执行系统卸载命令
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/umount")
            task.arguments = [mountPath]
            
            let stderrPipe = Pipe()
            task.standardError = stderrPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    ProtocolModuleManager.shared.removeInstance(serverID: serverID)
                    DispatchQueue.main.async {
                        self.mountedServers.remove(serverID)
                        self.mountPaths.removeValue(forKey: serverID)
                        self.mountErrors[serverID] = nil
                        self.mountingTasks[serverID] = false
                        EventBus.shared.publish(UnmountCompleted(serverID: serverID))
                        // ✅ 恢复重连监控
                        TaskScheduler.shared.resumeTask(taskID: "reconnect_monitor")
                        completion(.success(()))
                    }
                    return
                }
                
                // 9. 如果失败且 force=true，执行强制卸载
                if force {
                    let forceTask = Process()
                    forceTask.executableURL = URL(fileURLWithPath: "/usr/sbin/umount")
                    forceTask.arguments = ["-f", mountPath]
                    
                    let forceStderrPipe = Pipe()
                    forceTask.standardError = forceStderrPipe
                    
                    try forceTask.run()
                    forceTask.waitUntilExit()
                    
                    if forceTask.terminationStatus == 0 {
                        ProtocolModuleManager.shared.removeInstance(serverID: serverID)
                        DispatchQueue.main.async {
                            self.mountedServers.remove(serverID)
                            self.mountPaths.removeValue(forKey: serverID)
                            self.mountErrors[serverID] = nil
                            self.mountingTasks[serverID] = false
                            EventBus.shared.publish(UnmountCompleted(serverID: serverID))
                            // ✅ 恢复重连监控
                            TaskScheduler.shared.resumeTask(taskID: "reconnect_monitor")
                            completion(.success(()))
                        }
                        return
                    } else {
                        DispatchQueue.main.async {
                            self.mountingTasks[serverID] = false
                            self.mountErrors[serverID] = "强制卸载失败"
                            EventBus.shared.publish(UnmountFailed(serverID: serverID, error: "强制卸载失败"))
                            // ✅ 恢复重连监控
                            TaskScheduler.shared.resumeTask(taskID: "reconnect_monitor")
                            completion(.failure(NSError(domain: "MountManager", code: Int(forceTask.terminationStatus),
                                                        userInfo: [NSLocalizedDescriptionKey: "强制卸载失败"])))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.mountingTasks[serverID] = false
                        self.mountErrors[serverID] = "卸载失败"
                        EventBus.shared.publish(UnmountFailed(serverID: serverID, error: "卸载失败"))
                        // ✅ 恢复重连监控
                        TaskScheduler.shared.resumeTask(taskID: "reconnect_monitor")
                        completion(.failure(NSError(domain: "MountManager", code: Int(task.terminationStatus),
                                                    userInfo: [NSLocalizedDescriptionKey: "卸载失败"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.mountingTasks[serverID] = false
                    self.mountErrors[serverID] = error.localizedDescription
                    EventBus.shared.publish(UnmountFailed(serverID: serverID, error: error.localizedDescription))
                    // ✅ 恢复重连监控
                    TaskScheduler.shared.resumeTask(taskID: "reconnect_monitor")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 删除连接
    
    func deleteConnection(serverID: String, config: ServerConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        mountQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let mountPath = config.getMountPath()
            let volumeName = config.name
            
            self.deleteDesktopSymlink(byName: volumeName)
            
            if self.mountedServers.contains(serverID) {
                let semaphore = DispatchSemaphore(value: 0)
                self.unmount(serverID: serverID, force: true) { result in
                    semaphore.signal()
                }
                semaphore.wait()
            }
            
            var deleteError: Error?
            if FileManager.default.fileExists(atPath: mountPath) {
                if self.isMountedPath(mountPath) {
                    _ = DiskAPI.shared.forceUnmount(mountPath: mountPath)
                }
                do {
                    try FileManager.default.removeItem(atPath: mountPath)
                } catch {
                    deleteError = error
                }
            }
            
            ProtocolModuleManager.shared.removeInstance(serverID: serverID)
            
            DispatchQueue.main.async {
                self.mountedServers.remove(serverID)
                self.mountPaths.removeValue(forKey: serverID)
                self.mountErrors[serverID] = nil
                self.mountingTasks[serverID] = false
                
                if let error = deleteError {
                    EventBus.shared.publish(ServerConfigDeleted(serverID: serverID, success: false, error: error.localizedDescription))
                    completion(.failure(error))
                } else {
                    EventBus.shared.publish(ServerConfigDeleted(serverID: serverID, success: true, error: nil))
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - 状态查询
    
    func getMountedServers() -> Set<String> {
        verifyMountStatesEnhanced()
        return mountedServers
    }
    
    func getMountCount() -> Int {
        verifyMountStatesEnhanced()
        return mountedServers.count
    }
    
    func getMountError(serverID: String) -> String? {
        return mountErrors[serverID]
    }
    
    func getMountPath(serverID: String) -> String? {
        return mountPaths[serverID]
    }
    
    func isMounted(serverID: String) -> Bool {
        if let mountPath = mountPaths[serverID] {
            if FileManager.default.fileExists(atPath: mountPath) {
                return true
            } else {
                mountedServers.remove(serverID)
                mountPaths.removeValue(forKey: serverID)
                mountingTasks[serverID] = false
                return false
            }
        }
        return mountedServers.contains(serverID)
    }
    
    func resetMountingTask(serverID: String) {
        mountingTasks[serverID] = false
    }
    
    func getMountInstance(serverID: String) -> MountInstance? {
        guard let module = ProtocolModuleManager.shared.getInstance(serverID: serverID),
              let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            return nil
        }
        
        let mountPath = config.getMountPath()
        let status = ProtocolModuleManager.shared.getConnectionStatus(serverID: serverID)
        
        let instance = MountInstance(
            serverID: serverID,
            config: config,
            module: module
        )
        instance.mountPath = mountPath
        instance.state = status
        
        return instance
    }
    
    func getAllMountInstances() -> [MountInstance] {
        let allInstances = ProtocolModuleManager.shared.getAllInstances()
        return allInstances.compactMap { serverID, module in
            guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
                return nil
            }
            let instance = MountInstance(serverID: serverID, config: config, module: module)
            instance.mountPath = config.getMountPath()
            instance.state = ProtocolModuleManager.shared.getConnectionStatus(serverID: serverID)
            return instance
        }
    }
    
    func handleConnectionStateChange(serverID: String, state: ConnectionState, error: String?) {
        ProtocolModuleManager.shared.updateConnectionStatus(serverID: serverID, status: state)
        
        EventBus.shared.publish(
            ConnectionStateChanged(
                serverID: serverID,
                state: state,
                error: error
            )
        )
    }
    
    // MARK: - 清理状态（供 AppDelegate 调用）
    func forceCleanAllStates() {
        DispatchQueue.main.async {
            self.mountedServers.removeAll()
            self.mountPaths.removeAll()
            self.mountErrors.removeAll()
            self.mountingTasks.removeAll()
            print("📋 [MountManager] 所有内存状态已清理")
        }
    }
    
    func unmountAllVolumes() {
        print("📋 [MountManager] 强制卸载所有挂载卷...")
        
        let allMounts = scanAllMounts()
        
        for (key, info) in allMounts {
            if info.type == .webdavVolume {
                print("📋 [MountManager] 强制卸载: \(key) at \(info.mountPath)")
                
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/umount")
                task.arguments = ["-f", info.mountPath]
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    if task.terminationStatus == 0 {
                        print("✅ [MountManager] 强制卸载成功: \(info.mountPath)")
                    } else {
                        print("⚠️ [MountManager] 强制卸载失败: \(info.mountPath), 状态码: \(task.terminationStatus)")
                    }
                } catch {
                    print("⚠️ [MountManager] 强制卸载异常: \(error.localizedDescription)")
                }
            }
            
            // 清理符号链接
            if info.type == .symbolicLink {
                print("📋 [MountManager] 清理符号链接: \(key)")
                try? FileManager.default.removeItem(atPath: info.mountPath)
            }
        }
        
        // 清理内存状态
        forceCleanAllStates()
        
        print("📋 [MountManager] 强制卸载完成")
    }
}

// MARK: - 挂载实例

class MountInstance {
    let serverID: String
    let config: ServerConfig
    let module: ProtocolModule
    var mountPath: String = ""
    var state: ConnectionState = .idle
    var retryCount: Int = 0
    
    init(serverID: String, config: ServerConfig, module: ProtocolModule) {
        self.serverID = serverID
        self.config = config
        self.module = module
    }
    
    func updateState(_ state: ConnectionState, error: String? = nil) {
        self.state = state
    }
}
