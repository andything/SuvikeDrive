//
//  CacheManagerFileList.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 文件列表缓存（仅内存缓存）
//

import Foundation

extension CacheManager {
    
    // MARK: - 获取文件列表缓存（同步版本）
    func getFileList(key: String) -> [FileInfo]? {
        guard isCacheEnabled else {
            print("❌ [Cache] getFileList: 缓存已禁用")
            return nil
        }
        
        print("📋 [Cache] getFileList: 尝试获取内存缓存 key=\(key)")
        
        var result: [FileInfo]?
        fileListCacheQueue.sync {
            if let cached = fileListCache[key],
               Date().timeIntervalSince(cached.cachedAt) < fileListTTL {
                print("✅ [Cache] getFileList: 内存缓存命中 key=\(key)")
                result = cached.files.map { fileCacheItem in
                    FileInfo(
                        name: fileCacheItem.name,
                        path: fileCacheItem.path,
                        isDirectory: fileCacheItem.isDirectory,
                        size: fileCacheItem.size,
                        modificationDate: fileCacheItem.modificationDate,
                        permissions: fileCacheItem.permissions,
                        owner: nil,
                        group: nil,
                        creationDate: nil,
                        lastAccessDate: nil
                    )
                }
                // LRU：移动到最近使用
                if let index = fileListAccessOrder.firstIndex(of: key) {
                    fileListAccessOrder.remove(at: index)
                }
                fileListAccessOrder.append(key)
            } else {
                print("❌ [Cache] getFileList: 内存缓存未命中 key=\(key)")
            }
        }
        return result
    }
    
    // MARK: - ✅ 获取文件列表缓存（异步版本，用于子线程调用）
    func getFileList(key: String, completion: @escaping ([FileInfo]?) -> Void) {
        guard isCacheEnabled else {
            print("❌ [Cache] getFileList: 缓存已禁用")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        
        print("📋 [Cache] getFileList: 尝试获取内存缓存 key=\(key)")
        
        // ✅ 在子线程执行缓存读取
        Thread.detachNewThread { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            var result: [FileInfo]?
            self.fileListCacheQueue.sync {
                if let cached = self.fileListCache[key],
                   Date().timeIntervalSince(cached.cachedAt) < self.fileListTTL {
                    print("✅ [Cache] getFileList: 内存缓存命中 key=\(key)")
                    result = cached.files.map { fileCacheItem in
                        FileInfo(
                            name: fileCacheItem.name,
                            path: fileCacheItem.path,
                            isDirectory: fileCacheItem.isDirectory,
                            size: fileCacheItem.size,
                            modificationDate: fileCacheItem.modificationDate,
                            permissions: fileCacheItem.permissions,
                            owner: nil,
                            group: nil,
                            creationDate: nil,
                            lastAccessDate: nil
                        )
                    }
                    // LRU：移动到最近使用
                    if let index = self.fileListAccessOrder.firstIndex(of: key) {
                        self.fileListAccessOrder.remove(at: index)
                    }
                    self.fileListAccessOrder.append(key)
                } else {
                    print("❌ [Cache] getFileList: 内存缓存未命中 key=\(key)")
                }
            }
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    // MARK: - ✅ 获取文件列表缓存（同步版本，用于子线程内部调用）
    func getFileListSync(key: String) -> [FileInfo]? {
        guard isCacheEnabled else {
            print("❌ [Cache] getFileListSync: 缓存已禁用")
            return nil
        }
        
        print("📋 [Cache] getFileListSync: 尝试获取内存缓存 key=\(key)")
        
        var result: [FileInfo]?
        fileListCacheQueue.sync {
            if let cached = fileListCache[key],
               Date().timeIntervalSince(cached.cachedAt) < fileListTTL {
                print("✅ [Cache] getFileListSync: 内存缓存命中 key=\(key)")
                result = cached.files.map { fileCacheItem in
                    FileInfo(
                        name: fileCacheItem.name,
                        path: fileCacheItem.path,
                        isDirectory: fileCacheItem.isDirectory,
                        size: fileCacheItem.size,
                        modificationDate: fileCacheItem.modificationDate,
                        permissions: fileCacheItem.permissions,
                        owner: nil,
                        group: nil,
                        creationDate: nil,
                        lastAccessDate: nil
                    )
                }
                // LRU：移动到最近使用
                if let index = fileListAccessOrder.firstIndex(of: key) {
                    fileListAccessOrder.remove(at: index)
                }
                fileListAccessOrder.append(key)
            } else {
                print("❌ [Cache] getFileListSync: 内存缓存未命中 key=\(key)")
            }
        }
        return result
    }
    
    // MARK: - 设置文件列表缓存（仅内存）
    func setFileList(key: String, files: [FileInfo]) {
        guard isCacheEnabled else {
            print("❌ [Cache] setFileList: 缓存已禁用 key=\(key)")
            return
        }
        
        print("📋 [Cache] setFileList: 写入内存缓存 key=\(key), 文件数=\(files.count)")
        
        fileListCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // 内存缓存 LRU 淘汰
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
            
            let cacheModel = FileListCacheModel(
                serverID: key.components(separatedBy: "_").first ?? "",
                path: key,
                files: fileCacheItems,
                ttl: self.fileListTTL
            )
            
            self.fileListCache[key] = cacheModel
            
            // LRU：移动到最近使用
            if let index = self.fileListAccessOrder.firstIndex(of: key) {
                self.fileListAccessOrder.remove(at: index)
            }
            self.fileListAccessOrder.append(key)
            
            print("✅ [Cache] setFileList: 内存缓存写入完成 key=\(key), 文件数=\(files.count)")
        }
    }
    
    // MARK: - 失效文件列表缓存
    func invalidateFileList(key: String) {
        fileListCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.fileListCache.removeValue(forKey: key)
            self.fileListAccessOrder.removeAll { $0 == key }
            print("📋 [Cache] 已失效内存缓存: \(key)")
        }
    }
    
    func invalidateFileList(prefix: String) {
        fileListCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let keysToRemove = self.fileListCache.keys.filter { $0.hasPrefix(prefix) }
            for key in keysToRemove {
                self.fileListCache.removeValue(forKey: key)
                self.fileListAccessOrder.removeAll { $0 == key }
            }
            print("📋 [Cache] 已失效前缀内存缓存: \(prefix), 移除 \(keysToRemove.count) 个")
        }
    }
    
    // MARK: - 清除所有文件列表缓存（仅内存）
    func clearAllFileListCache() {
        fileListCacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.fileListCache.removeAll()
            self.fileListAccessOrder.removeAll()
            print("📋 [Cache] 已清除所有内存缓存")
        }
    }
    
    // MARK: - LRU 内存缓存淘汰
    func evictMemoryCache() {
        guard fileListAccessOrder.count > maxMemoryEntries / 2 else { return }
        
        let removeCount = max(1, fileListAccessOrder.count / 5)
        let keysToRemove = fileListAccessOrder.prefix(removeCount)
        for key in keysToRemove {
            fileListCache.removeValue(forKey: key)
        }
        fileListAccessOrder.removeFirst(removeCount)
        
        Logger.shared.debug("内存缓存 LRU 淘汰: 移除 \(removeCount) 个条目")
    }
}
