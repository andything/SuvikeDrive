//
//  CacheManagerWebDAV.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - WebDAV文件缓存 + 镜像目录 + 快照 + ETag
//

import Foundation

extension CacheManager {
    
    // MARK: - 镜像缓存目录
    
    func getMirrorRootDirectory() -> URL {
        return getCacheDirectory()
    }
    
    func getServerMirrorDirectory(serverName: String) -> URL {
        let sanitizedName = serverName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        let dir = getMirrorRootDirectory().appendingPathComponent(sanitizedName)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func getServerMirrorDirectory(serverID: String, serverName: String) -> URL {
        let sanitizedName = serverName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
        
        let dir = getMirrorRootDirectory().appendingPathComponent(sanitizedName)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func getMirrorFilePath(serverName: String, remotePath: String) -> URL {
        let serverDir = getServerMirrorDirectory(serverName: serverName)
        let relativePath = remotePath.hasPrefix("/") ? String(remotePath.dropFirst()) : remotePath
        return serverDir.appendingPathComponent(relativePath)
    }
    
    func getMirrorFilePath(serverID: String, serverName: String, remotePath: String) -> URL {
        let serverDir = getServerMirrorDirectory(serverID: serverID, serverName: serverName)
        let relativePath = remotePath.hasPrefix("/") ? String(remotePath.dropFirst()) : remotePath
        return serverDir.appendingPathComponent(relativePath)
    }
    
    // MARK: - 快照目录
    
    func getSnapshotDirectory() -> URL {
        let metadataDir = cacheRootDir.appendingPathComponent(".metadata")
        let dir = metadataDir.appendingPathComponent("Snapshots")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - ETag 索引目录
    
    func getETagIndexDirectory() -> URL {
        let metadataDir = cacheRootDir.appendingPathComponent(".metadata")
        let dir = metadataDir.appendingPathComponent("ETagIndex")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - 快照管理
    
    func saveSnapshot(_ snapshot: DirectorySnapshot) {
        let dir = getSnapshotDirectory()
        let filename = "\(snapshot.serverID)_\(snapshot.path.replacingOccurrences(of: "/", with: "_")).json"
        let fileURL = dir.appendingPathComponent(filename)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL)
            print("📋 [Cache] 快照已保存: \(filename)")
        } catch {
            print("❌ [Cache] 保存快照失败: \(error)")
        }
    }
    
    func loadSnapshot(serverID: String, path: String) -> DirectorySnapshot? {
        let dir = getSnapshotDirectory()
        let filename = "\(serverID)_\(path.replacingOccurrences(of: "/", with: "_")).json"
        let fileURL = dir.appendingPathComponent(filename)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        do {
            let snapshot = try JSONDecoder().decode(DirectorySnapshot.self, from: data)
            return snapshot
        } catch {
            print("❌ [Cache] 加载快照失败: \(error)")
            return nil
        }
    }
    
    func deleteSnapshot(serverID: String, path: String) {
        let dir = getSnapshotDirectory()
        let filename = "\(serverID)_\(path.replacingOccurrences(of: "/", with: "_")).json"
        let fileURL = dir.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }
    
    // MARK: - ETag 管理
    
    func saveETagEntry(_ entry: ETagCacheEntry) {
        let dir = getETagIndexDirectory()
        let filename = "\(entry.serverID)_\(entry.path.replacingOccurrences(of: "/", with: "_")).json"
        let fileURL = dir.appendingPathComponent(filename)
        
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL)
        } catch {
            print("❌ [Cache] 保存ETag失败: \(error)")
        }
    }
    
