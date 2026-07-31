//
//  MountEvents.swift
//  SuvikeDrive
//
//  功能: 磁盘挂载、卸载、批量挂载、桌面软链接相关事件
//

import AppKit
import Foundation

// MARK: - 单次挂载事件
struct MountCompleted: Event {
    let serverID: String
    let mountPath: String
    let success: Bool
    let error: String?
    let timestamp: Date
    
    init(serverID: String, mountPath: String, success: Bool = true, error: String? = nil) {
        self.serverID = serverID
        self.mountPath = mountPath
        self.success = success
        self.error = error
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

// MARK: - 单次卸载事件
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

// MARK: - 服务器挂载/卸载通知（用于 AppDelegate 监听）
struct ServerMountedEvent: Event {
    let serverID: String
    let mountPath: String
    let timestamp: Date
    
    init(serverID: String, mountPath: String) {
        self.serverID = serverID
        self.mountPath = mountPath
        self.timestamp = Date()
    }
}

struct ServerUnmountedEvent: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

// MARK: - 桌面符号链接卸载请求
struct UnmountDesktopSymlinkRequest: Event {
    let serverID: String
    let volumeName: String
}

// MARK: - 批量挂载事件
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
