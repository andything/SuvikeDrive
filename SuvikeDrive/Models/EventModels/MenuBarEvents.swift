//
//  MenuBarEvents.swift
//  SuvikeDrive
//
//  功能: 状态栏事件定义。菜单栏、日志、窗口管理均在此声明。
//
//

import Foundation

/// 状态栏 挂载/卸载 请求
struct MenuBarMountToggleRequested: Event {
    let serverID: String
}

/// 状态栏 编辑服务器 请求
struct MenuBarEditServerRequested: Event {
    let serverID: String
}

/// 状态栏 打开文件浏览器 请求
struct MenuBarOpenFileBrowserRequested: Event {
    let serverID: String?
}

/// 状态栏 打开新建连接 请求
struct MenuBarOpenNewConnectionRequested: Event {}

/// 状态栏 打开连接管理 请求
struct MenuBarOpenConnectionManagerRequested: Event {}

/// 状态栏 打开偏好设置 请求
struct MenuBarOpenSettingsRequested: Event {}

/// 状态栏 打开运行日志 请求
struct MenuBarOpenLogsRequested: Event {}

/// 状态栏 打开检查更新 请求
struct MenuBarOpenOTARequested: Event {}

/// 状态栏 打开关于 请求
struct MenuBarOpenAboutRequested: Event {}

/// 状态栏 退出应用 请求
struct MenuBarAppQuitRequested: Event {}


// MARK: - 日志窗口 控制事件
/// 请求刷新日志内容
struct LogRefreshRequested: Event {}

/// 请求清空日志文件
struct LogClearRequested: Event {}

/// 请求导出日志文件
struct LogExportRequested: Event {}

/// 请求获取日志文件路径
struct LogPathRequested: Event {}

/// 推送日志内容更新（给 LogView 使用）
struct LogContentUpdated: Event {
    let content: String
}
