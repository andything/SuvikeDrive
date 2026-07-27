//
//  EventModels.swift
//  SuvikeDrive
//
//  功能:  远程磁盘挂载完成事件结构体（挂载路径、服务器ID）
//        远程磁盘卸载完成事件结构体
//        服务器连接状态变更事件结构体（状态、错误信息）
//        全局统一异常错误事件结构体（错误码、文案、服务器ID）
//        文件上传/下载实时进度回调事件（文件大小、已传输、服务器ID）
//        全局配置修改变更事件结构体（变更字段、旧值/新值）
//        应用版本更新通知事件结构体（新版本号、更新日志）
//

import AppKit
import Foundation

// MARK: - 应用生命周期事件
struct AppDidFinishLaunching: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct AppWillTerminate: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct AppDidBecomeActive: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct AppWillResignActive: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

// MARK: - 挂载事件
struct MountCompleted: Event {
    let serverID: String
    let mountPath: String
    let timestamp: Date
    
    init(serverID: String, mountPath: String) {
        self.serverID = serverID
        self.mountPath = mountPath
        self.timestamp = Date()
    }
}

struct MountFailed: Event {
    let serverID: String
    let error: String
    let timestamp: Date
    
    init(serverID: String, error: String) {
        self.serverID = serverID
        self.error = error
        self.timestamp = Date()
    }
}

struct MountStarted: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct UnmountCompleted: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct UnmountFailed: Event {
    let serverID: String
    let error: String
    let timestamp: Date
    
    init(serverID: String, error: String) {
        self.serverID = serverID
        self.error = error
        self.timestamp = Date()
    }
}

struct UnmountStarted: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

// MARK: - 批量操作事件
struct BatchMountStarted: Event {
    let totalCount: Int
    let timestamp: Date
    
    init(totalCount: Int) {
        self.totalCount = totalCount
        self.timestamp = Date()
    }
}

struct BatchMountProgress: Event {
    let completed: Int
    let total: Int
    let serverID: String
    let success: Bool
    let error: String?
    let timestamp: Date
    
    init(completed: Int, total: Int, serverID: String, success: Bool, error: String? = nil) {
        self.completed = completed
        self.total = total
        self.serverID = serverID
        self.success = success
        self.error = error
        self.timestamp = Date()
    }
}

struct BatchMountCompleted: Event {
    let successCount: Int
    let totalCount: Int
    let failedServers: [String: String]
    let timestamp: Date
    
    init(successCount: Int, totalCount: Int, failedServers: [String: String] = [:]) {
        self.successCount = successCount
        self.totalCount = totalCount
        self.failedServers = failedServers
        self.timestamp = Date()
    }
}

// MARK: - 连接状态事件
struct ConnectionStateChanged: Event {
    let serverID: String
    let state: ConnectionState
    let error: String?
    let timestamp: Date
    
    init(serverID: String, state: ConnectionState, error: String? = nil) {
        self.serverID = serverID
        self.state = state
        self.error = error
        self.timestamp = Date()
    }
}

struct HeartbeatReceived: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct HeartbeatFailed: Event {
    let serverID: String
    let error: String?
    let timestamp: Date
    
    init(serverID: String, error: String? = nil) {
        self.serverID = serverID
        self.error = error
        self.timestamp = Date()
    }
}

struct ConnectionLost: Event {
    let serverID: String
    let reason: String?
    let timestamp: Date
    
    init(serverID: String, reason: String? = nil) {
        self.serverID = serverID
        self.reason = reason
        self.timestamp = Date()
    }
}

struct ConnectionReconnected: Event {
    let serverID: String
    let attemptCount: Int
    let timestamp: Date
    
    init(serverID: String, attemptCount: Int) {
        self.serverID = serverID
        self.attemptCount = attemptCount
        self.timestamp = Date()
    }
}

struct ConnectionReconnectFailed: Event {
    let serverID: String
    let attemptCount: Int
    let error: String
    let timestamp: Date
    
    init(serverID: String, attemptCount: Int, error: String) {
        self.serverID = serverID
        self.attemptCount = attemptCount
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - 传输事件
struct TransferStarted: Event {
    let transferID: String
    let serverID: String
    let filePath: String
    let localPath: String
    let totalBytes: UInt64
    let isUpload: Bool
    let timestamp: Date
    
    init(transferID: String, serverID: String, filePath: String, localPath: String, totalBytes: UInt64, isUpload: Bool) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.isUpload = isUpload
        self.timestamp = Date()
    }
}

struct TransferProgress: Event {
    let transferID: String
    let serverID: String
    let bytesTransferred: UInt64
    let totalBytes: UInt64
    let speed: UInt64
    let timestamp: Date
    
