//
//  ConfigurationEvents.swift
//  SuvikeDrive
//
//  功能: 全局App配置变更、导入导出备份、SettingsView全局设置读写事件
//

import AppKit
import Foundation

// MARK: - 通用配置变更
struct ConfigurationChanged: Event {
    let key: String
    let oldValue: Any?
    let newValue: Any?
    let timestamp: Date
    
    init(key: String, oldValue: Any?, newValue: Any?) {
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}

struct ConfigurationImported: Event {
    let source: String
    let format: String
    let timestamp: Date
    
    init(source: String, format: String) {
        self.source = source
        self.format = format
        self.timestamp = Date()
    }
}

struct ConfigurationExported: Event {
    let destination: String
    let format: String
    let timestamp: Date
    
    init(destination: String, format: String) {
        self.destination = destination
        self.format = format
        self.timestamp = Date()
    }
}

struct ConfigurationBackupCreated: Event {
    let backupFile: String
    let timestamp: Date
    
    init(backupFile: String) {
        self.backupFile = backupFile
        self.timestamp = Date()
    }
}

struct ConfigurationBackupRestored: Event {
    let backupFile: String
    let timestamp: Date
    
    init(backupFile: String) {
        self.backupFile = backupFile
        self.timestamp = Date()
    }
}

// MARK: - App全局设置读写（SettingsView）
struct LoadSettingsRequest: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct SaveSettingsRequest: Event {
    let settings: [String: Any]
    let timestamp: Date
    init(settings: [String: Any]) {
        self.settings = settings
        self.timestamp = Date()
    }
}

struct SettingsLoaded: Event {
    let settings: [String: Any]
    let timestamp: Date
    init(settings: [String: Any]) {
        self.settings = settings
        self.timestamp = Date()
    }
}

struct SettingsSaved: Event {
    let success: Bool
    let error: String?
    let timestamp: Date
    init(success: Bool, error: String? = nil) {
        self.success = success
        self.error = error
        self.timestamp = Date()
    }
}
