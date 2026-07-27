//
//  ConnectionModel.swift
//  SuvikeDrive
//
//  功能:  活动连接实例模型（服务器ID、挂载路径、连接创建时间）
//        全局连接统计模型（总挂载数、在线连接数、异常断开次数）
//        单连接状态快照模型，用于UI实时展示
//

import AppKit
import Foundation

// MARK: - 活动连接实例
struct ConnectionInstance {
    let serverID: String
    let serverName: String
    let protocolType: ProtocolType
    let mountPath: String
    let remoteURL: String
    let connectedAt: Date
    var lastActivity: Date
    var state: ConnectionState
    var bytesTransferred: UInt64
    var errorMessage: String?
    var sessionID: String
    
    init(
        serverID: String,
        serverName: String,
        protocolType: ProtocolType,
        mountPath: String,
        remoteURL: String
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.protocolType = protocolType
        self.mountPath = mountPath
        self.remoteURL = remoteURL
        self.connectedAt = Date()
        self.lastActivity = Date()
        self.state = .connecting
        self.bytesTransferred = 0
        self.errorMessage = nil
        self.sessionID = UUID().uuidString
    }
    
    var uptime: TimeInterval {
        return Date().timeIntervalSince(connectedAt)
    }
    
    var idleTime: TimeInterval {
        return Date().timeIntervalSince(lastActivity)
    }
    
    var isActive: Bool {
        return state == .mounted || state == .connecting || state == .connected
    }
    
    var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - 连接统计
struct ConnectionStatistics: Codable {
    var totalMounts: Int
    var activeConnections: Int
    var errorConnections: Int
    var disconnectedConnections: Int
    var totalBytesTransferred: UInt64
    var totalUptime: TimeInterval
    var errorCount: Int
    var lastError: String?
    var lastErrorTime: Date?
    var peakConnections: Int
    var createdAt: Date
    var updatedAt: Date
    
    init() {
        self.totalMounts = 0
        self.activeConnections = 0
        self.errorConnections = 0
        self.disconnectedConnections = 0
        self.totalBytesTransferred = 0
        self.totalUptime = 0
        self.errorCount = 0
        self.lastError = nil
        self.lastErrorTime = nil
        self.peakConnections = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var formattedTotalBytes: String {
        return Utils.shared.formatFileSize(totalBytesTransferred)
    }
    
    var connectionRate: Double {
        guard totalMounts > 0 else { return 0 }
        return Double(activeConnections) / Double(totalMounts)
    }
}

// MARK: - 连接状态快照
struct ConnectionSnapshot {
    let serverID: String
    let serverName: String
    let state: ConnectionState
    let mountPath: String
    let remoteURL: String
    let protocolType: ProtocolType
    let uptime: TimeInterval
    let idleTime: TimeInterval
    let bytesTransferred: UInt64
    let errorMessage: String?
    let timestamp: Date
    
    init(from instance: ConnectionInstance) {
        self.serverID = instance.serverID
        self.serverName = instance.serverName
        self.state = instance.state
        self.mountPath = instance.mountPath
        self.remoteURL = instance.remoteURL
        self.protocolType = instance.protocolType
        self.uptime = instance.uptime
        self.idleTime = instance.idleTime
        self.bytesTransferred = instance.bytesTransferred
        self.errorMessage = instance.errorMessage
        self.timestamp = Date()
    }
    
    var stateDisplay: String {
        switch state {
        case .idle: return "空闲"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .mounted: return "已挂载"
        case .disconnecting: return "断开中"
        case .disconnected: return "已断开"
        case .error: return "错误"
        case .reconnecting: return "重连中"
        }
    }
    
    var stateColor: String {
        switch state {
        case .idle: return "gray"
        case .connecting: return "orange"
        case .connected: return "blue"
        case .mounted: return "green"
        case .disconnecting: return "orange"
        case .disconnected: return "gray"
        case .error: return "red"
        case .reconnecting: return "orange"
        }
    }
}

// MARK: - 连接历史记录
struct ConnectionHistory: Codable {
    let serverID: String
    let timestamp: Date
    let event: ConnectionEvent
    let details: String?
    
    init(serverID: String, event: ConnectionEvent, details: String? = nil) {
        self.serverID = serverID
        self.timestamp = Date()
        self.event = event
        self.details = details
    }
}

enum ConnectionEvent: String, Codable {
    case connected
    case disconnected
    case reconnected
    case error
    case heartbeat
    case mount
    case unmount
    case transferStart
    case transferComplete
    case transferError
}

// MARK: - 连接配置
struct ConnectionConfig: Codable {
    var maxConnections: Int
    var maxRetries: Int
    var retryDelay: TimeInterval
    var timeout: TimeInterval
    var keepAliveInterval: TimeInterval
    var autoReconnect: Bool
    
    static let `default` = ConnectionConfig(
        maxConnections: 10,
        maxRetries: 3,
        retryDelay: 5,
        timeout: 30,
        keepAliveInterval: 30,
        autoReconnect: true
    )
}

// MARK: - 批量操作结果
struct BatchOperationResult: Codable {
    var total: Int
    var success: Int
    var failed: Int
    var errors: [String: String]
    var startedAt: Date
    var completedAt: Date?
    
    init(total: Int) {
        self.total = total
        self.success = 0
        self.failed = 0
        self.errors = [:]
        self.startedAt = Date()
        self.completedAt = nil
    }
    
    var isComplete: Bool {
        return success + failed >= total
    }
    
    var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(success) / Double(total)
    }
    
    mutating func recordSuccess() {
        success += 1
        if isComplete {
            completedAt = Date()
        }
    }
    
    mutating func recordFailure(serverID: String, error: String) {
        failed += 1
        errors[serverID] = error
        if isComplete {
            completedAt = Date()
        }
    }
}
