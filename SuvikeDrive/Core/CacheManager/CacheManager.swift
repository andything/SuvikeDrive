//
//  CacheManager.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 统一缓存总管
//

import AppKit
import Foundation

// MARK: - CacheError
enum CacheError: Error, LocalizedError {
    case sourceNotFound
    case destinationNotWritable
    case migrationInProgress
    case migrationCancelled
    case invalidPath
    
    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "源缓存目录不存在"
        case .destinationNotWritable:
            return "目标目录不可写"
        case .migrationInProgress:
            return "缓存迁移正在进行中"
        case .migrationCancelled:
            return "缓存迁移已取消"
        case .invalidPath:
            return "无效的缓存路径"
        }
    }
}

@preconcurrency
final class CacheManager {
    static let shared = CacheManager()
    
    // MARK: - 文件管理器
    let fileManager = FileManager.default
    
    // MARK: - 队列
    let cacheQueue = DispatchQueue(label: "com.suvikedrive.cache", attributes: .concurrent)
    let fileListCacheQueue = DispatchQueue(label: "com.suvikedrive.filelistcache", attributes: .concurrent)
    
    // MARK: - 缓存目录（可动态切换）
    private var _cacheRootDir: URL?
    var cacheRootDir: URL {
        guard let dir = _cacheRootDir else {
            let defaultPath = CacheManager.getDefaultCachePath()
            let url = URL(fileURLWithPath: defaultPath)
            _cacheRootDir = url
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return url
        }
        return dir
    }
    
    // MARK: - 文件列表内存缓存（internal 供 extension 访问）
    internal var fileListCache: [String: FileListCacheModel] = [:]
    internal var fileListAccessOrder: [String] = []
    
    // MARK: - 配置
    var maxMemoryEntries: Int = 100
    var maxMemorySize: UInt64 = 50 * 1024 * 1024
    var maxDiskSize: UInt64 = 500 * 1024 * 1024
    var fileListTTL: TimeInterval = 60
    var webDAVFileTTL: TimeInterval = 86400
    var isCacheEnabled: Bool = true
    var isAutoCleanupEnabled: Bool = true
    
    // MARK: - 迁移状态
    internal var isMigrating = false
    internal var migrationProgress: Progress?
    internal var migrationCancelled = false
    
    // MARK: - 定时器
    internal var cleanupTimer: Timer?
    internal var diskMonitorTimer: Timer?
    
    // MARK: - 缓存大小索引（增量维护）
    internal var serverCacheSizes: [String: UInt64] = [:]
    internal var totalCacheSize: UInt64 = 0
    internal let sizeIndexLock = NSLock()
    
    // MARK: - EventBus 订阅 Token
    internal var eventToken: SubscriptionToken?
    internal var configChangeToken: SubscriptionToken?
    
