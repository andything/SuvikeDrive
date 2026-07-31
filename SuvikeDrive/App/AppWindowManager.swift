//
//  AppWindowManager.swift
//  SuvikeDrive
//
//  功能: 所有窗口的创建和管理
//

import Cocoa
import SwiftUI

class AppWindowManager {
    static let shared = AppWindowManager()
    private init() {}
    
    // MARK: - 窗口引用
    var settingsWindow: NSWindow?
    var logsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var connectionWindow: NSWindow?
    var addServerWindow: NSWindow?
    var editServerWindow: NSWindow?
    var otaWindow: NSWindow?
    var fileBrowserWindow: NSWindow?
    
    // MARK: - OTA ViewModel
    private var otaViewModel = OTAManagerViewModel()
    
    // MARK: - 文件管理窗口（普通级别，不置顶）
    @objc func openFileBrowserWindow(serverID: String = "") {
        print("📋 [WindowManager] 打开文件管理窗口")
        
        if let window = fileBrowserWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let browserVM = FileBrowserViewModel(
            serverID: serverID,
            cacheManager: CacheManager.shared,
            eventBus: EventBus.shared
        )
        let browserView = FileBrowserView(viewModel: browserVM)
        let hostingController = NSHostingController(rootView: browserView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "\(AppInfo.appName) 文件管理"
        window.setContentSize(NSSize(width: 1200, height: 800))
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        styleMask.insert(.resizable)
        window.styleMask = styleMask
        window.minSize = NSSize(width: 500, height: 350)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal  // 普通级别
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        fileBrowserWindow = window
    }
    
    // MARK: - 设置窗口（置顶）
    @objc func openSettingsWindow() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = createWindow(
            contentViewController: hostingController,
            title: "偏好设置",
            size: NSSize(width: 660, height: 510),
            minSize: NSSize(width: 660, height: 600),
            level: .floating
        )
        settingsWindow = window
    }
    
    // MARK: - 日志窗口（置顶）
    @objc func openLogsWindow() {
        if let window = logsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let logView = LogView()
        let hostingController = NSHostingController(rootView: logView)
        
        let window = createWindow(
            contentViewController: hostingController,
            title: "\(AppInfo.appName) - 运行日志",
            size: NSSize(width: 1000, height: 800),
            minSize: nil,
            level: .floating
        )
        logsWindow = window
    }
    
    // MARK: - 关于窗口（置顶）
    @objc func openAboutWindow() {
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let aboutView = AboutView()
        let hostingController = NSHostingController(rootView: aboutView)
        let window = createWindow(
            contentViewController: hostingController,
            title: "关于 \(AppInfo.appName)",
            size: NSSize(width: 400, height: 300),
            minSize: nil,
            resizable: false,
            level: .floating
        )
        aboutWindow = window
    }
    
    // MARK: - 连接管理窗口（置顶）
    @objc func openConnectionWindow() {
        if let window = connectionWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let connectionView = ConnectionListView()
        let hostingController = NSHostingController(rootView: connectionView)
        let window = createWindow(
            contentViewController: hostingController,
            title: "连接管理",
            size: NSSize(width: 700, height: 500),
            minSize: nil,
            level: .floating
        )
        connectionWindow = window
    }
    
    // MARK: - 新建连接窗口（置顶）
    @objc func openAddServerWindow() {
        if let window = addServerWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let addServerView = AddServerView()
        let hostingController = NSHostingController(rootView: addServerView)
        let window = createWindow(
            contentViewController: hostingController,
            title: "新建连接",
            size: NSSize(width: 560, height: 660),
            minSize: nil,
            resizable: false,
            level: .floating
        )
        addServerWindow = window
    }
    
    // MARK: - 编辑连接窗口（置顶）
    @objc func openEditServerWindow(serverID: String?) {
        if let window = editServerWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let addServerView = AddServerView(serverID: serverID, isEditing: true)
        let hostingController = NSHostingController(rootView: addServerView)
        let window = createWindow(
            contentViewController: hostingController,
            title: "编辑连接",
            size: NSSize(width: 560, height: 660),
            minSize: nil,
            resizable: false,
            level: .floating
        )
        editServerWindow = window
    }
    
    // MARK: - OTA 更新窗口（置顶）
    @objc func openOTAWindow() {
        openOTAWindow(with: nil)
    }
    
    func openOTAWindow(with updateInfo: OTAUpdateAvailable?) {
        if let window = otaWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let otaView = OTAManagerView(viewModel: otaViewModel)
        let hostingController = NSHostingController(rootView: otaView)
        let window = createWindow(
            contentViewController: hostingController,
            title: "检查更新",
            size: NSSize(width: 500, height: 450),
            minSize: NSSize(width: 400, height: 350),
            level: .floating
        )
        otaWindow = window
        
        if updateInfo == nil {
            otaViewModel.checkForUpdate()
        }
    }
    
    // MARK: - 辅助方法
    private func createWindow(
        contentViewController: NSViewController,
        title: String,
        size: NSSize,
        minSize: NSSize? = nil,
        resizable: Bool = true,
        level: NSWindow.Level = .floating  // ✅ 默认置顶
    ) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)
        window.title = title
        window.setContentSize(size)
        
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable {
            styleMask.insert(.resizable)
        }
        window.styleMask = styleMask
        
        if let minSize = minSize {
            window.minSize = minSize
        }
        
        // ✅ 设置窗口级别
        window.level = level
        
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