    init(transferID: String, serverID: String, bytesTransferred: UInt64, totalBytes: UInt64, speed: UInt64 = 0) {
        self.transferID = transferID
        self.serverID = serverID
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.speed = speed
        self.timestamp = Date()
    }
    
    var progress: Double {
        return totalBytes > 0 ? Double(bytesTransferred) / Double(totalBytes) : 0
    }
    
    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }
    
    var remainingBytes: UInt64 {
        return totalBytes - bytesTransferred
    }
    
    var estimatedRemainingTime: TimeInterval? {
        guard speed > 0 && remainingBytes > 0 else { return nil }
        return TimeInterval(remainingBytes) / TimeInterval(speed)
    }
}

struct TransferCompleted: Event {
    let transferID: String
    let serverID: String
    let filePath: String
    let totalBytes: UInt64
    let duration: TimeInterval
    let timestamp: Date
    
    init(transferID: String, serverID: String, filePath: String, totalBytes: UInt64, duration: TimeInterval) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.totalBytes = totalBytes
        self.duration = duration
        self.timestamp = Date()
    }
    
    var averageSpeed: UInt64 {
        return duration > 0 ? UInt64(Double(totalBytes) / duration) : 0
    }
}

struct TransferFailed: Event {
    let transferID: String
    let serverID: String
    let filePath: String
    let error: String
    let bytesTransferred: UInt64
    let timestamp: Date
    
    init(transferID: String, serverID: String, filePath: String, error: String, bytesTransferred: UInt64) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.error = error
        self.bytesTransferred = bytesTransferred
        self.timestamp = Date()
    }
}

struct TransferPaused: Event {
    let transferID: String
    let serverID: String
    let timestamp: Date
    