    // MARK: - 获取默认缓存路径
    private static func getDefaultCachePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SuvikeDrive").path
    }
    
    // MARK: - 重新加载缓存路径
    func reloadCachePath() {
        let customPath: String = ConfigurationManager.shared.get(key: "webdav.cache.path", defaultValue: "")
        let newPath: String
        
        if !customPath.isEmpty {
            newPath = customPath
            print("🔍 [Cache] 重新加载: 使用自定义缓存路径: \(newPath)")
        } else {
            newPath = CacheManager.getDefaultCachePath()
            print("🔍 [Cache] 重新加载: 使用默认缓存路径: \(newPath)")
        }
        
        let newURL = URL(fileURLWithPath: newPath)
        
        if _cacheRootDir?.path != newPath {
            print("✅ [Cache] 切换缓存路径: \(_cacheRootDir?.path ?? "nil") -> \(newPath)")
            _cacheRootDir = newURL
            
            try? fileManager.createDirectory(at: newURL, withIntermediateDirectories: true, attributes: nil)
            
            rebuildCacheIndex()
            
            EventBus.shared.publish(ConfigurationChanged(
                key: "cache.directory",
                oldValue: nil,
                newValue: newPath
            ))
            
            Logger.shared.info("✅ 缓存路径已切换: \(newPath)")
        }
    }
    
    // MARK: - Init
    private init() {
        let configManager = ConfigurationManager.shared
        let customPath: String = configManager.get(key: "webdav.cache.path", defaultValue: "")
        
        print("🔍 [Cache] 读取 webdav.cache.path = '\(customPath)'")
        
        let cacheDir: URL
        if !customPath.isEmpty {
            cacheDir = URL(fileURLWithPath: customPath)
            print("📋 [Cache] 使用自定义缓存路径: \(customPath)")
        } else {
            let defaultPath = CacheManager.getDefaultCachePath()
            cacheDir = URL(fileURLWithPath: defaultPath)
            print("📋 [Cache] 使用默认缓存路径: \(defaultPath)")
        }
        
        _cacheRootDir = cacheDir
        print("✅ [Cache] 最终缓存目录: \(cacheRootDir.path)")
        
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        
        setupEventBusListener()
        loadConfig()
        rebuildCacheIndex()
        setupAutoCleanup()
        startDiskSizeMonitor()
        
        Logger.shared.info("缓存管理器初始化完成，磁盘缓存上限: \(formatBytes(maxDiskSize))")
        
        setupConfigChangeListener()
        
        // 延迟发布缓存大小事件，EventBus 内部会处理订阅者未就绪的情况
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.publishCacheSizeEvents()
        }
    }
    
    // MARK: - 发布缓存大小事件（不重试，由 EventBus 内部处理）
    private func publishCacheSizeEvents() {
        Logger.shared.debug("发布缓存大小事件")
        
        EventBus.shared.publish(CacheSizeChanged(
            totalSize: self.totalCacheSize,
            formattedSize: self.formatBytes(self.totalCacheSize)
        ))
        
        let servers = ConfigurationManager.shared.getServers()
        for server in servers {
            let size = self.getCacheSize(for: server.id)
            EventBus.shared.publish(ServerCacheSizeChanged(
                serverID: server.id,
                serverName: server.name,
                formattedSize: self.formatBytes(size)
            ))
        }
    }
    
    deinit {
        eventToken?.unsubscribe()
        configChangeToken?.unsubscribe()
        cleanupTimer?.invalidate()
        diskMonitorTimer?.invalidate()
    }
    
    // MARK: - 监听配置变更
    private func setupConfigChangeListener() {
        configChangeToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .high
        ) { [weak self] event in
            guard let self = self else { return }
            if event.key == "webdav.cache.path" {
                print("🔍 [Cache] 检测到缓存路径配置变更")
                self.reloadCachePath()
            }
        }
    }
    
    // MARK: - 获取缓存目录
    func getCacheDirectory() -> URL {
        return cacheRootDir
    }
    
    // MARK: - 清除所有缓存
    func clearAllCaches() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.clearAllFileListCache()
            self.clearAllWebDAVCaches()
            
            // 重置索引
            self.sizeIndexLock.withLock {
                self.serverCacheSizes.removeAll()
                self.totalCacheSize = 0
            }
            
            EventBus.shared.publish(CacheCleared())
            Logger.shared.info("所有缓存已清除")
            
            DispatchQueue.main.async {
                let servers = ConfigurationManager.shared.getServers()
                for server in servers {
                    EventBus.shared.publish(ServerCacheSizeChanged(
                        serverID: server.id,
                        serverName: server.name,
                        formattedSize: "0 KB"
                    ))
                }
                EventBus.shared.publish(CacheSizeChanged(
                    totalSize: 0,
                    formattedSize: "0 KB"
                ))
            }
        }
    }
    
    // MARK: - 按服务器清除缓存
    func clearCache(for serverID: String, serverName: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.invalidateFileList(prefix: serverID)
            self.clearWebDAVCache(serverID: serverID, serverName: serverName)
            
            // 从索引中移除（尝试两种 key）
            self.sizeIndexLock.withLock {
                self.serverCacheSizes.removeValue(forKey: serverID)
                self.serverCacheSizes.removeValue(forKey: serverName)
                self.totalCacheSize = self.serverCacheSizes.values.reduce(0, +)
            }
            
            let serverDir = self.getServerMirrorDirectory(serverID: serverID, serverName: serverName)
            if self.fileManager.fileExists(atPath: serverDir.path) {
                try? self.fileManager.removeItem(at: serverDir)
                Logger.shared.info("🗑️ 已删除服务器镜像目录: \(serverDir.path)")
            }
            
            EventBus.shared.publish(CacheCleared(serverID: serverID))
            Logger.shared.info("已清除服务器缓存: \(serverID)")
            
            DispatchQueue.main.async {
                EventBus.shared.publish(ServerCacheSizeChanged(
                    serverID: serverID,
                    serverName: serverName,
                    formattedSize: "0 KB"
                ))
                EventBus.shared.publish(CacheSizeChanged(
                    totalSize: self.totalCacheSize,
                    formattedSize: self.formatBytes(self.totalCacheSize)
                ))
            }
        }
    }
    
    // MARK: - 获取服务器缓存大小
    func getCacheSize(for serverID: String) -> UInt64 {
        // ✅ 先尝试用 serverID 查找
        if let size = sizeIndexLock.withLock({ serverCacheSizes[serverID] }) {
            return size
        }
        
        // ✅ 如果 serverID 查找失败，尝试通过服务器名称查找
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        let size = sizeIndexLock.withLock { serverCacheSizes[serverName] ?? 0 }
        
        if size == 0 {
            print("⚠️ [Cache] getCacheSize: 未找到缓存 for serverID=\(serverID), serverName=\(serverName)")
        }
        
        return size
    }
    
    // MARK: - 获取总缓存大小
    func getTotalCacheSize() -> UInt64 {
        return sizeIndexLock.withLock { totalCacheSize }
    }
    
    // MARK: - 获取格式化后的总缓存大小
    func getCacheSizeFormatted() -> String {
        return formatBytes(getTotalCacheSize())
    }
    
    // MARK: - 获取服务器缓存大小（带格式化）
    func getCacheSizeFormatted(for serverID: String) -> String {
        return formatBytes(getCacheSize(for: serverID))
    }
    
    // MARK: - 重建缓存索引
    func rebuildCacheIndex() {
        sizeIndexLock.withLock {
            serverCacheSizes.removeAll()
            totalCacheSize = 0
        }
        
        guard let serverDirs = try? fileManager.contentsOfDirectory(at: cacheRootDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        // ✅ 获取所有服务器配置，建立 serverName → serverID 映射
        let servers = ConfigurationManager.shared.getServers()
        let nameToID: [String: String] = Dictionary(uniqueKeysWithValues: servers.map { ($0.name, $0.id) })
        
        for serverDir in serverDirs {
            // 跳过元数据目录
            if serverDir.lastPathComponent == ".metadata" { continue }
            
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: serverDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            let size = calculateDirectorySize(serverDir)
            let serverName = serverDir.lastPathComponent
            
            // ✅ 通过服务器名称查找对应的 serverID
            let serverID = nameToID[serverName] ?? serverName
            
            sizeIndexLock.withLock {
                // ✅ 同时用 serverID 和 serverName 作为 key，兼容两种查找方式
                serverCacheSizes[serverID] = size
                serverCacheSizes[serverName] = size
                totalCacheSize += size
            }
            
            print("📋 [Cache] rebuildCacheIndex: \(serverName) (ID: \(serverID)) = \(formatBytes(size))")
        }
        
        print("📋 [Cache] rebuildCacheIndex 完成，总缓存: \(formatBytes(totalCacheSize))")
    }
    
    // MARK: - 增量更新缓存大小
    func updateCacheSizeForServer(serverID: String, delta: Int64) {
        sizeIndexLock.withLock {
            // 尝试更新 serverID 对应的缓存
            let currentID = serverCacheSizes[serverID] ?? 0
            let newSizeID = max(0, Int64(currentID) + delta)
            serverCacheSizes[serverID] = UInt64(newSizeID)
            
            // 也尝试更新服务器名称对应的缓存
            let servers = ConfigurationManager.shared.getServers()
            let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
            let currentName = serverCacheSizes[serverName] ?? 0
            let newSizeName = max(0, Int64(currentName) + delta)
            serverCacheSizes[serverName] = UInt64(newSizeName)
            
            totalCacheSize = UInt64(max(0, Int64(totalCacheSize) + delta))
        }
    }
    
    // MARK: - 计算目录大小
    func calculateDirectorySize(_ url: URL) -> UInt64 {
        var total: UInt64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let attrs = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                total += UInt64(attrs.fileSize ?? 0)
            } catch {
                continue
            }
        }
        
        return total
    }
    
    // MARK: - 格式化工具
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - 兼容旧 API
extension CacheManager {
    
    /// 刷新配置（兼容旧调用）
    func refreshConfig() {
        loadConfig()
        reloadCachePath()
    }
    
    /// 获取内存缓存大小（兼容旧调用）
    func getMemoryCacheSize() -> Int {
        return fileListCacheQueue.sync { fileListCache.count }
    }
    
    /// 更新缓存大小（兼容旧调用）- 使用 rebuildCacheIndex 替代
    func updateCacheSize() {
        rebuildCacheIndex()
    }
    
    /// 按服务器清除缓存（兼容旧调用，只需 serverID）
    func clearCache(for serverID: String) {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        clearCache(for: serverID, serverName: serverName)
    }
}
