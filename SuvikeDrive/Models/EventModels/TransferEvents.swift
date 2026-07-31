//
//  TransferEvents.swift
//  SuvikeDrive
//
//  功能: 文件上传下载传输全流程事件
//

import AppKit
import Foundation

// MARK: - 传输开始
struct TransferStarted: Event {
    let transferID: String
    let serverID: String
    let filePath: String
    let localPath: String
    let totalBytes: UInt64
    let isUpload: Bool
    let timestamp: Date
    
    init(transferID: String, serverID: String, filePath: String, localPath: String, totalBytes: UInt64, isUpload: Bool) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.isUpload = isUpload
        self.timestamp = Date()
    }
}

// MARK: - 传输进度
struct TransferProgress: Event {
    let transferID: String
    let serverID: String
    let bytesTransferred: UInt64
    let totalBytes: UInt64
    let speed: UInt64
    let timestamp: Date
    
    init(transferID: String, serverID: String, bytesTransferred: UInt64, totalBytes: UInt64, speed: UInt64 = 0) {
        self.transferID = transferID
        self.serverID = serverID
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.speed = speed
        self.timestamp = Date()
    }
    
    var progress: Double {
        return totalBytes > 0 ? Double(bytesTransferred) / Double(totalBytes) : 0
    }
    
    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }
    
    var remainingBytes: UInt64 {
        return totalBytes - bytesTransferred
    }
    
    var estimatedRemainingTime: TimeInterval? {
        guard speed > 0 && remainingBytes > 0 else { return nil }
        return TimeInterval(remainingBytes) / TimeInterval(speed)
    }
}

// MARK: - 传输完成
struct TransferCompleted: Event {
    let transferID: String
    let serverID: String
    let filePath: String
    let totalBytes: UInt64
    let duration: TimeInterval
    let timestamp: Date
    
    init(transferID: String, serverID: String, filePath: String, totalBytes: UInt64, duration: TimeInterval) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.totalBytes = totalBytes
        self.duration = duration
        self.timestamp = Date()
    }
    
    var averageSpeed: UInt64 {
        return duration > 0 ? UInt64(Double(totalBytes) / duration) : 0
    }
}

// MARK: - 传输失败
struct TransferFailed: Event {
    let transferID: String
    let serverID: String
    let filePath: String
    let error: String
    let bytesTransferred: UInt64
    let timestamp: Date
    
    init(transferID: String, serverID: String, filePath: String, error: String, bytesTransferred: UInt64) {
        self.transferID = transferID
        self.serverID = serverID
        self.filePath = filePath
        self.error = error
        self.bytesTransferred = bytesTransferred
        self.timestamp = Date()
    }
}

// MARK: - 传输暂停/恢复/取消
struct TransferPaused: Event {
    let transferID: String
    let serverID: String
    let timestamp: Date
    
    init(transferID: String, serverID: String) {
        self.transferID = transferID
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct TransferResumed: Event {
    let transferID: String
    let serverID: String
    let timestamp: Date
    
    init(transferID: String, serverID: String) {
        self.transferID = transferID
        self.serverID = serverID
        self.timestamp = Date()
    }
}

struct TransferCancelled: Event {
    let transferID: String
    let serverID: String
    let timestamp: Date
    
    init(transferID: String, serverID: String) {
        self.transferID = transferID
        self.serverID = serverID
        self.timestamp = Date()
    }
}

// MARK: - ✅ 简化的上传下载事件（用于 FileBrowserViewModel）
struct FileDownloadProgress: Event {
    let fileName: String
    let filePath: String
    let progress: Double
    let bytesTransferred: Int64
    
    init(fileName: String, filePath: String, progress: Double, bytesTransferred: Int64) {
        self.fileName = fileName
        self.filePath = filePath
        self.progress = progress
        self.bytesTransferred = bytesTransferred
    }
}

struct FileDownloadComplete: Event {
    let fileName: String
    let filePath: String
    let success: Bool
    let localPath: String?
    let error: String?
    
    init(fileName: String, filePath: String, success: Bool, localPath: String? = nil, error: String? = nil) {
        self.fileName = fileName
        self.filePath = filePath
        self.success = success
        self.localPath = localPath
        self.error = error
    }
}

struct FileUploadProgress: Event {
    let fileName: String
    let filePath: String
    let progress: Double
    let bytesTransferred: Int64
    
    init(fileName: String, filePath: String, progress: Double, bytesTransferred: Int64) {
        self.fileName = fileName
        self.filePath = filePath
        self.progress = progress
        self.bytesTransferred = bytesTransferred
    }
}

struct FileUploadComplete: Event {
    let fileName: String
    let filePath: String
    let success: Bool
    let error: String?
    
    init(fileName: String, filePath: String, success: Bool, error: String? = nil) {
        self.fileName = fileName
        self.filePath = filePath
        self.success = success
        self.error = error
    }
}

// MARK: - ✅ 取消传输事件
struct CancelDownloadRequest: Event {
    let filePath: String
}

struct CancelUploadRequest: Event {
    let filePath: String
}