    func loadETagEntry(serverID: String, path: String) -> ETagCacheEntry? {
        let dir = getETagIndexDirectory()
        let filename = "\(serverID)_\(path.replacingOccurrences(of: "/", with: "_")).json"
        let fileURL = dir.appendingPathComponent(filename)
        
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ETagCacheEntry.self, from: data)
    }
    
    func getCachedETag(serverID: String, path: String) -> String? {
        return loadETagEntry(serverID: serverID, path: path)?.etag
    }
    
    func deleteETagEntry(serverID: String, path: String) {
        let dir = getETagIndexDirectory()
        let filename = "\(serverID)_\(path.replacingOccurrences(of: "/", with: "_")).json"
        let fileURL = dir.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }
    
    // MARK: - 文件缓存检查
    
    func isFileCachedInMirror(serverID: String, serverName: String, remotePath: String) -> Bool {
        let localPath = getMirrorFilePath(serverID: serverID, serverName: serverName, remotePath: remotePath)
        return fileManager.fileExists(atPath: localPath.path)
    }
    
    func getCachedFileSize(serverID: String, serverName: String, remotePath: String) -> UInt64? {
        let localPath = getMirrorFilePath(serverID: serverID, serverName: serverName, remotePath: remotePath)
        guard let attrs = try? fileManager.attributesOfItem(atPath: localPath.path) else { return nil }
        return attrs[.size] as? UInt64
    }
    
    func removeCachedFileFromMirror(serverID: String, serverName: String, remotePath: String) {
        let localPath = getMirrorFilePath(serverID: serverID, serverName: serverName, remotePath: remotePath)
        if fileManager.fileExists(atPath: localPath.path) {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: localPath.path)
                let size = attrs[.size] as? UInt64 ?? 0
                try fileManager.removeItem(at: localPath)
                deleteETagEntry(serverID: serverID, path: remotePath)
                updateCacheSizeForServer(serverID: serverID, delta: -Int64(size))
            } catch {
                Logger.shared.warning("删除缓存文件失败: \(localPath.path)")
            }
        }
    }
    
    // MARK: - 目录同步
    
    @discardableResult
    func syncDirectory(
        serverID: String,
        serverName: String,
        path: String,
        remoteItems: [RemoteFileItem],
        directoryETag: String?
    ) -> (snapshot: DirectorySnapshot, changes: SnapshotChanges?) {
        
        let oldSnapshot = loadSnapshot(serverID: serverID, path: path)
        
        if let old = oldSnapshot, let etag = directoryETag, old.etag == etag {
            print("📋 [Cache] 目录未变化 (ETag匹配): \(path)")
            return (old, nil)
        }
        
        var items: [SnapshotItem] = []
        for remoteItem in remoteItems {
            let isCached = isFileCachedInMirror(serverID: serverID, serverName: serverName, remotePath: remoteItem.path)
            let cachedSize = isCached ? getCachedFileSize(serverID: serverID, serverName: serverName, remotePath: remoteItem.path) : nil
            
            let item = SnapshotItem(
                name: remoteItem.name,
                path: remoteItem.path,
                type: remoteItem.isDirectory ? .directory : .file,
                size: remoteItem.size,
                etag: remoteItem.etag,
                lastModified: remoteItem.modified,
                contentType: remoteItem.contentType,
                isCached: isCached,
                cachedAt: isCached ? Date() : nil,
                cachedSize: cachedSize
            )
            items.append(item)
            
            if let etag = remoteItem.etag, !remoteItem.isDirectory {
                let entry = ETagCacheEntry(
                    serverID: serverID,
                    path: remoteItem.path,
                    etag: etag,
                    size: remoteItem.size ?? 0,
                    lastModified: remoteItem.modified
                )
                saveETagEntry(entry)
            }
        }
        
        let newSnapshot = DirectorySnapshot(
            serverID: serverID,
            path: path,
            etag: directoryETag,
            items: items
        )
        
        var changes: SnapshotChanges?
        if let old = oldSnapshot {
            changes = diffSnapshots(old: old, new: newSnapshot)
        }
        
        saveSnapshot(newSnapshot)
        rebuildCacheIndex()
        
        print("📋 [Cache] 目录同步完成: \(path), 文件数=\(items.count)")
        return (newSnapshot, changes)
    }
    
    // MARK: - 快照比对
    
    func diffSnapshots(old: DirectorySnapshot, new: DirectorySnapshot) -> SnapshotChanges {
        let oldMap = Dictionary(uniqueKeysWithValues: old.items.map { ($0.path, $0) })
        let newMap = Dictionary(uniqueKeysWithValues: new.items.map { ($0.path, $0) })
        
        var added: [SnapshotItem] = []
        var modified: [SnapshotItem] = []
        var deleted: [String] = []
        var unchanged: [String] = []
        
        for (path, newItem) in newMap {
            if let oldItem = oldMap[path] {
                if oldItem.etag != newItem.etag {
                    modified.append(newItem)
                } else {
                    unchanged.append(path)
                }
            } else {
                added.append(newItem)
            }
        }
        
        for (path, _) in oldMap where newMap[path] == nil {
            deleted.append(path)
        }
        
        return SnapshotChanges(
            added: added,
            modified: modified,
            deleted: deleted,
            unchanged: unchanged
        )
    }
    
    // MARK: - 按需下载
    
    func downloadFileIfNeeded(
        serverID: String,
        serverName: String,
        remotePath: String,
        remoteETag: String?,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        
        let localPath = getMirrorFilePath(serverID: serverID, serverName: serverName, remotePath: remotePath)
        
        if fileManager.fileExists(atPath: localPath.path) {
            if let etag = remoteETag {
                let cachedETag = getCachedETag(serverID: serverID, path: remotePath)
                if cachedETag == etag {
                    return localPath
                } else {
                    try? fileManager.removeItem(at: localPath)
                    deleteETagEntry(serverID: serverID, path: remotePath)
                }
            } else {
                return localPath
            }
        }
        
        try fileManager.createDirectory(at: localPath.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        
        // TODO: 实际下载逻辑
        
        if let etag = remoteETag {
            let size = UInt64(try fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64 ?? 0)
            let entry = ETagCacheEntry(
                serverID: serverID,
                path: remotePath,
                etag: etag,
                size: size,
                lastModified: Date()
            )
            saveETagEntry(entry)
            updateCacheSizeForServer(serverID: serverID, delta: Int64(size))
        }
        
        updateSnapshotCacheStatus(serverID: serverID, path: remotePath, isCached: true)
        
        return localPath
    }
    
    // MARK: - 辅助方法
    
    private func updateSnapshotCacheStatus(serverID: String, path: String, isCached: Bool) {
        guard var snapshot = loadSnapshot(serverID: serverID, path: "/") else { return }
        
        if let index = snapshot.items.firstIndex(where: { $0.path == path }) {
            var item = snapshot.items[index]
            item.isCached = isCached
            item.cachedAt = isCached ? Date() : nil
            if !isCached {
                item.cachedSize = nil
            }
            snapshot.items[index] = item
            
            snapshot.cachedFiles = snapshot.items.filter { $0.isCached }.count
            snapshot.cachedSize = snapshot.items.compactMap { $0.cachedSize }.reduce(0, +)
            snapshot.updatedAt = Date()
            
            saveSnapshot(snapshot)
        }
    }
    
    // MARK: - 清理方法
    
    func clearWebDAVCache(serverID: String, serverName: String) {
        let serverDir = getServerMirrorDirectory(serverID: serverID, serverName: serverName)
        try? fileManager.removeItem(at: serverDir)
        
        deleteSnapshots(for: serverID)
        
        let etagDir = getETagIndexDirectory()
        let etagFiles = (try? fileManager.contentsOfDirectory(at: etagDir, includingPropertiesForKeys: nil)) ?? []
        for file in etagFiles where file.lastPathComponent.hasPrefix(serverID) {
            try? fileManager.removeItem(at: file)
        }
        
        invalidateFileList(prefix: "\(serverID)_")
        rebuildCacheIndex()
        Logger.shared.info("已清除镜像缓存: \(serverID)")
    }
    
    func clearAllWebDAVCaches() {
        let mirrorRoot = getMirrorRootDirectory()
        try? fileManager.removeItem(at: mirrorRoot)
        
        let metadataDir = cacheRootDir.appendingPathComponent(".metadata")
        try? fileManager.removeItem(at: metadataDir)
        
        clearAllFileListCache()
        
        sizeIndexLock.withLock {
            serverCacheSizes.removeAll()
            totalCacheSize = 0
        }
        
        Logger.shared.info("已清除所有镜像缓存")
    }
    
    func removeCachedFile(serverID: String, serverName: String, remotePath: String) {
        removeCachedFileFromMirror(serverID: serverID, serverName: serverName, remotePath: remotePath)
        updateSnapshotCacheStatus(serverID: serverID, path: remotePath, isCached: false)
        rebuildCacheIndex()
    }
}

