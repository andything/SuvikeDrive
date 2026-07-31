//
//  CacheModel.swift
//  SuvikeDrive
//
//  功能: 所有缓存数据模型
//  注意: 只包含数据结构定义，不包含方法实现
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
        let expirationTime: TimeInterval = 86400
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
        maxTotalSize: 524288000,
        maxThumbnailSize: 104857600,
        fileListTTL: 300,
        thumbnailTTL: 86400,
        transferTTL: 86400,
        cleanupInterval: 3600,
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

// ============================================================
// MARK: - 【新增】目录快照模型
// ============================================================

/// 目录快照
/// ✅ 添加 @unchecked Sendable 解决 Swift 6 并发问题
struct DirectorySnapshot: Codable, @unchecked Sendable {
    let id: String
    let serverID: String
    let path: String
    let etag: String?
    let createdAt: Date
    var updatedAt: Date
    var items: [SnapshotItem]
    var totalFiles: Int
    var totalSize: UInt64
    var cachedFiles: Int
    var cachedSize: UInt64
    let version: String
    
    init(serverID: String, path: String, etag: String? = nil, items: [SnapshotItem] = []) {
        self.id = UUID().uuidString
        self.serverID = serverID
        self.path = path
        self.etag = etag
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = items
        self.totalFiles = items.filter { $0.type == .file }.count
        self.totalSize = items.compactMap { $0.size }.reduce(0, +)
        self.cachedFiles = items.filter { $0.isCached }.count
        self.cachedSize = items.compactMap { $0.cachedSize }.reduce(0, +)
        self.version = "1.0"
    }
}

/// 快照节点
struct SnapshotItem: Codable {
    let name: String
    let path: String
    let type: SnapshotItemType
    let size: UInt64?
    let etag: String?
    let lastModified: Date?
    let contentType: String?
    var isCached: Bool
    var cachedAt: Date?
    var cachedSize: UInt64?
    
    init(name: String, path: String, type: SnapshotItemType, size: UInt64? = nil,
         etag: String? = nil, lastModified: Date? = nil, contentType: String? = nil,
         isCached: Bool = false, cachedAt: Date? = nil, cachedSize: UInt64? = nil) {
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.etag = etag
        self.lastModified = lastModified
        self.contentType = contentType
        self.isCached = isCached
        self.cachedAt = cachedAt
        self.cachedSize = cachedSize
    }
}

enum SnapshotItemType: String, Codable {
    case file
    case directory
    case symlink
}

// MARK: - 【新增】ETag缓存索引

/// ETag缓存条目
/// ✅ 添加 @unchecked Sendable 解决 Swift 6 并发问题
struct ETagCacheEntry: Codable, @unchecked Sendable {
    let serverID: String
    let path: String
    let etag: String
    let size: UInt64
    let lastModified: Date?
    let updatedAt: Date
    
    init(serverID: String, path: String, etag: String, size: UInt64, lastModified: Date? = nil) {
        self.serverID = serverID
        self.path = path
        self.etag = etag
        self.size = size
        self.lastModified = lastModified
        self.updatedAt = Date()
    }
}

// MARK: - 【新增】快照变化

struct SnapshotChanges {
    let added: [SnapshotItem]
    let modified: [SnapshotItem]
    let deleted: [String]
    let unchanged: [String]
    
    var hasChanges: Bool {
        return !added.isEmpty || !modified.isEmpty || !deleted.isEmpty
    }
    
    var summary: String {
        return "新增: \(added.count), 修改: \(modified.count), 删除: \(deleted.count)"
    }
}

// MARK: - 【新增】快照统计

struct SnapshotStats: Codable {
    let serverID: String
    let path: String
    let totalItems: Int
    let totalFiles: Int
    let totalDirectories: Int
    let totalSize: UInt64
    let cachedFiles: Int
    let cachedSize: UInt64
    let cacheHitRate: Double
    let lastSyncTime: Date?
    let syncDuration: TimeInterval?
    
    init(snapshot: DirectorySnapshot) {
        self.serverID = snapshot.serverID
        self.path = snapshot.path
        self.totalItems = snapshot.items.count
        self.totalFiles = snapshot.totalFiles
        self.totalDirectories = snapshot.items.filter { $0.type == .directory }.count
        self.totalSize = snapshot.totalSize
        self.cachedFiles = snapshot.cachedFiles
        self.cachedSize = snapshot.cachedSize
        self.cacheHitRate = totalFiles > 0 ? Double(cachedFiles) / Double(totalFiles) : 0
        self.lastSyncTime = snapshot.updatedAt
        self.syncDuration = nil
    }
}

// MARK: - RemoteFileItem（从 WebDAV 获取的远程文件信息）

struct RemoteFileItem {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64?
    let etag: String?
    let modified: Date?
    let contentType: String?
    
    init(name: String, path: String, isDirectory: Bool, size: UInt64? = nil,
         etag: String? = nil, modified: Date? = nil, contentType: String? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.etag = etag
        self.modified = modified
        self.contentType = contentType
    }
}
