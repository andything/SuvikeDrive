//
//  CacheManager.swift
//  SuvikeDrive
//
//  功能: 缓存管理器
//  支持: 内存缓存上限、磁盘缓存上限、LRU淘汰、自动清理、异步迁移
//

import AppKit
import Foundation

// MARK: - 使用 Models 中的缓存类型
typealias TransferCache = TransferCacheModel
typealias FileListCacheEntry = FileListCacheModel

// MARK: - CacheError
enum CacheError: Error, LocalizedError {
    case sourceNotFound
    case destinationNotWritable
    case migrationInProgress
    case migrationCancelled
    
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
        }
    }
}

@preconcurrency
class CacheManager {
    static let shared = CacheManager()
    
    private let fileManager = FileManager.default
    private let cacheQueue = DispatchQueue(label: "com.suvikedrive.cache", attributes: .concurrent)
    
    // ✅ 使用 TransferCacheModel
    private var transferCache: [String: TransferCacheModel] = [:]
    private let transferCacheDir: URL
    
    // ✅ 使用 FileListCacheModel
    private var fileListCache: [String: FileListCacheModel] = [:]
    private let fileListCacheQueue = DispatchQueue(label: "com.suvikedrive.filelistcache", attributes: .concurrent)
    private var fileListAccessOrder: [String] = []
    
    // MARK: - 配置
    private var maxMemoryEntries: Int = 100
    private var maxMemorySize: UInt64 = 50 * 1024 * 1024
    private var maxDiskSize: UInt64 = 500 * 1024 * 1024
    private var fileListTTL: TimeInterval = 60
    private var transferTTL: Int = 7
    private var isCacheEnabled: Bool = true
    private var isAutoCleanupEnabled: Bool = true
    
    private var isMigrating = false
    private var migrationProgress: Progress?
    private var migrationCancelled = false
    private var cleanupTimer: Timer?
    private var diskMonitorTimer: Timer?
    
