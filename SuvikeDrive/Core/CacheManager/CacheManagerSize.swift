//
//  CacheManagerSize.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 缓存大小查询扩展
//

import Foundation

extension CacheManager {
    
    // MARK: - 获取所有服务器的缓存大小（字典）
    func getAllServerCacheSizes() -> [String: UInt64] {
        return sizeIndexLock.withLock { serverCacheSizes }
    }
    
    // MARK: - 获取所有服务器的缓存大小（带服务器名称）
    func getAllServerCacheSizesWithNames() -> [(serverID: String, serverName: String, size: UInt64)] {
        let sizes = getAllServerCacheSizes()
        let servers = ConfigurationManager.shared.getServers()
        
        return sizes.map { serverID, size in
            let name = servers.first(where: { $0.id == serverID })?.name ?? serverID
            return (serverID: serverID, serverName: name, size: size)
        }.sorted { $0.size > $1.size }
    }
    
    // MARK: - 获取磁盘可用空间
    func getAvailableDiskSpace() -> UInt64? {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: cacheRootDir.path)
            return attributes[.systemFreeSize] as? UInt64
        } catch {
            Logger.shared.warning("获取磁盘可用空间失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 获取磁盘总空间
    func getTotalDiskSpace() -> UInt64? {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: cacheRootDir.path)
            return attributes[.systemSize] as? UInt64
        } catch {
            Logger.shared.warning("获取磁盘总空间失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 获取缓存使用率
    func getCacheUsageRatio() -> Double {
        let total = getTotalCacheSize()
        guard maxDiskSize > 0 else { return 0 }
        return Double(total) / Double(maxDiskSize)
    }
    
    // MARK: - 获取缓存使用率百分比字符串
    func getCacheUsagePercentage() -> String {
        let ratio = getCacheUsageRatio()
        return String(format: "%.1f%%", ratio * 100)
    }
}
