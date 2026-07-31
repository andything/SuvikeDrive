//
//  CommonEvents.swift
//  SuvikeDrive
//
//  功能: 全局错误、通用任务、缓存、日志、弹窗确认等通用杂项事件
//

import AppKit
import Foundation

// MARK: - 全局异常错误
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

// MARK: - 通用后台任务
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

// MARK: - 缓存管理事件
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

// MARK: - 退出卸载确认弹窗
struct UnmountConfirmationResult: Event {
    let choice: UnmountChoice
}

enum UnmountChoice {
    case unmountAll
    case cancel
    case forceQuit
}
