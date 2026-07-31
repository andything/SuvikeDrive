//
//  FileBrowserManager.swift
//  SuvikeDrive
//
//  功能: 文件浏览器业务逻辑管理
//  归属: Core
//  通信: 通过 EventBus
//

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 文件浏览器状态
enum FileBrowserState {
    case idle
    case loading
    case loaded([FileInfo])
    case error(String)
    case loadingServers
}

// MARK: - 文件浏览器管理器
class FileBrowserManager {
    static let shared = FileBrowserManager()
    private init() {}
    
    private let webDAVModule = WebDAVModule.shared
    private var currentServerID: String?
    private var currentPath: String = "/"
    private var navigationStack: [String] = ["/"]
    
    // EventBus 订阅
    private var eventTokens: [SubscriptionToken] = []
    
    // 状态
    private(set) var state: FileBrowserState = .idle
    private(set) var availableServers: [ServerConfig] = []
    private(set) var currentFiles: [FileInfo] = []
    private(set) var currentServerName: String = ""
    
    // 回调
    var onStateChanged: ((FileBrowserState) -> Void)?
    
    func setup() {
        setupEventListeners()
        loadAvailableServers()
    }
    
    func cleanup() {
        eventTokens.forEach { $0.unsubscribe() }
        eventTokens.removeAll()
    }
    
    // MARK: - EventBus 监听
    
    private func setupEventListeners() {
        // ✅ 监听配置变化
        let configToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .medium
        ) { [weak self] event in
            if event.key == "server.mounted" || event.key == "server.unmounted" {
                print("📋 [FileBrowserManager] 服务器挂载状态变化，重新加载服务器列表")
                self?.loadAvailableServers()
            }
        }
        eventTokens.append(configToken)
        
        // ✅ 监听挂载完成事件（直接刷新）
        let mountToken = EventBus.shared.subscribe(
            to: MountCompleted.self,
            priority: .high
        ) { [weak self] event in
            print("📋 [FileBrowserManager] 收到挂载完成事件: \(event.serverID)")
            DispatchQueue.main.async {
                // 重新加载服务器列表
                self?.loadAvailableServers()
                // 如果当前没有选中的服务器，选择刚挂载的
                if self?.currentServerID == nil {
                    self?.selectServer(serverID: event.serverID)
                } else if self?.currentServerID == event.serverID {
                    // 如果当前选中的就是刚挂载的，刷新文件列表
                    self?.loadFiles()
                }
            }
        }
        eventTokens.append(mountToken)
        
