//
//  DaemonWatchdogEvents.swift
//  SuvikeDrive
//
//  功能: 看门狗、守护进程开关与状态刷新事件
//

import AppKit
import Foundation

// MARK: - 请求事件 (UI → 业务层)
struct ToggleWatchdogRequest: Event {
    let enabled: Bool
    let timestamp: Date
    init(enabled: Bool) {
        self.enabled = enabled
        self.timestamp = Date()
    }
}

struct ToggleDaemonRequest: Event {
    let enabled: Bool
    let timestamp: Date
    init(enabled: Bool) {
        self.enabled = enabled
        self.timestamp = Date()
    }
}

struct RefreshWatchdogStatusRequest: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

// MARK: - 状态推送事件 (业务层 → UI)
struct WatchdogStatusUpdated: Event {
    let isInstalled: Bool
    let isRunning: Bool
    let isEnabled: Bool
    let timestamp: Date
    init(isInstalled: Bool, isRunning: Bool, isEnabled: Bool) {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }
}

struct DaemonStatusUpdated: Event {
    let isInstalled: Bool
    let isRunning: Bool
    let isEnabled: Bool
    let timestamp: Date
    init(isInstalled: Bool, isRunning: Bool, isEnabled: Bool) {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.isEnabled = isEnabled
        self.timestamp = Date()
    }
}
