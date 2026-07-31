//
//  AppLifecycleEvents.swift
//  SuvikeDrive
//
//  功能: 应用生命周期事件 + 系统底层事件(休眠、网络、磁盘空间告警)
//

import AppKit
import Foundation

// MARK: - 应用生命周期事件
struct AppDidFinishLaunching: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct AppWillTerminate: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct AppDidBecomeActive: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct AppWillResignActive: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

// MARK: - 系统底层事件
struct SystemSleep: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct SystemWake: Event {
    let timestamp: Date
    init() { self.timestamp = Date() }
}

struct NetworkChanged: Event {
    let isConnected: Bool
    let timestamp: Date
    
    init(isConnected: Bool) {
        self.isConnected = isConnected
        self.timestamp = Date()
    }
}

struct DiskSpaceLow: Event {
    let freeSpace: UInt64
    let threshold: UInt64
    let timestamp: Date
    
    init(freeSpace: UInt64, threshold: UInt64) {
        self.freeSpace = freeSpace
        self.threshold = threshold
        self.timestamp = Date()
    }
}
