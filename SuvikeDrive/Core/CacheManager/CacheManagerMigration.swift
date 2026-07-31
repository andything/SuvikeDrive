//
//  CacheManagerMigration.swift
//  SuvikeDrive
//
//  功能: 缓存管理器 - 缓存迁移
//

import Foundation

extension CacheManager {
    
    // MARK: - 缓存迁移
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
                    
                    try self.fileManager.copyItem(at: file, to: destFile)
                    
                    processedFiles += 1
                    let percent = Double(processedFiles) / Double(totalFiles) * 100
                    self.migrationProgress?.completedUnitCount = Int64(percent)
                    
                    DispatchQueue.main.async {
                        progress(percent / 100)
                    }
                }
                
                try self.fileManager.removeItem(at: sourceURL)
                
                ConfigurationManager.shared.set(key: "webdav.cache.path", value: destURL.path)
                
                self.rebuildCacheIndex()
                
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
    
    // MARK: - 取消迁移
    func cancelMigration() {
        migrationCancelled = true
    }
    
    // MARK: - 获取迁移进度
    func getMigrationProgress() -> Progress? {
        return migrationProgress
    }
    
    // MARK: - 是否正在迁移
    var isMigrationInProgress: Bool {
        return isMigrating
    }
}
