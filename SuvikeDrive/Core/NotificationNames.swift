//
//  NotificationNames.swift
//  SuvikeDrive
//
//  功能: 通知名称统一管理
//
//  ⚠️ 使用说明:
//  - NotificationCenter 用于 UI 层通信（窗口管理、状态刷新）
//  - EventBus (EventModels.swift) 用于业务层通信（挂载、传输、任务等）
//  - 两者分工明确，不要混淆使用
//

import AppKit
import Foundation

extension Notification.Name {
    // ============================================
    // MARK: - UI 层通知 (NotificationCenter)
    // 用途: 窗口管理、UI 刷新、用户交互反馈
    // 发送者: AppDelegate, ViewControllers, Views
    // 接收者: UI 层组件
    // ============================================
    
    // 窗口切换
    static let switchTab = Notification.Name("switchTab")
    
    // 功能窗口
    static let showSettings = Notification.Name("showSettings")
    static let showLogs = Notification.Name("showLogs")
    static let showConnections = Notification.Name("showConnections")
    static let showNewConnection = Notification.Name("showNewConnection")
    static let showAbout = Notification.Name("showAbout")
    
    // 状态刷新
    static let refreshConnections = Notification.Name("refreshConnections")
    static let MountStatusChanged = Notification.Name("MountStatusChanged")
    static let ConfigurationChanged = Notification.Name("ConfigurationChanged")
    static let NetworkStatusChanged = Notification.Name("NetworkStatusChanged")
    
    // 权限状态变更
    static let PermissionStatusChanged = Notification.Name("PermissionStatusChanged")
    
    // 日志更新
    static let logFileUpdated = Notification.Name("logFileUpdated")
    
    // 下载相关
    static let downloadFinished = Notification.Name("downloadFinished")
}

// ============================================
// MARK: - 业务层事件 (EventBus)
// 用途: 跨模块业务通信、数据流转
// 发送者: Managers, Services, ProtocolModules
// 接收者: 业务层模块
// 定义位置: EventModels.swift
// ============================================
// 包括:
// - MountStarted/MountCompleted/MountFailed
// - TransferStarted/TransferProgress/TransferCompleted
// - ConnectionStateChanged/HeartbeatReceived/HeartbeatFailed
// - TaskStarted/TaskCompleted
// - OTAUpdateAvailable/OTADownloadProgress
// - CacheCleaned/CacheSizeExceeded
// - 等等 (共 60+ 事件类型)
