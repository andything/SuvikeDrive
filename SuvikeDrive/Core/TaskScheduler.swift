//
//  TaskScheduler.swift
//  SuvikeDrive
//
//  功能:  全局定时任务统一注册、存储、管理
//

import AppKit
import Foundation

// MARK: - 任务优先级
enum TaskPriority: String, Codable {
    case high
    case medium
    case low
}

class TaskScheduler {
    static let shared = TaskScheduler()
    
    // MARK: - 属性
    private var tasks: [String: TaskModel] = [:]
    private var taskClosures: [String: () -> Void] = [:]
    private var taskTimers: [String: Timer] = [:]
    private let taskQueue = DispatchQueue(label: "com.suvikedrive.taskscheduler", attributes: .concurrent)
    private var isRunning = false
    private var isPaused = false
    
    private var totalExecutions: Int = 0
    private var totalErrors: Int = 0
    private var taskHistory: [TaskExecutionRecord] = []
    private let maxHistorySize = 1000
    
    private let lock = NSLock()
    
    private init() {
        Logger.shared.info("任务调度器初始化完成")
    }
    
    // MARK: - 启动/停止
    func start() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        
        registerDefaultTasks()
        restoreTaskStates()
        
        Logger.shared.info("任务调度器启动，已注册 \(tasks.count) 个任务")
    }
    
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning else { return }
        isRunning = false
        
        for (_, timer) in taskTimers {
            timer.invalidate()
        }
        taskTimers.removeAll()
        
        saveTaskStates()
        Logger.shared.info("任务调度器已停止")
    }
    
    func pause() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning && !isPaused else { return }
        isPaused = true
        
        for (_, timer) in taskTimers {
            timer.invalidate()
        }
        taskTimers.removeAll()
        
        Logger.shared.info("任务调度器已暂停")
    }
    
    func resume() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning && isPaused else { return }
        isPaused = false
        
        for (taskID, task) in tasks {
            if task.isEnabled && !task.isPaused {
                startTaskTimer(taskID: taskID, interval: task.interval)
            }
        }
        
        Logger.shared.info("任务调度器已恢复")
    }
    
    // MARK: - 默认任务注册
    private func registerDefaultTasks() {
        let heartbeatInterval = ConfigurationManager.shared.get(key: "heartbeat.interval", defaultValue: 30)
        registerTask(
            taskID: "heartbeat",
            name: "全局心跳检测",
            interval: TimeInterval(heartbeatInterval),
            priority: .high
        ) { [weak self] in
            self?.performHeartbeat()
        }
        
        registerTask(
            taskID: "connection_refresh",
            name: "连接状态刷新",
            interval: 60,
            priority: .medium
        ) { [weak self] in
            self?.refreshConnectionStates()
        }
        
        let otaInterval = ConfigurationManager.shared.get(key: "ota.checkInterval", defaultValue: 21600)
        registerTask(
            taskID: "ota_check",
            name: "OTA版本检查",
            interval: TimeInterval(otaInterval),
            priority: .low
        ) { [weak self] in
            self?.checkOTAUpdates()
        }
        
        registerTask(
            taskID: "log_cleanup",
            name: "日志清理",
            interval: 86400,
            priority: .low
        ) { [weak self] in
            self?.cleanupLogs()
        }
        
        registerTask(
            taskID: "cache_cleanup",
            name: "缓存清理",
            interval: 43200,
            priority: .low
        ) { [weak self] in
            self?.cleanupCache()
        }
        
        registerTask(
            taskID: "reconnect_monitor",
            name: "自动重连监控",
            interval: 10,
            priority: .high
        ) { [weak self] in
            self?.monitorReconnections()
        }
        
        registerTask(
            taskID: "disk_space_monitor",
            name: "磁盘空间监控",
            interval: 300,
            priority: .medium
        ) { [weak self] in
            self?.monitorDiskSpace()
        }
        
        registerTask(
            taskID: "config_backup",
            name: "配置自动备份",
            interval: 86400,
            priority: .low
        ) { [weak self] in
            self?.backupConfiguration()
        }
    }
    
    // MARK: - 任务管理
    func registerTask(
        taskID: String,
        name: String,
        interval: TimeInterval,
        priority: TaskPriority = .medium,
        initialDelay: TimeInterval = 0,
        task: @escaping () -> Void
    ) {
        taskQueue.async(flags: .barrier) {
            if self.tasks[taskID] != nil {
                self.unregisterTask(taskID: taskID)
            }
            
            let taskModel = TaskModel(
                id: taskID,
                name: name,
                type: .custom,
                interval: interval,
                isEnabled: true,
                isPaused: false
            )
            
            self.tasks[taskID] = taskModel
            self.taskClosures[taskID] = task
            
            if self.isRunning && !self.isPaused {
                self.startTaskTimer(taskID: taskID, interval: interval, initialDelay: initialDelay)
            }
            
            Logger.shared.debug("任务已注册: \(taskID) - \(name) (间隔: \(interval)秒)")
        }
    }
    
    func unregisterTask(taskID: String) {
        taskQueue.async(flags: .barrier) {
            self.tasks.removeValue(forKey: taskID)
            self.taskClosures.removeValue(forKey: taskID)
            if let timer = self.taskTimers[taskID] {
                timer.invalidate()
                self.taskTimers.removeValue(forKey: taskID)
            }
            Logger.shared.debug("任务已注销: \(taskID)")
        }
    }
    
    func pauseTask(taskID: String) {
        taskQueue.async(flags: .barrier) {
            guard var task = self.tasks[taskID] else { return }
            task.isPaused = true
            self.tasks[taskID] = task
            
            if let timer = self.taskTimers[taskID] {
                timer.invalidate()
                self.taskTimers.removeValue(forKey: taskID)
            }
            
            Logger.shared.debug("任务已暂停: \(taskID)")
        }
    }
    
    func resumeTask(taskID: String) {
        taskQueue.async(flags: .barrier) {
            guard var task = self.tasks[taskID] else { return }
            guard task.isEnabled else { return }
            
            task.isPaused = false
            self.tasks[taskID] = task
            
            if self.isRunning && !self.isPaused {
                self.startTaskTimer(taskID: taskID, interval: task.interval)
            }
            
            Logger.shared.debug("任务已恢复: \(taskID)")
        }
    }
    
    func enableTask(taskID: String) {
        taskQueue.async(flags: .barrier) {
            guard var task = self.tasks[taskID] else { return }
            task.isEnabled = true
            self.tasks[taskID] = task
            
            if self.isRunning && !self.isPaused && !task.isPaused {
                self.startTaskTimer(taskID: taskID, interval: task.interval)
            }
            
            Logger.shared.debug("任务已启用: \(taskID)")
        }
    }
    
    func disableTask(taskID: String) {
        taskQueue.async(flags: .barrier) {
            guard var task = self.tasks[taskID] else { return }
            task.isEnabled = false
            self.tasks[taskID] = task
            
            if let timer = self.taskTimers[taskID] {
                timer.invalidate()
                self.taskTimers.removeValue(forKey: taskID)
            }
            
            Logger.shared.debug("任务已禁用: \(taskID)")
        }
    }
    
    func executeTaskNow(taskID: String) {
        taskQueue.async {
            guard let _ = self.tasks[taskID] else {
                Logger.shared.warning("任务不存在: \(taskID)")
                return
            }
            self.executeTask(taskID: taskID)
        }
    }
    
    func getTaskStatus(taskID: String) -> TaskStatus? {
        var status: TaskStatus?
        taskQueue.sync {
            if let task = tasks[taskID] {
                status = TaskStatus(
                    id: task.id,
                    name: task.name,
                    isRunning: false,
                    isPaused: task.isPaused,
                    isEnabled: task.isEnabled,
                    lastRun: task.lastRun,
                    nextRun: task.nextRun,
                    runCount: task.runCount,
                    lastError: task.lastError,
                    interval: task.interval,
                    priority: .medium
                )
            }
        }
        return status
    }
    
    func getAllTaskStatus() -> [TaskStatus] {
        var statuses: [TaskStatus] = []
        taskQueue.sync {
            for task in tasks.values {
                statuses.append(
                    TaskStatus(
                        id: task.id,
                        name: task.name,
                        isRunning: false,
                        isPaused: task.isPaused,
                        isEnabled: task.isEnabled,
                        lastRun: task.lastRun,
                        nextRun: task.nextRun,
                        runCount: task.runCount,
                        lastError: task.lastError,
                        interval: task.interval,
                        priority: .medium
                    )
                )
            }
        }
        return statuses
    }
    
    func getTaskStatistics() -> TaskStatistics {
        var stats = TaskStatistics()
        taskQueue.sync {
            stats.totalTasks = tasks.count
            stats.enabledTasks = tasks.values.filter { $0.isEnabled }.count
            stats.runningTasks = 0
            stats.totalExecutions = self.totalExecutions
            stats.totalErrors = self.totalErrors
            stats.averageExecutionTime = 0
            stats.lastUpdated = Date()
        }
        return stats
    }
    
    // MARK: - 定时器管理
    private func startTaskTimer(taskID: String, interval: TimeInterval, initialDelay: TimeInterval = 0) {
        lock.lock()
        defer { lock.unlock() }
        
        if let timer = taskTimers[taskID] {
            timer.invalidate()
            taskTimers.removeValue(forKey: taskID)
        }
        
        var delay = initialDelay
        if delay == 0 {
            delay = interval
        }
        
        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.executeTask(taskID: taskID)
        }
        
        taskTimers[taskID] = timer
        RunLoop.current.add(timer, forMode: .common)
        
        if var task = tasks[taskID] {
            task.nextRun = Date().addingTimeInterval(delay)
            tasks[taskID] = task
        }
    }
    
    private func executeTask(taskID: String) {
        taskQueue.async {
            guard let task = self.tasks[taskID] else { return }
            guard task.isEnabled else { return }
            guard !task.isPaused else { return }
            
            self.executeTaskInternal(taskID: taskID, task: task)
        }
    }
    
    private func executeTaskInternal(taskID: String, task: TaskModel) {
        guard let closure = taskClosures[taskID] else { return }
        
        var mutableTask = task
        mutableTask.recordRun()
        tasks[taskID] = mutableTask
        
        let startTime = Date()
        totalExecutions += 1
        
        Logger.shared.debug("任务开始执行: \(task.id) - \(task.name) (第 \(task.runCount) 次)")
        
        EventBus.shared.publish(TaskStarted(taskID: task.id, taskName: task.name))
        
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            
            closure()
            
            let duration = Date().timeIntervalSince(startTime)
            Logger.shared.debug("任务执行完成: \(task.id) - \(task.name) (耗时: \(String(format: "%.3f", duration))秒)")
            
            EventBus.shared.publish(TaskCompleted(
                taskID: task.id,
                taskName: task.name,
                duration: duration
            ))
            
            self.recordExecution(taskID: task.id, success: true, duration: duration)
        }
    }
    
    // MARK: - 执行历史记录
    private func recordExecution(taskID: String, success: Bool, duration: TimeInterval) {
        taskQueue.async(flags: .barrier) {
            let record = TaskExecutionRecord(
                taskID: taskID,
                timestamp: Date(),
                success: success,
                duration: duration
            )
            
            self.taskHistory.append(record)
            
            if self.taskHistory.count > self.maxHistorySize {
                self.taskHistory.removeFirst(self.taskHistory.count - self.maxHistorySize)
            }
        }
    }
    
    func getTaskHistory(taskID: String? = nil, limit: Int = 100) -> [TaskExecutionRecord] {
        var records: [TaskExecutionRecord] = []
        taskQueue.sync {
            if let taskID = taskID {
                records = self.taskHistory.filter { $0.taskID == taskID }
            } else {
                records = self.taskHistory
            }
        }
        return Array(records.suffix(limit))
    }
    
    // MARK: - 状态持久化
    private func saveTaskStates() {
        let stateFile = getStateFileURL()
        
        taskQueue.sync {
            let taskArray = Array(tasks.values)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            do {
                let data = try encoder.encode(taskArray)
                try data.write(to: stateFile)
                Logger.shared.debug("任务状态已保存")
            } catch {
                Logger.shared.error("保存任务状态失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func restoreTaskStates() {
        let stateFile = getStateFileURL()
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: stateFile)
            let decoder = JSONDecoder()
            let taskArray = try decoder.decode([TaskModel].self, from: data)
            
            taskQueue.async(flags: .barrier) {
                for task in taskArray {
                    if self.tasks[task.id] != nil {
                        self.tasks[task.id] = task
                    }
                }
            }
            
            Logger.shared.debug("任务状态已恢复")
        } catch {
            Logger.shared.error("恢复任务状态失败: \(error.localizedDescription)")
        }
    }
    
    private func getStateFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("com.suvikedrive.drive")
        
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        
        return appDir.appendingPathComponent("task_states.json")
    }
    
    // MARK: - 格式化文件大小辅助方法
    private func formatFileSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - 具体任务实现
    // 1. 心跳检测
    private func performHeartbeat() {
        Logger.shared.debug("执行全局心跳检测")
        
        let mountedServers = MountManager.shared.getMountedServers()
        
        if mountedServers.isEmpty {
            return
        }
        
        for serverID in mountedServers {
            // ✅ 验证挂载状态
            if let mountPath = MountManager.shared.getMountPath(serverID: serverID) {
                if !DiskAPI.shared.isMounted(mountPath) {
                    Logger.shared.debug("[\(serverID)] 挂载路径不存在，跳过心跳", module: "TaskScheduler")
                    continue
                }
            } else {
                continue
            }
            
            if let instance = MountManager.shared.getMountInstance(serverID: serverID) {
                let module = ProtocolModuleManager.shared.getModule(type: instance.config.protocolType)
                let success = module?.ping(serverID: serverID) ?? false
                
                if success {
                    EventBus.shared.publish(HeartbeatReceived(serverID: serverID))
                } else {
                    EventBus.shared.publish(HeartbeatFailed(serverID: serverID))
                    Logger.shared.warning("心跳检测失败: \(serverID)")
                }
            }
        }
        
        ConfigurationManager.shared.set(key: "lastHeartbeat", value: Date().timeIntervalSince1970)
    }
    
    // 2. 连接状态刷新
    private func refreshConnectionStates() {
        Logger.shared.debug("刷新连接状态")
        
        let mountedServers = MountManager.shared.getMountedServers()
        
        for serverID in mountedServers {
            // ✅ 验证挂载状态
            if let mountPath = MountManager.shared.getMountPath(serverID: serverID) {
                if !DiskAPI.shared.isMounted(mountPath) {
                    Logger.shared.debug("[\(serverID)] 挂载路径不存在，跳过状态刷新", module: "TaskScheduler")
                    continue
                }
            } else {
                continue
            }
            
            if let instance = MountManager.shared.getMountInstance(serverID: serverID) {
                let isConnected = DiskAPI.shared.isMounted(instance.mountPath)
                if !isConnected {
                    MountManager.shared.handleConnectionStateChange(
                        serverID: serverID,
                        state: .disconnected,
                        error: "连接已断开"
                    )
                    EventBus.shared.publish(ConnectionLost(serverID: serverID))
                }
            }
        }
    }
    
    // 3. OTA版本检查
    private func checkOTAUpdates() {
        Logger.shared.debug("检查OTA更新")
        
        let autoCheck = ConfigurationManager.shared.get(key: "ota.autoCheck", defaultValue: true)
        guard autoCheck else { return }
        
        OTAManager.shared.checkForUpdates { hasUpdate in
            if hasUpdate {
                if let updateInfo = OTAManager.shared.getUpdateInfo() {
                    Logger.shared.info("发现新版本: \(updateInfo.version)")
                    EventBus.shared.publish(OTAUpdateAvailable(
                        version: updateInfo.version,
                        releaseNotes: updateInfo.releaseNotes,
                        size: updateInfo.size
                    ))
                    
                    let autoDownload = ConfigurationManager.shared.get(key: "ota.autoDownload", defaultValue: true)
                    if autoDownload {
                        self.downloadUpdateAutomatically()
                    }
                }
            }
        }
    }
    
    private func downloadUpdateAutomatically() {
        OTAManager.shared.downloadUpdate { progress in
            Logger.shared.debug("OTA下载进度: \(Int(progress * 100))%")
        } completion: { result in
            switch result {
            case .success:
                Logger.shared.info("OTA下载完成")
                let autoInstall = ConfigurationManager.shared.get(key: "ota.autoInstall", defaultValue: false)
                if autoInstall {
                    if let updateInfo = OTAManager.shared.getUpdateInfo() {
                        let packagePath = self.getUpdatePackagePath(version: updateInfo.version)
                        OTAManager.shared.installUpdate(updatePackage: URL(fileURLWithPath: packagePath)) { _ in
                            // 安装完成
                        }
                    }
                }
            case .failure(let error):
                Logger.shared.error("OTA下载失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func getUpdatePackagePath(version: String) -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("com.suvikedrive.drive")
        let updateDir = appDir.appendingPathComponent("Updates")
        return updateDir.appendingPathComponent("update_\(version).dmg").path
    }
    
    // 4. 日志清理
    private func cleanupLogs() {
        Logger.shared.debug("清理日志文件")
        Logger.shared.clearAllLogs()
    }
    
    // 5. 缓存清理
    private func cleanupCache() {
        Logger.shared.debug("清理缓存")
        let beforeSize = CacheManager.shared.totalCacheSize
        CacheManager.shared.cleanup()
        let afterSize = CacheManager.shared.totalCacheSize
        
        if beforeSize > afterSize {
            let freedSize = beforeSize - afterSize
            Logger.shared.info("缓存清理完成，释放了 \(formatFileSize(freedSize))")
            EventBus.shared.publish(CacheCleaned(
                freedSize: freedSize,
                removedCount: 0,
                reason: "定时清理"
            ))
        }
    }
    
    // 6. 自动重连监控
    private func monitorReconnections() {
        let maxRetries = ConfigurationManager.shared.get(key: "network.maxRetries", defaultValue: 3)
        let autoReconnect = ConfigurationManager.shared.get(key: "network.autoReconnect", defaultValue: true)
        
        guard autoReconnect else { return }
        
        let mountedServers = MountManager.shared.getMountedServers()
        
        for serverID in mountedServers {
            // ✅ 验证挂载状态
            if let mountPath = MountManager.shared.getMountPath(serverID: serverID) {
                if !DiskAPI.shared.isMounted(mountPath) {
                    Logger.shared.debug("[\(serverID)] 挂载路径不存在，跳过重连", module: "TaskScheduler")
                    continue
                }
            } else {
                continue
            }
            
            if let instance = MountManager.shared.getMountInstance(serverID: serverID) {
                if instance.state == .disconnected || instance.state == .error {
                    if instance.retryCount < maxRetries {
                        Logger.shared.info("尝试自动重连: \(serverID) (第 \(instance.retryCount + 1) 次)")
                        
                        let delay = TimeInterval((instance.retryCount + 1) * 5)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            // ✅ 重连前再次检查挂载状态
                            if !MountManager.shared.isMounted(serverID: serverID) {
                                Logger.shared.info("[\(serverID)] 重连前检查：已卸载，跳过重连", module: "TaskScheduler")
                                return
                            }
                            
                            MountManager.shared.mount(
                                serverID: serverID,
                                config: instance.config
                            ) { result in
                                if case .success = result {
                                    Logger.shared.info("自动重连成功: \(serverID)")
                                    EventBus.shared.publish(ConnectionReconnected(
                                        serverID: serverID,
                                        attemptCount: instance.retryCount + 1
                                    ))
                                } else {
                                    Logger.shared.warning("自动重连失败: \(serverID)")
                                    EventBus.shared.publish(ConnectionReconnectFailed(
                                        serverID: serverID,
                                        attemptCount: instance.retryCount + 1,
                                        error: "重连失败"
                                    ))
                                }
                            }
                        }
                    } else {
                        Logger.shared.warning("自动重连次数已达上限: \(serverID)")
                    }
                }
            }
        }
    }
    
    // 7. 磁盘空间监控
    private func monitorDiskSpace() {
        let mountPath = "/"
        let result = DiskAPI.shared.getDiskInfo(at: mountPath)
        
        switch result {
        case .success(let diskInfo):
            let freeSpace = diskInfo.freeSize
            let threshold: UInt64 = 1024 * 1024 * 1024
            
            if freeSpace < threshold {
                Logger.shared.warning("磁盘空间不足: \(formatFileSize(freeSpace)) 剩余")
                EventBus.shared.publish(DiskSpaceLow(
                    freeSpace: freeSpace,
                    threshold: threshold
                ))
            }
            
        case .failure:
            break
        }
    }
    
    // 8. 配置自动备份
    private func backupConfiguration() {
        Logger.shared.debug("执行配置自动备份")
        ConfigurationManager.shared.saveConfiguration()
    }
}

// MARK: - TaskStatus
struct TaskStatus {
    let id: String
    let name: String
    let isRunning: Bool
    let isPaused: Bool
    let isEnabled: Bool
    let lastRun: Date?
    let nextRun: Date?
    let runCount: Int
    let lastError: String?
    let interval: TimeInterval
    let priority: TaskPriority
}
