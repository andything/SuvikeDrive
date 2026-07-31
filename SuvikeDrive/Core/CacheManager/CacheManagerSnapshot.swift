//
//  CacheManagerSnapshot.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 快照管理
//

import Foundation

extension CacheManager {
    
    func getAllSnapshots() -> [DirectorySnapshot] {
        let dir = getSnapshotDirectory()
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var snapshots: [DirectorySnapshot] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let snapshot = try? JSONDecoder().decode(DirectorySnapshot.self, from: data) else {
                continue
            }
            snapshots.append(snapshot)
        }
        return snapshots
    }
    
    func getSnapshots(for serverID: String) -> [DirectorySnapshot] {
        let all = getAllSnapshots()
        return all.filter { $0.serverID == serverID }
    }
    
    func getSnapshotStats(serverID: String, path: String) -> SnapshotStats? {
        guard let snapshot = loadSnapshot(serverID: serverID, path: path) else {
            return nil
        }
        return SnapshotStats(snapshot: snapshot)
    }
    
    func getAllSnapshotStats() -> [SnapshotStats] {
        let snapshots = getAllSnapshots()
        return snapshots.map { SnapshotStats(snapshot: $0) }
    }
    
    func cleanExpiredSnapshots(olderThan days: Int = 30) {
        let dir = getSnapshotDirectory()
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        
        let expirationDate = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        var removedCount = 0
        
        for file in files where file.pathExtension == "json" {
            guard let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                  let creationDate = attrs[.creationDate] as? Date else {
                continue
            }
            
            if creationDate < expirationDate {
                try? fileManager.removeItem(at: file)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            print("📋 [Cache] 清理了 \(removedCount) 个过期快照")
        }
    }
    
    func deleteSnapshots(for serverID: String) {
        let dir = getSnapshotDirectory()
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.lastPathComponent.hasPrefix(serverID) {
            try? fileManager.removeItem(at: file)
        }
        print("📋 [Cache] 已删除服务器快照: \(serverID)")
    }
}
