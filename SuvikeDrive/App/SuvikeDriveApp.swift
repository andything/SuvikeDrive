//
//  SuvikeDriveApp.swift
//  SuvikeDrive
//
//  功能: 应用入口
//

import SwiftUI
import AppKit

@main
struct SuvikeDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        let arguments = CommandLine.arguments
        let isWatchdogMode = arguments.contains("--watchdog-mode")
        
        if isWatchdogMode {
            print("🛡️ 看门狗子进程入口 (PID: \(ProcessInfo.processInfo.processIdentifier))")
            
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: false)
            }
            
            DispatchQueue.global(qos: .utility).async {
                WatchdogSubprocess.shared.run()
            }
        } else {
            print("📋 主进程入口 (PID: \(ProcessInfo.processInfo.processIdentifier))")
        }
    }
    
    // ✅ 统一返回一个 Scene，不区分模式
    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
    }
}