    init(transferID: String, serverID: String) {
        self.transferID = transferID
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct TransferResumed: Event {
    let transferID: String
    let serverID: String
    let timestamp: Date
    
    init(transferID: String, serverID: String) {
        self.transferID = transferID
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct TransferCancelled: Event {
    let transferID: String
    let serverID: String
    let timestamp: Date
    
    init(transferID: String, serverID: String) {
        self.transferID = transferID
        self.serverID = serverID
        self.timestamp = Date()
    }
}

// MARK: - 错误事件
struct GlobalError: Event {
    let errorCode: String
    let message: String
    let serverID: String?
    let details: [String: Any]?
    let severity: ErrorSeverity
    let timestamp: Date
    
    init(errorCode: String, message: String, serverID: String? = nil, details: [String: Any]? = nil, severity: ErrorSeverity = .error) {
        self.errorCode = errorCode
        self.message = message
        self.serverID = serverID
        self.details = details
        self.severity = severity
        self.timestamp = Date()
    }
}

enum ErrorSeverity: String {
    case info
    case warning
    case error
    case critical
}

// MARK: - 配置事件
struct ConfigurationChanged: Event {
    let key: String
    let oldValue: Any?
    let newValue: Any?
    let timestamp: Date
    
    init(key: String, oldValue: Any?, newValue: Any?) {
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}

struct ConfigurationImported: Event {
    let source: String
    let format: String
    let timestamp: Date
    
    init(source: String, format: String) {
        self.source = source
        self.format = format
        self.timestamp = Date()
    }
}

struct ConfigurationExported: Event {
    let destination: String
    let format: String
    let timestamp: Date
    
    init(destination: String, format: String) {
        self.destination = destination
        self.format = format
        self.timestamp = Date()
    }
}

struct ConfigurationBackupCreated: Event {
    let backupFile: String
    let timestamp: Date
    
    init(backupFile: String) {
        self.backupFile = backupFile
        self.timestamp = Date()
    }
}

struct ConfigurationBackupRestored: Event {
    let backupFile: String
    let timestamp: Date
    
    init(backupFile: String) {
        self.backupFile = backupFile
        self.timestamp = Date()
    }
}

// MARK: - OTA更新事件
struct OTAUpdateAvailable: Event {
    let version: String
    let releaseNotes: String?
    let size: Int64
    let timestamp: Date
    
    init(version: String, releaseNotes: String? = nil, size: Int64 = 0) {
        self.version = version
        self.releaseNotes = releaseNotes
        self.size = size
        self.timestamp = Date()
    }
}

struct OTADownloadProgress: Event {
    let version: String
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let timestamp: Date
    
    init(version: String, progress: Double, downloadedBytes: Int64, totalBytes: Int64) {
        self.version = version
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.timestamp = Date()
    }
}

struct OTADownloadComplete: Event {
    let version: String
    let packagePath: String
    let timestamp: Date
    
    init(version: String, packagePath: String) {
        self.version = version
        self.packagePath = packagePath
        self.timestamp = Date()
    }
}

struct OTAInstallStarted: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTAInstallComplete: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTAInstallFailed: Event {
    let version: String
    let error: String
    let timestamp: Date
    
    init(version: String, error: String) {
        self.version = version
        self.error = error
        self.timestamp = Date()
    }
}

struct OTARollbackStarted: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTARollbackComplete: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

// MARK: - 任务事件
struct TaskStarted: Event {
    let taskID: String
    let taskName: String
    let timestamp: Date
    
    init(taskID: String, taskName: String) {
        self.taskID = taskID
        self.taskName = taskName
        self.timestamp = Date()
    }
}

struct TaskCompleted: Event {
    let taskID: String
    let taskName: String
    let duration: TimeInterval
    let timestamp: Date
    
    init(taskID: String, taskName: String, duration: TimeInterval) {
        self.taskID = taskID
        self.taskName = taskName
        self.duration = duration
        self.timestamp = Date()
    }
}

struct TaskError: Event {
    let taskID: String
    let taskName: String
    let error: String
    let timestamp: Date
    
    init(taskID: String, taskName: String, error: String) {
        self.taskID = taskID
        self.taskName = taskName
        self.error = error
        self.timestamp = Date()
    }
}

struct TaskPaused: Event {
    let taskID: String
    let taskName: String
    let timestamp: Date
    
    init(taskID: String, taskName: String) {
        self.taskID = taskID
        self.taskName = taskName
        self.timestamp = Date()
    }
}

struct TaskResumed: Event {
    let taskID: String
    let taskName: String
    let timestamp: Date
    
    init(taskID: String, taskName: String) {
        self.taskID = taskID
        self.taskName = taskName
        self.timestamp = Date()
    }
}

// MARK: - 缓存事件
struct CacheCleaned: Event {
    let freedSize: UInt64
    let removedCount: Int
    let reason: String
    let timestamp: Date
    
    init(freedSize: UInt64, removedCount: Int, reason: String) {
        self.freedSize = freedSize
        self.removedCount = removedCount
        self.reason = reason
        self.timestamp = Date()
    }
}

struct CacheSizeExceeded: Event {
    let currentSize: UInt64
    let maxSize: UInt64
    let timestamp: Date
    
    init(currentSize: UInt64, maxSize: UInt64) {
        self.currentSize = currentSize
        self.maxSize = maxSize
        self.timestamp = Date()
    }
}

struct CacheCleared: Event {
    let freedSize: UInt64
    let timestamp: Date
    
    init(freedSize: UInt64) {
        self.freedSize = freedSize
        self.timestamp = Date()
    }
}

// MARK: - 服务器事件
struct ServerAdded: Event {
    let serverID: String
    let serverName: String
    let timestamp: Date
    
    init(serverID: String, serverName: String) {
        self.serverID = serverID
        self.serverName = serverName
        self.timestamp = Date()
    }
}

struct ServerUpdated: Event {
    let serverID: String
    let serverName: String
    let changes: [String: Any]
    let timestamp: Date
    
    init(serverID: String, serverName: String, changes: [String: Any]) {
        self.serverID = serverID
        self.serverName = serverName
        self.changes = changes
        self.timestamp = Date()
    }
}

struct ServerRemoved: Event {
    let serverID: String
    let serverName: String
    let timestamp: Date
    
    init(serverID: String, serverName: String) {
        self.serverID = serverID
        self.serverName = serverName
        self.timestamp = Date()
    }
}

// MARK: - 权限事件
struct PermissionGranted: Event {
    let permissionType: String
    let timestamp: Date
    
    init(permissionType: String) {
        self.permissionType = permissionType
        self.timestamp = Date()
    }
}

struct PermissionDenied: Event {
    let permissionType: String
    let timestamp: Date
    
    init(permissionType: String) {
        self.permissionType = permissionType
        self.timestamp = Date()
    }
}

struct PermissionRequired: Event {
    let permissionType: String
    let message: String
    let timestamp: Date
    
    init(permissionType: String, message: String) {
        self.permissionType = permissionType
        self.message = message
        self.timestamp = Date()
    }
}

struct PermissionStatusUpdated: Event {
    let permissionType: String
    let isGranted: Bool
    let timestamp: Date
    
    init(permissionType: String, isGranted: Bool) {
        self.permissionType = permissionType
        self.isGranted = isGranted
        self.timestamp = Date()
    }
}

struct RequestPermissionEvent: Event {
    let permissionType: String
    let timestamp: Date
    
    init(permissionType: String) {
        self.permissionType = permissionType
        self.timestamp = Date()
    }
}

// MARK: - 日志事件
struct LogEntryEvent: Event {
    let level: String
    let module: String
    let message: String
    let timestamp: Date
    
    init(level: String, module: String, message: String) {
        self.level = level
        self.module = module
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - 系统事件
struct SystemSleep: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct SystemWake: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct NetworkChanged: Event {
    let isConnected: Bool
    let timestamp: Date
    
    init(isConnected: Bool) {
        self.isConnected = isConnected
        self.timestamp = Date()
    }
}

struct DiskSpaceLow: Event {
    let freeSpace: UInt64
    let threshold: UInt64
    let timestamp: Date
    
    init(freeSpace: UInt64, threshold: UInt64) {
        self.freeSpace = freeSpace
        self.threshold = threshold
        self.timestamp = Date()
    }
}

// MARK: - 服务器配置请求事件 (UI → 业务层)
struct SaveServerConfigRequest: Event {
    let serverID: String?
    let isEditing: Bool
    let config: ServerConfig
    let timestamp: Date
    
    init(serverID: String? = nil, isEditing: Bool, config: ServerConfig) {
        self.serverID = serverID
        self.isEditing = isEditing
        self.config = config
        self.timestamp = Date()
    }
}

struct LoadServerConfigRequest: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct DeleteServerConfigRequest: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct LoadServerListRequest: Event {
    let timestamp: Date
    
    init() {
        self.timestamp = Date()
    }
}

// MARK: - 服务器配置响应事件 (业务层 → UI)
struct ServerConfigLoaded: Event {
    let serverID: String
    let config: ServerConfig
    let timestamp: Date
    
    init(serverID: String, config: ServerConfig) {
        self.serverID = serverID
        self.config = config
        self.timestamp = Date()
    }
}

struct ServerConfigSaved: Event {
    let serverID: String
    let success: Bool
    let error: String?
    let timestamp: Date
    
    init(serverID: String, success: Bool, error: String? = nil) {
        self.serverID = serverID
        self.success = success
        self.error = error
        self.timestamp = Date()
    }
}

struct ServerConfigDeleted: Event {
    let serverID: String
    let success: Bool
    let error: String?
    let timestamp: Date
    
    init(serverID: String, success: Bool, error: String? = nil) {
        self.serverID = serverID
        self.success = success
        self.error = error
        self.timestamp = Date()
    }
}

struct ServerListLoaded: Event {
    let servers: [ServerConfig]
    let timestamp: Date
    
    init(servers: [ServerConfig]) {
        self.servers = servers
        self.timestamp = Date()
    }
}

// MARK: - 网络测试事件
struct TestConnectionRequest: Event {
    let config: ServerConfig
    let timestamp: Date
    
    init(config: ServerConfig) {
        self.config = config
        self.timestamp = Date()
    }
}

struct TestConnectionResultEvent: Event {
    let result: NetworkTestResult
    let timestamp: Date
    
    init(result: NetworkTestResult) {
        self.result = result
        self.timestamp = Date()
    }
}

// MARK: - 配置读写事件 (SettingsView 使用)
struct LoadSettingsRequest: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct SaveSettingsRequest: Event {
    let settings: [String: Any]
    let timestamp: Date
    init(settings: [String: Any]) {
        self.settings = settings
        self.timestamp = Date()
    }
}

struct SettingsLoaded: Event {
    let settings: [String: Any]
    let timestamp: Date
    init(settings: [String: Any]) {
        self.settings = settings
        self.timestamp = Date()
    }
}

struct SettingsSaved: Event {
    let success: Bool
    let error: String?
    let timestamp: Date
    init(success: Bool, error: String? = nil) {
        self.success = success
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - 看门狗和守护进程事件

// 请求事件 (UI → 业务层)
struct ToggleWatchdogRequest: Event {
    let enabled: Bool
    let timestamp: Date
    init(enabled: Bool) {
        self.enabled = enabled
        self.timestamp = Date()
    }
}

struct ToggleDaemonRequest: Event {
    let enabled: Bool
    let timestamp: Date
    init(enabled: Bool) {
        self.enabled = enabled
        self.timestamp = Date()
    }
}

struct RefreshWatchdogStatusRequest: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

// 响应事件 (业务层 → UI)
struct WatchdogStatusUpdated: Event {
    let isInstalled: Bool
    let isRunning: Bool
    let isEnabled: Bool  // 用户配置是否开启
    let timestamp: Date
    init(isInstalled: Bool, isRunning: Bool, isEnabled: Bool) {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }
}

struct DaemonStatusUpdated: Event {
    let isInstalled: Bool
    let isRunning: Bool
    let isEnabled: Bool
    let timestamp: Date
    init(isInstalled: Bool, isRunning: Bool, isEnabled: Bool) {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }
}
