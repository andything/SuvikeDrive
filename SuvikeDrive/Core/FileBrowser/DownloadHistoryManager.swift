//
//  DownloadHistoryManager.swift
//  SuvikeDrive
//
//  功能: 管理已下载文件的记录
//

import Foundation

class DownloadHistoryManager {
    static let shared = DownloadHistoryManager()
    private init() {}
    
    private let userDefaults = UserDefaults.standard
    private let key = "downloaded_files"
    
    /// 记录已下载的文件
    func markAsDownloaded(fileName: String, serverID: String, localPath: String) {
        var history = getDownloadHistory()
        let key = "\(serverID)_\(fileName)"
        history[key] = localPath
        userDefaults.set(history, forKey: self.key)
        print("📋 [DownloadHistory] 记录下载: \(fileName) -> \(localPath)")
    }
    
    /// 检查文件是否已下载
    func isFileDownloaded(fileName: String, serverID: String) -> Bool {
        let history = getDownloadHistory()
        let key = "\(serverID)_\(fileName)"
        
        guard let localPath = history[key] else {
            return false
        }
        
        // 检查文件是否还存在
        return FileManager.default.fileExists(atPath: localPath)
    }
    
    /// 获取已下载文件列表
    func getDownloadHistory() -> [String: String] {
        return userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
    
    /// 删除下载记录
    func removeDownloadRecord(fileName: String, serverID: String) {
        var history = getDownloadHistory()
        let key = "\(serverID)_\(fileName)"
        history.removeValue(forKey: key)
        userDefaults.set(history, forKey: self.key)
    }
    
    /// 清理不存在的文件记录
    func cleanInvalidRecords() {
        var history = getDownloadHistory()
        var removedCount = 0
        
        for (key, localPath) in history {
            if !FileManager.default.fileExists(atPath: localPath) {
                history.removeValue(forKey: key)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            userDefaults.set(history, forKey: self.key)
            print("📋 [DownloadHistory] 清理了 \(removedCount) 条无效记录")
        }
    }
}
