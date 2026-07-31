//
//  TaskModel.swift
//  SuvikeDrive
//
//  功能:  定时任务基础数据模型
//

import AppKit
import Foundation

// MARK: - 基础任务模型
struct TaskModel: Codable {
    let id: String
    var name: String
    var type: TaskType
    var interval: TimeInterval
    var isEnabled: Bool
    var isPaused: Bool  // ✅ 添加这个属性
    var createdAt: Date
    var lastRun: Date?
    var nextRun: Date?
    var runCount: Int
    var lastError: String?
    
    init(
        id: String = UUID().uuidString,
        name: String,
        type: TaskType,
        interval: TimeInterval,
        isEnabled: Bool = true,
        isPaused: Bool = false  // ✅ 添加参数
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.interval = interval
        self.isEnabled = isEnabled
        self.isPaused = isPaused
        self.createdAt = Date()
        self.lastRun = nil
        self.nextRun = nil
        self.runCount = 0
        self.lastError = nil
    }
    
    mutating func recordRun() {
        lastRun = Date()
        nextRun = Date().addingTimeInterval(interval)
        runCount += 1
    }
    
    mutating func recordError(_ error: String) {
        lastError = error
    }
    
    func isDue() -> Bool {
        guard isEnabled else { return false }
        guard let nextRun = nextRun else { return true }
        return Date() >= nextRun
    }
}

// MARK: - 任务执行记录
struct TaskExecutionRecord: Codable {  // ✅ 添加 Codable
    let taskID: String
    let timestamp: Date
    let success: Bool
    let duration: TimeInterval
}

// MARK: - 任务统计
struct TaskStatistics: Codable {
    var totalTasks: Int
    var enabledTasks: Int
    var runningTasks: Int
    var totalExecutions: Int
    var totalErrors: Int
    var averageExecutionTime: TimeInterval
    var lastUpdated: Date
    
    init() {
        totalTasks = 0
        enabledTasks = 0
        runningTasks = 0
        totalExecutions = 0
        totalErrors = 0
        averageExecutionTime = 0
        lastUpdated = Date()
    }
}

// MARK: - 其他类型
enum TaskType: String, Codable {
    case heartbeat
    case connectionRefresh
    case otaCheck
    case logCleanup
    case cacheCleanup
    case reconnectMonitor
    case custom
}

// MARK: - 心跳任务
struct HeartbeatTask: Codable {
    let serverID: String
    var lastHeartbeat: Date?
    var heartbeatCount: Int
    var successCount: Int
    var failureCount: Int
    var lastResult: HeartbeatResult
    
    init(serverID: String) {
        self.serverID = serverID
        self.lastHeartbeat = nil
        self.heartbeatCount = 0
        self.successCount = 0
        self.failureCount = 0
        self.lastResult = .pending
    }
    
    mutating func recordResult(_ success: Bool) {
        heartbeatCount += 1
        lastHeartbeat = Date()
        
        if success {
            successCount += 1
            lastResult = .success
        } else {
            failureCount += 1
            lastResult = .failure
        }
    }
    
    var successRate: Double {
        guard heartbeatCount > 0 else { return 0 }
        return Double(successCount) / Double(heartbeatCount)
    }
    
    var isHealthy: Bool {
        return successRate > 0.8
    }
}

enum HeartbeatResult: String, Codable {
    case pending
    case success
    case failure
}

// MARK: - 自动重连任务
struct ReconnectTask: Codable {
    let serverID: String
    var reconnectCount: Int
    var maxReconnectAttempts: Int
    var lastReconnect: Date?
    var nextReconnect: Date?
    var isReconnecting: Bool
    var lastError: String?
    
    init(serverID: String, maxReconnectAttempts: Int = 3) {
        self.serverID = serverID
        self.reconnectCount = 0
        self.maxReconnectAttempts = maxReconnectAttempts
        self.lastReconnect = nil
        self.nextReconnect = nil
        self.isReconnecting = false
        self.lastError = nil
    }
    
    mutating func recordReconnect() {
        reconnectCount += 1
        lastReconnect = Date()
        let delay = TimeInterval(reconnectCount * 5)
        nextReconnect = Date().addingTimeInterval(delay)
    }
    
    mutating func reset() {
        reconnectCount = 0
        isReconnecting = false
        lastError = nil
    }
    
    var canReconnect: Bool {
        return reconnectCount < maxReconnectAttempts
    }
    
    var isRetryDue: Bool {
        guard let nextReconnect = nextReconnect else { return true }
        return Date() >= nextReconnect
    }
}

// MARK: - OTA检查任务
struct OTACheckTask: Codable {
    var lastCheck: Date?
    var checkInterval: TimeInterval
    var lastVersion: String?
    var hasUpdate: Bool
    var updateVersion: String?
    var checkCount: Int
    
    init(checkInterval: TimeInterval = 21600) {
        self.lastCheck = nil
        self.checkInterval = checkInterval
        self.lastVersion = nil
        self.hasUpdate = false
        self.updateVersion = nil
        self.checkCount = 0
    }
    
    mutating func recordCheck(version: String, hasUpdate: Bool) {
        lastCheck = Date()
        checkCount += 1
        lastVersion = version
        self.hasUpdate = hasUpdate
        if hasUpdate {
            updateVersion = version
        }
    }
    
    var isDue: Bool {
        guard let lastCheck = lastCheck else { return true }
        return Date().timeIntervalSince(lastCheck) >= checkInterval
    }
}

// MARK: - 日志清理任务
struct LogCleanupTask: Codable {
    var lastCleanup: Date?
    var cleanupInterval: TimeInterval
    var maxKeepDays: Int
    var maxArchiveCount: Int
    var cleanupCount: Int
    var lastCleanupSize: UInt64
    
    init(maxKeepDays: Int = 30, maxArchiveCount: Int = 20) {
        self.lastCleanup = nil
        self.cleanupInterval = 86400
        self.maxKeepDays = maxKeepDays
        self.maxArchiveCount = maxArchiveCount
        self.cleanupCount = 0
        self.lastCleanupSize = 0
    }
    
    mutating func recordCleanup(size: UInt64) {
        lastCleanup = Date()
        cleanupCount += 1
        lastCleanupSize = size
    }
    
    var isDue: Bool {
        guard let lastCleanup = lastCleanup else { return true }
        return Date().timeIntervalSince(lastCleanup) >= cleanupInterval
    }
}
