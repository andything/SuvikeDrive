//
//  CacheManagerConfig.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 配置加载
//

import Foundation

extension CacheManager {
    
    // MARK: - EventBus 事件监听
    func setupEventBusListener() {
        eventToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .low
        ) { [weak self] event in
            guard let self = self else { return }
            if event.key == "cache" || event.key.hasPrefix("cache.") || event.key == "webdav.cache.path" {
                self.loadConfig()
                Logger.shared.debug("缓存配置已更新")
            }
        }
    }
    
    // MARK: - 配置加载
    func loadConfig() {
        maxMemoryEntries = ConfigurationManager.shared.get(key: "cache.maxMemoryEntries", defaultValue: 100)
        maxMemorySize = UInt64(ConfigurationManager.shared.get(key: "cache.maxMemorySize", defaultValue: 50 * 1024 * 1024))
        maxDiskSize = UInt64(ConfigurationManager.shared.get(key: "cache.maxDiskSize", defaultValue: 500 * 1024 * 1024))
        fileListTTL = ConfigurationManager.shared.get(key: "cache.fileListTTL", defaultValue: 60)
        webDAVFileTTL = ConfigurationManager.shared.get(key: "cache.webdavFileTTL", defaultValue: 86400)
        isCacheEnabled = ConfigurationManager.shared.get(key: "cache.enabled", defaultValue: true)
        isAutoCleanupEnabled = ConfigurationManager.shared.get(key: "cache.autoCleanup", defaultValue: true)
        
        print("📋 [Cache] 配置加载完成:")
        print("  - isCacheEnabled: \(isCacheEnabled)")
        print("  - isAutoCleanupEnabled: \(isAutoCleanupEnabled)")
        print("  - maxDiskSize: \(maxDiskSize) bytes (\(formatBytes(maxDiskSize)))")
        print("  - maxMemoryEntries: \(maxMemoryEntries)")
        print("  - fileListTTL: \(fileListTTL) 秒")
        print("  - webDAVFileTTL: \(webDAVFileTTL) 秒")
        print("  - 缓存目录: \(cacheRootDir.path)")
        
        if !fileManager.fileExists(atPath: cacheRootDir.path) {
            do {
                try fileManager.createDirectory(at: cacheRootDir, withIntermediateDirectories: true)
                print("✅ [Cache] 缓存目录已创建: \(cacheRootDir.path)")
            } catch {
                print("❌ [Cache] 创建缓存目录失败: \(error)")
            }
        }
        
        if isAutoCleanupEnabled {
            setupAutoCleanup()
        } else {
            stopAutoCleanup()
        }
    }
}