// MARK: - 兼容旧调用

extension CacheManager {
    
    func getServerMirrorDirectory(serverID: String) -> URL {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        return getServerMirrorDirectory(serverID: serverID, serverName: serverName)
    }
    
    func getMirrorFilePath(serverID: String, remotePath: String) -> URL {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        return getMirrorFilePath(serverID: serverID, serverName: serverName, remotePath: remotePath)
    }
    
    func isFileCachedInMirror(serverID: String, remotePath: String) -> Bool {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        return isFileCachedInMirror(serverID: serverID, serverName: serverName, remotePath: remotePath)
    }
    
    func clearWebDAVCache(serverID: String) {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        clearWebDAVCache(serverID: serverID, serverName: serverName)
    }
    
    func removeCachedFile(serverID: String, remotePath: String) {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        removeCachedFile(serverID: serverID, serverName: serverName, remotePath: remotePath)
    }
    
    func getCachedFileSize(serverID: String, remotePath: String) -> UInt64? {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        return getCachedFileSize(serverID: serverID, serverName: serverName, remotePath: remotePath)
    }
    
    func removeCachedFileFromMirror(serverID: String, remotePath: String) {
        let servers = ConfigurationManager.shared.getServers()
        let serverName = servers.first(where: { $0.id == serverID })?.name ?? serverID
        removeCachedFileFromMirror(serverID: serverID, serverName: serverName, remotePath: remotePath)
    }
}
