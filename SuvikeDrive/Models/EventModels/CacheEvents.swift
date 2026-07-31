//
//  CacheEvents.swift
//  SuvikeDrive
//
//  功能: 缓存相关事件
//

import Foundation

// MARK: - 缓存清除事件
struct CacheCleared: Event {
    let eventName: String = "cacheCleared"
    let serverID: String?
    
    init(serverID: String? = nil) {
        self.serverID = serverID
    }
}

// MARK: - 缓存大小变化事件
struct CacheSizeChanged: Event {
    let eventName: String = "cacheSizeChanged"
    let totalSize: UInt64
    let formattedSize: String
}

// MARK: - 缓存错误事件
struct CacheErrorEvent: Event {
    let eventName: String = "cacheError"
    let error: String
    let serverID: String?
}

// MARK: - 请求缓存大小事件
struct RequestCacheSize: Event {
    let eventName: String = "requestCacheSize"
}
