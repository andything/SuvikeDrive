//
//  SettingsViewModel.swift
//  SuvikeDrive
//
//  功能: 偏好设置数据模型 (纯数据)
//

import SwiftUI
import Combine

class SettingsViewModel: ObservableObject {
    // MARK: - EventBus 订阅
    var eventTokens: [SubscriptionToken] = []
    
    // MARK: - 通用设置
    @Published var startAtLogin: Bool = false
    @Published var autoMount: Bool = false
    @Published var showDesktop: Bool = false
    @Published var shortName: Bool = true
    @Published var mountDelay: Int = 3
    @Published var refreshInterval: Int = 60
    
    // MARK: - 网络设置
    @Published var timeout: Int = 30
    @Published var maxRetries: Int = 3
    
    // MARK: - 日志设置
    @Published var enableLogging: Bool = true
    @Published var logLevel: String = "信息"
    @Published var analytics: Bool = false
    
    // MARK: - 加密设置
    @Published var forceEncryptExport: Bool = true
    @Published var exportPassword: String = ""
    @Published var confirmExportPassword: String = ""
    @Published var showingPasswordMismatch = false
    
    // MARK: - 缓存设置
    @Published var cacheEnabled: Bool = true
    @Published var cacheAutoCleanup: Bool = true
    @Published var cacheMaxDiskSize: String = "500 MB"
    @Published var cacheMaxMemoryEntries: String = "100"
    @Published var cacheTTL: String = "7天"
    @Published var cacheFileListTTL: String = "60秒"
    @Published var cacheWebDAVTTL: String = "24小时"
    @Published var maxCacheSize: String = "10 GB"
    @Published var cachePath: String = ""
    
    // MARK: - 同步设置
    @Published var autoSyncEnabled: Bool = true
    @Published var syncOnLaunch: Bool = false
    @Published var syncRealtime: Bool = true
    @Published var syncDirection: String = "双向同步"
    @Published var conflictStrategy: String = "保留最新"
    @Published var syncLocalPath: String = "~/Documents/Sync"
    @Published var syncRemotePath: String = "/"
    @Published var syncIncludeSubdirs: Bool = true
    @Published var syncHiddenFiles: Bool = false
    @Published var syncDeleteRemote: Bool = false
    
    // MARK: - 同步统计
    @Published var lastSyncTime: String = "从未同步"
    @Published var syncStatus: String = "未同步"
    @Published var pendingSyncCount: Int = 0
    
    // MARK: - 同步底栏状态
    @Published var isSyncRunning: Bool = false
    
    // MARK: - 状态栏流量监控
    @Published var statusBarTrafficMonitor: Bool = true
    
    // MARK: - 全盘访问权限
    @Published var hasFullDiskAccess: Bool = false
    @Published var isCheckingPermission: Bool = false
    
    // MARK: - 守护进程状态
    @Published var daemonInstalled: Bool = false
    @Published var daemonRunning: Bool = false
    @Published var daemonEnabled: Bool = true
    
    // MARK: - UI 刷新触发器
    @Published var serverListVersion: Int = 0
    
    // MARK: - 常量
    let logLevels = ["调试", "信息", "警告", "错误", "崩溃"]
    let cacheSizeOptions = ["100 MB", "200 MB", "500 MB", "1 GB", "2 GB", "5 GB", "10 GB", "无限制"]
    let cacheEntryOptions = ["50", "100", "200", "500", "1000"]
    let cacheTTLOptions = ["1天", "3天", "7天", "14天", "30天", "永不"]
    let fileListTTLOptions = ["30秒", "60秒", "120秒", "300秒", "600秒", "永不"]
    let webDAVTTLOptions = ["1小时", "6小时", "12小时", "24小时", "3天", "7天", "永不"]
    
    // MARK: - 映射表
    let diskSizeMap: [String: UInt64] = [
        "100 MB": 100 * 1024 * 1024,
        "200 MB": 200 * 1024 * 1024,
        "500 MB": 500 * 1024 * 1024,
        "1 GB": 1024 * 1024 * 1024,
        "2 GB": 2 * 1024 * 1024 * 1024,
        "5 GB": 5 * 1024 * 1024 * 1024,
        "10 GB": 10 * 1024 * 1024 * 1024,
        "无限制": 0
    ]
    
    let ttlMap: [String: Int] = [
        "1天": 1, "3天": 3, "7天": 7, "14天": 14, "30天": 30, "永不": 0
    ]
    
    let fileListTTLMap: [String: TimeInterval] = [
        "30秒": 30, "60秒": 60, "120秒": 120, "300秒": 300, "600秒": 600, "永不": 0
    ]
    
    let webDAVTTLMap: [String: TimeInterval] = [
        "1小时": 3600, "6小时": 21600, "12小时": 43200,
        "24小时": 86400, "3天": 259200, "7天": 604800, "永不": 0
    ]
}
