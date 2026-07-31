//
//  AppCacheManager.swift
//  SuvikeDrive
//
//  功能: 缓存管理器初始化
//

import Foundation

struct AppCacheManager {
    
    /// 初始化缓存管理器
    static func setup() {
        print("📋 [Cache] 开始初始化缓存管理器...")
        let manager = CacheManager.shared
        print("✅ [Cache] 缓存管理器已初始化")
        print("📋 [Cache] 缓存目录: \(manager.getCacheDirectory().path)")
        
        // 打印缓存状态
        print("📋 [Cache] 缓存启用状态: \(manager.isCacheEnabled)")
        print("📋 [Cache] 内存缓存条目: \(manager.maxMemoryEntries)")
        print("📋 [Cache] 磁盘缓存上限: \(manager.formatBytes(manager.maxDiskSize))")
    }
}
