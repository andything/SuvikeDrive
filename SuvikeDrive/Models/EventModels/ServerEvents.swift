//
//  ServerEvents.swift
//  SuvikeDrive
//
//  功能: 服务器实例CRUD、服务器配置双向请求响应、文件列表加载事件、服务器切换事件
//

import AppKit
import Foundation

// MARK: - 服务器实例CRUD
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

// MARK: - 服务器配置请求 (UI → 业务层)
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

// MARK: - 服务器配置响应 (业务层 → UI)
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

// MARK: - 文件列表加载
struct FileListLoaded: Event {
    let serverID: String
    let count: Int
    let timestamp: Date
    
    init(serverID: String, count: Int) {
        self.serverID = serverID
        self.count = count
        self.timestamp = Date()
    }
}

// MARK: - 服务器切换事件
struct ServerSwitchRequested: Event {
    let eventName: String = "serverSwitchRequested"
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct ServerSwitched: Event {
    let eventName: String = "serverSwitched"
    let serverID: String
    let serverName: String
    let timestamp: Date
    
    init(serverID: String, serverName: String) {
        self.serverID = serverID
        self.serverName = serverName
        self.timestamp = Date()
    }
}

struct ServerSwitchFailed: Event {
    let eventName: String = "serverSwitchFailed"
    let serverID: String
    let error: String
    let timestamp: Date
    
    init(serverID: String, error: String) {
        self.serverID = serverID
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - 服务器列表更新事件
struct ServerListUpdated: Event {
    let eventName: String = "serverListUpdated"
    let servers: [ServerConfig]
    let timestamp: Date
    
    init(servers: [ServerConfig]) {
        self.servers = servers
        self.timestamp = Date()
    }
}

// MARK: - 文件管理器事件
struct OpenFileBrowserRequest: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct CloseFileBrowserRequest: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct FileBrowserOpenedEvent: Event {
    let serverID: String
    let mountPath: String
    let timestamp: Date
    
    init(serverID: String, mountPath: String) {
        self.serverID = serverID
        self.mountPath = mountPath
        self.timestamp = Date()
    }
}

struct FileBrowserClosedEvent: Event {
    let serverID: String
    let timestamp: Date
    
    init(serverID: String) {
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct FileBrowserErrorEvent: Event {
    let serverID: String
    let error: String
    let timestamp: Date
    
    init(serverID: String, error: String) {
        self.serverID = serverID
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - 流量统计事件
struct TrafficStatsUpdated: Event {
    let downloadSpeed: Double
    let uploadSpeed: Double
    let totalDownload: UInt64
    let totalUpload: UInt64
    let timestamp: Date
    
    init(downloadSpeed: Double, uploadSpeed: Double, totalDownload: UInt64, totalUpload: UInt64) {
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.totalDownload = totalDownload
        self.totalUpload = totalUpload
        self.timestamp = Date()
    }
}

// MARK: - 服务器缓存大小变化事件
struct ServerCacheSizeChanged: Event {
    let serverID: String
    let serverName: String
    let formattedSize: String
    let timestamp: Date
    
    init(serverID: String, serverName: String, formattedSize: String) {
        self.serverID = serverID
        self.serverName = serverName
        self.formattedSize = formattedSize
        self.timestamp = Date()
    }
}
