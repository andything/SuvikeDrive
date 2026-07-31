//
//  OTAEvents.swift
//  SuvikeDrive
//
//  功能: 版本更新、安装包下载、升级、回滚全套OTA事件
//

import AppKit
import Foundation

struct OTAUpdateAvailable: Event {
    let version: String
    let releaseNotes: String?
    let size: Int64
    let timestamp: Date
    
    init(version: String, releaseNotes: String? = nil, size: Int64 = 0) {
        self.version = version
        self.releaseNotes = releaseNotes
        self.size = size
        self.timestamp = Date()
    }
}

struct OTAPackageReady: Event {
    let version: String
    let packagePath: String
    let timestamp: Date
    
    init(version: String, packagePath: String) {
        self.version = version
        self.packagePath = packagePath
        self.timestamp = Date()
    }
}

struct OTAPackageCorrupted: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTADownloadProgress: Event {
    let version: String
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let timestamp: Date
    
    init(version: String, progress: Double, downloadedBytes: Int64, totalBytes: Int64) {
        self.version = version
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.timestamp = Date()
    }
}

struct OTADownloadComplete: Event {
    let version: String
    let packagePath: String
    let timestamp: Date
    
    init(version: String, packagePath: String) {
        self.version = version
        self.packagePath = packagePath
        self.timestamp = Date()
    }
}

struct OTAInstallStarted: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTAInstallComplete: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTAInstallFailed: Event {
    let version: String
    let error: String
    let timestamp: Date
    
    init(version: String, error: String) {
        self.version = version
        self.error = error
        self.timestamp = Date()
    }
}

struct OTARollbackStarted: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}

struct OTARollbackComplete: Event {
    let version: String
    let timestamp: Date
    
    init(version: String) {
        self.version = version
        self.timestamp = Date()
    }
}