    // MARK: - 统计
    private(set) var totalCacheSize: UInt64 = 0
    private let statsLock = NSLock()
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("com.suvikedrive.drive/TransferCache")
        self.transferCacheDir = cacheDir
        
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: NSNotification.Name("ConfigurationChanged"),
            object: nil
        )
        
        loadConfig()
        loadAllTransferCaches()
        updateCacheSize()
        setupAutoCleanup()
        startDiskSizeMonitor()
        
        Logger.shared.info("缓存管理器初始化完成，磁盘缓存上限: \(formatBytes(maxDiskSize))")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupTimer?.invalidate()
        diskMonitorTimer?.invalidate()
    }
    
    // MARK: - 配置加载
    private func loadConfig() {
        maxMemoryEntries = ConfigurationManager.shared.get(key: "cache.maxMemoryEntries", defaultValue: 100)
        maxMemorySize = UInt64(ConfigurationManager.shared.get(key: "cache.maxMemorySize", defaultValue: 50 * 1024 * 1024))
        maxDiskSize = UInt64(ConfigurationManager.shared.get(key: "cache.maxDiskSize", defaultValue: 500 * 1024 * 1024))
        fileListTTL = ConfigurationManager.shared.get(key: "cache.fileListTTL", defaultValue: 60)
        transferTTL = ConfigurationManager.shared.get(key: "cache.transferTTL", defaultValue: 7)
        isCacheEnabled = ConfigurationManager.shared.get(key: "cache.enabled", defaultValue: true)
        isAutoCleanupEnabled = ConfigurationManager.shared.get(key: "cache.autoCleanup", defaultValue: true)
        
        if isAutoCleanupEnabled {
            setupAutoCleanup()
        } else {
            stopAutoCleanup()
        }
    }
    
    @objc private func configurationChanged() {
        loadConfig()
        Logger.shared.debug("缓存配置已更新")
    }
    
    // MARK: - 缓存大小统计
    private func updateCacheSize() {
        statsLock.lock()
        totalCacheSize = calculateCacheSize()
        statsLock.unlock()
    }
    
    private func calculateCacheSize() -> UInt64 {
        var total: UInt64 = 0
        guard let files = try? fileManager.contentsOfDirectory(at: transferCacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        for file in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }
    
    // MARK: - 编码辅助方法
    @preconcurrency
    private func encodeTransferCache(_ cache: TransferCacheModel) -> Data? {
        return try? JSONEncoder().encode(cache)
    }
    
    // MARK: - 传输断点缓存
    func getTransferCache(transferID: String) -> TransferCacheModel? {
        guard isCacheEnabled else { return nil }
        
        var result: TransferCacheModel?
        cacheQueue.sync {
            if let cache = transferCache[transferID] {
                result = cache
            } else {
                let cacheFile = transferCacheDir.appendingPathComponent("\(transferID).cache")
                if let data = try? Data(contentsOf: cacheFile),
                   let cache = try? JSONDecoder().decode(TransferCacheModel.self, from: data) {
                    result = cache
                    transferCache[transferID] = cache
                }
            }
        }
        return result
    }
    
    func setTransferCache(_ cache: TransferCacheModel) {
        guard isCacheEnabled else { return }
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            if self.totalCacheSize >= self.maxDiskSize {
                self.evictDiskCache(neededSpace: 1024 * 1024)
            }
            
            self.transferCache[cache.transferID] = cache
            
            let cacheFile = self.transferCacheDir.appendingPathComponent("\(cache.transferID).cache")
            if let data = self.encodeTransferCache(cache) {
                try? data.write(to: cacheFile)
                self.updateCacheSize()
            }
        }
    }
    
    func updateTransferProgress(transferID: String, bytesTransferred: UInt64) {
        guard isCacheEnabled else { return }
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            if var cache = self.transferCache[transferID] {
                cache.transferredBytes = bytesTransferred
                cache.lastUpdated = Date()
                self.transferCache[transferID] = cache
                
                let cacheFile = self.transferCacheDir.appendingPathComponent("\(transferID).cache")
                if let data = self.encodeTransferCache(cache) {
                    try? data.write(to: cacheFile)
                }
            }
        }
    }
    
    func removeTransferCache(transferID: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.transferCache.removeValue(forKey: transferID)
            let cacheFile = self.transferCacheDir.appendingPathComponent("\(transferID).cache")
            try? FileManager.default.removeItem(at: cacheFile)
            self.updateCacheSize()
        }
    }
    
    // MARK: - 文件列表缓存（带 LRU）
    func getFileList(key: String) -> [FileInfo]? {
        guard isCacheEnabled else { return nil }
        
        var result: [FileInfo]?
        fileListCacheQueue.sync {
            if let cached = fileListCache[key],
               Date().timeIntervalSince(cached.cachedAt) < fileListTTL {
                result = cached.files.map { fileCacheItem in
                    FileInfo(
                        name: fileCacheItem.name,
                        path: fileCacheItem.path,
                        isDirectory: fileCacheItem.isDirectory,
                        size: fileCacheItem.size,
                        modificationDate: fileCacheItem.modificationDate,
                        permissions: fileCacheItem.permissions
                    )
                }
                if let index = fileListAccessOrder.firstIndex(of: key) {
                    fileListAccessOrder.remove(at: index)
                }
                fileListAccessOrder.append(key)
            }
        }
        return result
    }
    
    func setFileList(key: String, files: [FileInfo]) {
        guard isCacheEnabled else { return }
        
        fileListCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            if self.fileListCache.count >= self.maxMemoryEntries {
                self.evictMemoryCache()
            }
            
            let fileCacheItems = files.map { file in
                FileCacheItem(
                    name: file.name,
                    path: file.path,
                    isDirectory: file.isDirectory,
                    size: file.size,
                    modificationDate: file.modificationDate,
                    permissions: file.permissions ?? "rw-"
                )
            }
            
            self.fileListCache[key] = FileListCacheModel(
                serverID: key.components(separatedBy: "_").first ?? "",
                path: key,
                files: fileCacheItems,
                ttl: self.fileListTTL
            )
            
            if let index = self.fileListAccessOrder.firstIndex(of: key) {
                self.fileListAccessOrder.remove(at: index)
            }
            self.fileListAccessOrder.append(key)
        }
    }
    
    func invalidateFileList(key: String) {
        fileListCacheQueue.async(flags: .barrier) {
            self.fileListCache.removeValue(forKey: key)
            self.fileListAccessOrder.removeAll { $0 == key }
        }
    }
    
    func invalidateFileList(prefix: String) {
        fileListCacheQueue.async(flags: .barrier) {
            let keysToRemove = self.fileListCache.keys.filter { $0.hasPrefix(prefix) }
            for key in keysToRemove {
                self.fileListCache.removeValue(forKey: key)
                self.fileListAccessOrder.removeAll { $0 == key }
            }
        }
    }
    
    func clearAllFileListCache() {
        fileListCacheQueue.async(flags: .barrier) {
            self.fileListCache.removeAll()
            self.fileListAccessOrder.removeAll()
        }
    }
    
    // MARK: - LRU 淘汰
    private func evictMemoryCache() {
        guard fileListAccessOrder.count > maxMemoryEntries / 2 else { return }
        
        let removeCount = max(1, fileListAccessOrder.count / 5)
        let keysToRemove = fileListAccessOrder.prefix(removeCount)
        for key in keysToRemove {
            fileListCache.removeValue(forKey: key)
        }
        fileListAccessOrder.removeFirst(removeCount)
        
        Logger.shared.debug("内存缓存 LRU 淘汰: 移除 \(removeCount) 个条目")
    }
    
    private func evictDiskCache(neededSpace: UInt64 = 0) {
        let expirationDate = Date().addingTimeInterval(-Double(transferTTL) * 24 * 60 * 60)
        let expiredIDs = transferCache.filter { $0.value.lastUpdated < expirationDate }.map { $0.key }
        
        for id in expiredIDs {
            removeTransferCache(transferID: id)
        }
        
        if totalCacheSize >= maxDiskSize {
            let sorted = transferCache.sorted { $0.value.lastUpdated < $1.value.lastUpdated }
            let removeCount = max(1, sorted.count / 5)
            for i in 0..<min(removeCount, sorted.count) {
                removeTransferCache(transferID: sorted[i].key)
            }
        }
        
        updateCacheSize()
    }
    
    // MARK: - 加载所有缓存
    private func loadAllTransferCaches() {
        guard let files = try? fileManager.contentsOfDirectory(at: transferCacheDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "cache" {
            guard let data = try? Data(contentsOf: file),
                  let cache = try? JSONDecoder().decode(TransferCacheModel.self, from: data) else {
                continue
            }
            transferCache[cache.transferID] = cache
        }
        
        Logger.shared.debug("加载传输缓存: \(transferCache.count) 个")
    }
    
    // MARK: - 清理过期缓存
    func cleanExpiredCaches(olderThan days: Int? = nil) {
        guard isCacheEnabled else { return }
        
        let ttl = days ?? transferTTL
        let expirationDate = Date().addingTimeInterval(-Double(ttl) * 24 * 60 * 60)
        
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let expiredIDs = self.transferCache.filter { $0.value.lastUpdated < expirationDate }.map { $0.key }
            
            for id in expiredIDs {
                self.removeTransferCache(transferID: id)
            }
            
            if !expiredIDs.isEmpty {
                Logger.shared.info("清理了 \(expiredIDs.count) 个过期传输缓存")
            }
            
            self.fileListCacheQueue.async(flags: .barrier) {
                let keysToRemove = self.fileListCache.filter {
                    Date().timeIntervalSince($0.value.cachedAt) > self.fileListTTL * 2
                }.map { $0.key }
                for key in keysToRemove {
                    self.fileListCache.removeValue(forKey: key)
                    self.fileListAccessOrder.removeAll { $0 == key }
                }
                if !keysToRemove.isEmpty {
                    Logger.shared.debug("清理了 \(keysToRemove.count) 个过期文件列表缓存")
                }
            }
            
            self.updateCacheSize()
        }
    }
    
    // MARK: - 缓存迁移（异步）
    func migrateCache(from sourceURL: URL, to destURL: URL, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !isMigrating else {
            completion(.failure(CacheError.migrationInProgress))
            return
        }
        
        isMigrating = true
        migrationCancelled = false
        migrationProgress = Progress(totalUnitCount: 100)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard self.fileManager.fileExists(atPath: sourceURL.path) else {
                    throw CacheError.sourceNotFound
                }
                
                let destDir = destURL.deletingLastPathComponent()
                var isDir: ObjCBool = false
                if !self.fileManager.fileExists(atPath: destDir.path, isDirectory: &isDir) || !isDir.boolValue {
                    try self.fileManager.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                if !self.fileManager.isWritableFile(atPath: destDir.path) {
                    throw CacheError.destinationNotWritable
                }
                
                let files = try self.fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: [.fileSizeKey])
                let totalFiles = files.count
                var processedFiles = 0
                
                try self.fileManager.createDirectory(at: destURL, withIntermediateDirectories: true, attributes: nil)
                
                for file in files {
                    if self.migrationCancelled {
                        throw CacheError.migrationCancelled
                    }
                    
                    let destFile = destURL.appendingPathComponent(file.lastPathComponent)
                    
                    if self.fileManager.fileExists(atPath: destFile.path) {
                        try self.fileManager.removeItem(at: destFile)
                    }
                    
                    try self.fileManager.moveItem(at: file, to: destFile)
                    
                    processedFiles += 1
                    let percent = Double(processedFiles) / Double(totalFiles) * 100
                    self.migrationProgress?.completedUnitCount = Int64(percent)
                    
                    DispatchQueue.main.async {
                        progress(percent / 100)
                    }
                }
                
                ConfigurationManager.shared.set(key: "cache.customPath", value: destURL.path)
                self.updateCacheSize()
                
                DispatchQueue.main.async {
                    self.isMigrating = false
                    completion(.success(destURL))
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isMigrating = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    func cancelMigration() {
        migrationCancelled = true
    }
    
    func getMigrationProgress() -> Progress? {
        return migrationProgress
    }
    
    // MARK: - 缓存大小
    func getCacheSizeFormatted() -> String {
        let size = getCacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    func getCacheSize() -> UInt64 {
        statsLock.lock()
        defer { statsLock.unlock() }
        return totalCacheSize
    }
    
    func getMemoryCacheSize() -> Int {
        return fileListCache.count
    }
    
    func getDiskCacheSize() -> UInt64 {
        return getCacheSize()
    }
    
    // MARK: - 获取缓存目录
    func getCacheDirectory() -> URL {
        return transferCacheDir
    }
    
    // MARK: - 清除所有缓存
    func clearAllCaches() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.transferCache.removeAll()
            self.clearAllFileListCache()
            
            guard let files = try? self.fileManager.contentsOfDirectory(at: self.transferCacheDir, includingPropertiesForKeys: nil) else {
                return
            }
            
            for file in files {
                try? self.fileManager.removeItem(at: file)
            }
            
            self.updateCacheSize()
            Logger.shared.info("所有缓存已清除")
        }
    }
    
    // MARK: - 自动清理定时器
    private func setupAutoCleanup() {
        guard isAutoCleanupEnabled else { return }
        
        cleanupTimer?.invalidate()
        
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanExpiredCaches()
        }
        
        Logger.shared.debug("自动清理已启动")
    }
    
    private func stopAutoCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        Logger.shared.debug("自动清理已停止")
    }
    
    // MARK: - 磁盘大小监控
    private func startDiskSizeMonitor() {
        diskMonitorTimer?.invalidate()
        diskMonitorTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkDiskSize()
        }
    }
    
    private func checkDiskSize() {
        guard isCacheEnabled else { return }
        
        updateCacheSize()
        let threshold = UInt64(Double(maxDiskSize) * 0.9)
        if totalCacheSize > threshold {
            Logger.shared.warning("缓存大小 \(formatBytes(totalCacheSize)) 超过阈值 \(formatBytes(threshold))，开始清理")
            evictDiskCache()
        }
    }
    
    // MARK: - 刷新配置（外部调用）
    func refreshConfig() {
        loadConfig()
    }
    
    // MARK: - 清理（供 TaskScheduler 调用）
    func cleanup() {
        cleanExpiredCaches(olderThan: transferTTL)
    }
    
    // MARK: - 格式化工具
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
