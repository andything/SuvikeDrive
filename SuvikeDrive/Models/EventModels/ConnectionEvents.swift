//
//  ConnectionEvents.swift
//  SuvikeDrive
//
//  功能: 连接状态、心跳、重连、网络连通性测试事件
//

import AppKit
import Foundation

// MARK: - 连接状态变更事件
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

// MARK: - 网络连通测试
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
