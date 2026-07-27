//
//  CacheModel.swift
//  SuvikeDrive
//
//  功能: 文件列表缓存数据表结构（服务器ID、路径、文件数组、过期时间）
//        缩略图缓存数据表结构（文件唯一标识、图片二进制、尺寸、过期时间）
//        传输断点缓存结构（文件路径、已传输字节、服务器ID、创建时间）
//        缓存容量统计模型、缓存清理记录模型
//

import AppKit
import Foundation

// MARK: - 文件列表缓存
struct FileListCacheModel: Codable {
    let serverID: String
    let path: String
    let files: [FileCacheItem]
    let cachedAt: Date
    let expiresAt: Date
    
    init(serverID: String, path: String, files: [FileCacheItem], ttl: TimeInterval = 300) {
        self.serverID = serverID
        self.path = path
        self.files = files
        self.cachedAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttl)
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var isValid: Bool {
        return !isExpired
    }
}

struct FileCacheItem: Codable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modificationDate: Date
    let permissions: String
    
    init(name: String, path: String, isDirectory: Bool, size: UInt64, modificationDate: Date, permissions: String) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
    }
}

// MARK: - 缩略图缓存
struct ThumbnailCacheModel: Codable {
    let fileID: String
    let imageData: Data
    let width: Int
    let height: Int
    let cachedAt: Date
    let expiresAt: Date
    
    init(fileID: String, imageData: Data, width: Int, height: Int, ttl: TimeInterval = 86400) {
        self.fileID = fileID
        self.imageData = imageData
        self.width = width
        self.height = height
        self.cachedAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttl)
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var isValid: Bool {
        return !isExpired
    }
    
    var size: UInt64 {
        return UInt64(imageData.count)
    }
}

// MARK: - 传输断点缓存
struct TransferCacheModel: Codable {
    let transferID: String
    let serverID: String
    let filePath: String
    let localPath: String
    let totalBytes: UInt64
    var transferredBytes: UInt64
    let isUpload: Bool
    let createdAt: Date
    var lastUpdated: Date
    
    init(transferID: String, serverID: String, filePath: String, localPath: String, totalBytes: UInt64, isUpload: Bool) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.transferredBytes = 0
        self.isUpload = isUpload
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
    
    var progress: Double {
        return totalBytes > 0 ? Double(transferredBytes) / Double(totalBytes) : 0
    }
    
    var isComplete: Bool {
        return transferredBytes >= totalBytes
    }
    
    var isExpired: Bool {
        let expirationTime: TimeInterval = 86400 // 24小时
        return Date().timeIntervalSince(lastUpdated) > expirationTime
    }
}

// MARK: - 缓存统计
struct CacheStats: Codable {
    var totalSize: UInt64
    var fileListCount: Int
    var thumbnailCount: Int
    var transferCacheCount: Int
    var fileListSize: UInt64
    var thumbnailSize: UInt64
    var transferCacheSize: UInt64
    var lastUpdated: Date
    
    init() {
        totalSize = 0
        fileListCount = 0
        thumbnailCount = 0
        transferCacheCount = 0
        fileListSize = 0
        thumbnailSize = 0
        transferCacheSize = 0
        lastUpdated = Date()
    }
    
    var formattedTotalSize: String {
        return Utils.shared.formatFileSize(totalSize)
    }
}

// MARK: - 缓存清理记录
struct CacheCleanupRecord: Codable {
    let timestamp: Date
    let freedSize: UInt64
    let reason: CleanupReason
    let filesRemoved: Int
    
    init(freedSize: UInt64, reason: CleanupReason, filesRemoved: Int) {
        self.timestamp = Date()
        self.freedSize = freedSize
        self.reason = reason
        self.filesRemoved = filesRemoved
    }
    
    var formattedFreedSize: String {
        return Utils.shared.formatFileSize(freedSize)
    }
}

enum CleanupReason: String, Codable {
    case expired
    case sizeLimit
    case manual
    case onStart
    case thumbnails
}

// MARK: - 缓存配置
struct CacheConfig: Codable {
    var maxTotalSize: UInt64
    var maxThumbnailSize: UInt64
    var fileListTTL: TimeInterval
    var thumbnailTTL: TimeInterval
    var transferTTL: TimeInterval
    var cleanupInterval: TimeInterval
    var cleanupOnStart: Bool
    
    static let `default` = CacheConfig(
        maxTotalSize: 524288000, // 500MB
        maxThumbnailSize: 104857600, // 100MB
        fileListTTL: 300, // 5分钟
        thumbnailTTL: 86400, // 24小时
        transferTTL: 86400, // 24小时
        cleanupInterval: 3600, // 1小时
        cleanupOnStart: true
    )
}

// MARK: - 数据库模型
struct CacheDatabaseModel: Codable {
    var version: String
    var createdAt: Date
    var lastUpdated: Date
    var cacheStats: CacheStats
    var cleanupHistory: [CacheCleanupRecord]
    var config: CacheConfig
    
    init() {
        self.version = "1.0"
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.cacheStats = CacheStats()
        self.cleanupHistory = []
        self.config = .default
    }
}
