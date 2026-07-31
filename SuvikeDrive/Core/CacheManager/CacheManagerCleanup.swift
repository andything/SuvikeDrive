//
//  CacheManagerCleanup.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 自动清理、过期淘汰
//

import Foundation

extension CacheManager {
    
    // MARK: - 清理过期缓存
    func cleanExpiredCaches() {
        guard isCacheEnabled else { return }
        
        // 清理过期的 WebDAV 镜像文件
        evictExpiredWebDAVFiles()
        
        // 清理过期的文件列表内存缓存
        fileListCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
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
        
        // 清理过期快照
        cleanExpiredSnapshots()
        
        rebuildCacheIndex()
    }
    
    // MARK: - 全局磁盘缓存淘汰
    func evictDiskCache() {
        // 先清理过期文件
        evictExpiredWebDAVFiles()
        
        let currentSize = getTotalCacheSize()
        guard currentSize >= maxDiskSize else { return }
        
        let rootDir = getCacheDirectory()
        guard let serverDirs = try? fileManager.contentsOfDirectory(at: rootDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        // 收集所有文件及其修改时间
        var fileInfos: [(url: URL, size: UInt64, date: Date, serverID: String)] = []
        var totalSize: UInt64 = 0
        
        for serverDir in serverDirs {
            if serverDir.lastPathComponent == ".metadata" { continue }
            
            let serverID = serverDir.lastPathComponent
            guard let enumerator = fileManager.enumerator(at: serverDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                      let size = attrs[.size] as? UInt64,
                      let modDate = attrs[.modificationDate] as? Date else {
                    continue
                }
                fileInfos.append((fileURL, size, modDate, serverID))
                totalSize += size
            }
        }
        
        // 按修改时间排序，删除最旧的文件
        if totalSize > maxDiskSize {
            fileInfos.sort { $0.date < $1.date }
            let targetSize = maxDiskSize * 9 / 10
            var currentSize = totalSize
            var sizeDelta: [String: Int64] = [:]
            
            for info in fileInfos {
                if currentSize <= targetSize { break }
                try? fileManager.removeItem(at: info.url)
                currentSize -= info.size
                sizeDelta[info.serverID] = (sizeDelta[info.serverID] ?? 0) - Int64(info.size)
            }
            
            // 更新索引
            for (serverID, delta) in sizeDelta {
                updateCacheSizeForServer(serverID: serverID, delta: delta)
            }
            
            Logger.shared.info("磁盘缓存清理完成，当前大小: \(formatBytes(currentSize))")
        }
    }
    
    // MARK: - 清理过期 WebDAV 本地文件
    func evictExpiredWebDAVFiles() {
        guard webDAVFileTTL > 0 else { return }
        let expireTime = Date().addingTimeInterval(-webDAVFileTTL)
        
        let rootDir = getCacheDirectory()
        guard let serverDirs = try? fileManager.contentsOfDirectory(at: rootDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        var removedCount = 0
        var freedSize: UInt64 = 0
        var sizeDelta: [String: Int64] = [:]
        
        for serverDir in serverDirs {
            if serverDir.lastPathComponent == ".metadata" { continue }
            
            let serverID = serverDir.lastPathComponent
            guard let enumerator = fileManager.enumerator(at: serverDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = attrs.contentModificationDate else {
                    continue
                }
                if mtime < expireTime {
                    let size = UInt64(attrs.fileSize ?? 0)
                    try? fileManager.removeItem(at: fileURL)
                    removedCount += 1
                    freedSize += size
                    sizeDelta[serverID] = (sizeDelta[serverID] ?? 0) - Int64(size)
                }
            }
        }
        
        // 更新索引
        for (serverID, delta) in sizeDelta {
            updateCacheSizeForServer(serverID: serverID, delta: delta)
        }
        
        if removedCount > 0 {
            Logger.shared.info("清理了 \(removedCount) 个过期 WebDAV 文件，释放 \(formatBytes(freedSize))")
        }
    }
    
    // MARK: - 自动清理定时器
    func setupAutoCleanup() {
        guard isAutoCleanupEnabled else { return }
        
        cleanupTimer?.invalidate()
        
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanExpiredCaches()
        }
        
        Logger.shared.debug("自动清理已启动")
    }
    
    func stopAutoCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        Logger.shared.debug("自动清理已停止")
    }
    
    // MARK: - 磁盘大小监控
    func startDiskSizeMonitor() {
        diskMonitorTimer?.invalidate()
        diskMonitorTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkDiskSize()
        }
    }
    
    func checkDiskSize() {
        guard isCacheEnabled else { return }
        
        let currentSize = getTotalCacheSize()
        let threshold = UInt64(Double(maxDiskSize) * 0.9)
        if currentSize > threshold {
            Logger.shared.warning("缓存大小 \(formatBytes(currentSize)) 超过阈值 \(formatBytes(threshold))，开始清理")
            evictDiskCache()
        }
    }
    
    // MARK: - 清理（供 TaskScheduler 调用）
    func cleanup() {
        cleanExpiredCaches()
    }
}