        // ✅ 监听卸载完成事件
        let unmountToken = EventBus.shared.subscribe(
            to: UnmountCompleted.self,
            priority: .high
        ) { [weak self] event in
            print("📋 [FileBrowserManager] 收到卸载完成事件: \(event.serverID)")
            DispatchQueue.main.async {
                self?.loadAvailableServers()
                if self?.currentServerID == event.serverID {
                    self?.currentServerID = nil
                    self?.currentFiles = []
                    self?.currentServerName = ""
                    self?.state = .idle
                    self?.onStateChanged?(.idle)
                }
            }
        }
        eventTokens.append(unmountToken)
    }
    
    // MARK: - 服务器管理
    
    func loadAvailableServers() {
        print("📋 [FileBrowserManager] 开始加载服务器列表...")
        
        let mountedServers = MountManager.shared.getMountedServers()
        let allServers = ConfigurationManager.shared.getServers()
        
        print("📋 [FileBrowserManager] 已挂载服务器: \(mountedServers)")
        print("📋 [FileBrowserManager] 所有服务器: \(allServers.map { $0.id })")
        
        availableServers = allServers.filter { mountedServers.contains($0.id) }
        
        print("📋 [FileBrowserManager] 可用服务器: \(availableServers.map { $0.name })")
        
        if availableServers.isEmpty {
            state = .error("没有已挂载的服务器")
            onStateChanged?(state)
        } else if currentServerID == nil || !availableServers.contains(where: { $0.id == currentServerID }) {
            // 自动选择第一个可用服务器
            selectServer(serverID: availableServers.first?.id)
        }
    }
    
    func selectServer(serverID: String?) {
        guard let serverID = serverID else {
            currentServerID = nil
            currentFiles = []
            currentServerName = ""
            state = .idle
            onStateChanged?(state)
            return
        }
        
        // ✅ 检查服务器是否可用
        guard availableServers.contains(where: { $0.id == serverID }) else {
            print("⚠️ [FileBrowserManager] 服务器不可用: \(serverID)")
            state = .error("服务器不可用")
            onStateChanged?(state)
            return
        }
        
        currentServerID = serverID
        currentServerName = availableServers.first(where: { $0.id == serverID })?.name ?? ""
        resetNavigation()
        loadFiles()
    }
    
    // MARK: - 文件操作
    
    func loadFiles() {
        guard let serverID = currentServerID, !serverID.isEmpty else {
            currentFiles = []
            state = .idle
            onStateChanged?(state)
            return
        }
        
        state = .loading
        onStateChanged?(state)
        
        let pathParam = currentPath == "/" ? "/" : currentPath
        
        print("📋 [FileBrowserManager] 加载文件: 服务器=\(serverID), 路径=\(pathParam)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let files = try self.webDAVModule.listFiles(serverID: serverID, path: pathParam)
                DispatchQueue.main.async {
                    self.currentFiles = files
                    self.state = .loaded(files)
                    self.onStateChanged?(self.state)
                    print("📋 [FileBrowserManager] 加载完成: \(files.count) 个文件")
                    
                    // ✅ 发送文件列表加载完成事件
                    EventBus.shared.publish(FileListLoaded(serverID: serverID, count: files.count))
                }
            } catch {
                DispatchQueue.main.async {
                    let errorMsg = self.formatErrorMessage(error)
                    self.state = .error(errorMsg)
                    self.onStateChanged?(self.state)
                    print("❌ [FileBrowserManager] 加载失败: \(error)")
                }
            }
        }
    }
    
    // MARK: - 导航
    
    func navigateTo(path: String) {
        print("📂 [FileBrowserManager] 导航到: \(path)")
        
        guard !path.isEmpty else {
            print("⚠️ [FileBrowserManager] 路径为空，忽略导航")
            return
        }
        
        var normalizedPath = path
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        
        if normalizedPath == "/" {
            navigateToRoot()
            return
        }
        
        currentPath = normalizedPath
        
        if let index = navigationStack.firstIndex(of: normalizedPath) {
            navigationStack.removeSubrange((index + 1)...)
        } else {
            navigationStack.append(normalizedPath)
        }
        
        loadFiles()
    }
    
    func navigateToRoot() {
        currentPath = "/"
        navigationStack = ["/"]
        loadFiles()
    }
    
    func goUp() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        currentPath = navigationStack.last ?? "/"
        loadFiles()
    }
    
    func resetNavigation() {
        currentPath = "/"
        navigationStack = ["/"]
    }
    
    // MARK: - 下载文件
    
    func downloadFile(_ file: FileInfo) {
        guard let serverID = currentServerID, !serverID.isEmpty else { return }
        
        let savePanel = NSOpenPanel()
        savePanel.prompt = "下载"
        savePanel.canChooseDirectories = true
        savePanel.canCreateDirectories = true
        savePanel.message = "选择保存位置"
        savePanel.title = "下载文件"
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let selectedURL = savePanel.url {
                let localPath = selectedURL.appendingPathComponent(file.name)
                let totalBytes = file.size
                
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try self.webDAVModule.downloadFile(
                            serverID: serverID,
                            remotePath: file.path,
                            localPath: localPath.path
                        ) { progress in
                            DispatchQueue.main.async {
                                EventBus.shared.publish(FileDownloadProgress(
                                    fileName: file.name,
                                    filePath: file.path,
                                    progress: progress,
                                    bytesTransferred: Int64(progress * Double(totalBytes))
                                ))
                            }
                        }
                        
                        // ✅ 记录下载历史
                        DownloadHistoryManager.shared.markAsDownloaded(
                            fileName: file.name,
                            serverID: serverID,
                            localPath: localPath.path
                        )
                        
                        DispatchQueue.main.async {
                            EventBus.shared.publish(FileDownloadComplete(
                                fileName: file.name,
                                filePath: file.path,
                                success: true,
                                localPath: localPath.path
                            ))
                            self.loadFiles()
                        }
                    } catch {
                        DispatchQueue.main.async {
                            EventBus.shared.publish(FileDownloadComplete(
                                fileName: file.name,
                                filePath: file.path,
                                success: false,
                                localPath: nil,
                                error: error.localizedDescription
                            ))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 上传文件
    
    func uploadFiles(urls: [URL]) {
        guard let serverID = currentServerID, !serverID.isEmpty else {
            showAlert(title: "上传失败", message: "请先选择一个服务器")
            return
        }
        
        guard !urls.isEmpty else { return }
        
        for url in urls {
            let fileName = url.lastPathComponent
            let remotePath = currentPath + (currentPath.hasSuffix("/") ? "" : "/") + fileName
            
            print("📤 [FileBrowserManager] 开始上传: \(fileName) -> \(remotePath)")
            
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes?[.size] as? UInt64) ?? 0
            
            DispatchQueue.main.async {
                EventBus.shared.publish(FileUploadProgress(
                    fileName: fileName,
                    filePath: remotePath,
                    progress: 0.0,
                    bytesTransferred: 0
                ))
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                    try self.webDAVModule.uploadFile(
                        serverID: serverID,
                        localPath: url.path,
                        remotePath: remotePath
                    ) { progress in
                        DispatchQueue.main.async {
                            EventBus.shared.publish(FileUploadProgress(
                                fileName: fileName,
                                filePath: remotePath,
                                progress: progress,
                                bytesTransferred: Int64(progress * Double(fileSize))
                            ))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        EventBus.shared.publish(FileUploadComplete(
                            fileName: fileName,
                            filePath: remotePath,
                            success: true
                        ))
                        self.loadFiles()
                    }
                } catch {
                    DispatchQueue.main.async {
                        EventBus.shared.publish(FileUploadComplete(
                            fileName: fileName,
                            filePath: remotePath,
                            success: false,
                            error: error.localizedDescription
                        ))
                    }
                }
            }
        }
    }
    
    // MARK: - 上传文件夹
    
    func uploadFolder(url: URL) {
        guard let serverID = currentServerID, !serverID.isEmpty else {
            showAlert(title: "上传失败", message: "请先选择一个服务器")
            return
        }
        
        let folderName = url.lastPathComponent
        let remoteFolderPath = currentPath + (currentPath.hasSuffix("/") ? "" : "/") + folderName
        
        do {
            try webDAVModule.createDirectory(serverID: serverID, path: remoteFolderPath)
            print("📁 [FileBrowserManager] 创建远程文件夹: \(remoteFolderPath)")
        } catch {
            print("⚠️ [FileBrowserManager] 创建远程文件夹失败: \(error)")
        }
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            showAlert(title: "上传失败", message: "无法读取文件夹内容")
            return
        }
        
        var filesToUpload: [URL] = []
        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    filesToUpload.append(fileURL)
                }
            }
        }
        
        if filesToUpload.isEmpty {
            showAlert(title: "提示", message: "文件夹为空，无需上传")
            return
        }
        
        for fileURL in filesToUpload {
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            let remotePath = remoteFolderPath + "/" + relativePath
            
            print("📤 [FileBrowserManager] 上传: \(relativePath) -> \(remotePath)")
            
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attributes?[.size] as? UInt64) ?? 0
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                    try self.webDAVModule.uploadFile(
                        serverID: serverID,
                        localPath: fileURL.path,
                        remotePath: remotePath
                    ) { progress in
                        DispatchQueue.main.async {
                            EventBus.shared.publish(FileUploadProgress(
                                fileName: relativePath,
                                filePath: remotePath,
                                progress: progress,
                                bytesTransferred: Int64(progress * Double(fileSize))
                            ))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        EventBus.shared.publish(FileUploadComplete(
                            fileName: relativePath,
                            filePath: remotePath,
                            success: true
                        ))
                    }
                } catch {
                    DispatchQueue.main.async {
                        EventBus.shared.publish(FileUploadComplete(
                            fileName: relativePath,
                            filePath: remotePath,
                            success: false,
                            error: error.localizedDescription
                        ))
                    }
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.loadFiles()
        }
    }
    
    // MARK: - 辅助方法
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    private func formatErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "SuvikeDrive.ProtocolError" && nsError.code == 13 {
            return "连接失败：无法获取文件列表，请检查服务器是否可访问"
        }
        return error.localizedDescription
    }
    
    // MARK: - 状态查询
    
    func getCurrentPath() -> String {
        return currentPath
    }
    
    func getNavigationStack() -> [String] {
        return navigationStack
    }
    
    func getServerName() -> String {
        return currentServerName
    }
    
    func getSelectedServerID() -> String? {
        return currentServerID
    }
    
    // MARK: - 公开方法
    
    func getCurrentServerID() -> String? {
        return currentServerID
    }
    
    func getWebDAVModule() -> WebDAVModule {
        return webDAVModule
    }
    
    func listFilesAtPath(_ path: String) throws -> [FileInfo] {
        guard let serverID = currentServerID else {
            return []
        }
        return try webDAVModule.listFiles(serverID: serverID, path: path)
    }
}
