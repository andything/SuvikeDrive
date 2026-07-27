//
//  AppDelegate.swift
//  SuvikeDrive
//
//  功能: 应用代理，管理状态栏
//

import Cocoa
import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    var mainPopover: NSPopover?
    var connectionPopover: NSPopover?
    
    // ✅ 看门狗模式标志
    private var isWatchdogMode: Bool {
        return ProcessInfo.processInfo.arguments.contains("--watchdog-mode")
    }
    
    // MARK: - 应用生命周期
    func applicationWillFinishLaunching(_ notification: Notification) {
        // ✅ 看门狗模式：完全静默运行
        if isWatchdogMode {
            print("🛡️ 看门狗子进程运行中 (PID: \(ProcessInfo.processInfo.processIdentifier))")
            // 设置后台策略，不显示 Dock 图标
            NSApp.setActivationPolicy(.accessory)
            // 启动看门狗监控循环
            DispatchQueue.global(qos: .utility).async {
                WatchdogSubprocess.shared.run()
            }
            return
        }
        
        AppLifecycleManager.shared.start()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ✅ 看门狗模式：不做任何 UI 初始化
        if isWatchdogMode {
            return
        }
        
        Logger.shared.setLogLevel(.debug)
        print("\(AppInfo.appName) 启动")
        configureGlobalScrollBarStyle()
        setupStatusBar()
        
        // 启动业务层
        _ = ServerConfigManager.shared
        _ = SettingsManager.shared
        
        // ✅ 启动守护进程（独立子进程）
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            let enabled = ConfigurationManager.shared.get(key: "app.daemon.enabled", defaultValue: true)
            if enabled {
                WatchdogProcessManager.shared.startWatchdog()
            }
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closeMainPopover),
            name: NSNotification.Name("CloseMainPopover"),
            object: nil
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("📢 应用即将退出")
        Logger.shared.info("应用即将退出")
        
        AppLifecycleManager.shared.stop()
        WatchdogProcessManager.shared.cleanup()
    }
    
    // MARK: - 全局移除滚动条
    private func configureGlobalScrollBarStyle() {
        DispatchQueue.main.async {
            self.configureAllScrollViews()
        }
    }
    
    private func configureAllScrollViews() {
        for window in NSApp.windows {
            configureScrollViews(in: window.contentView)
        }
    }
    
    private func configureScrollViews(in view: NSView?) {
        guard let view = view else { return }
        
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            return
        }
        
        for subview in view.subviews {
            configureScrollViews(in: subview)
        }
    }
    
    // MARK: - 弹窗管理
    private func closeAllPopovers() {
        if let popover = mainPopover, popover.isShown {
            popover.performClose(nil)
        }
        if let popover = connectionPopover, popover.isShown {
            popover.performClose(nil)
        }
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            let icon = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "SuvikeDrive")
            button.image = icon
            button.imagePosition = .imageLeading
            button.action = #selector(toggleMainPopover)
            button.target = self
        }
        
        let menuView = MenuBarView()
        let hostingController = NSHostingController(rootView: menuView)
        
        mainPopover = NSPopover()
        mainPopover?.contentSize = NSSize(width: 320, height: 480)
        mainPopover?.behavior = .transient
        mainPopover?.animates = true
        mainPopover?.contentViewController = hostingController
        
        let connectionView = ConnectionListView()
        let connectionHostingController = NSHostingController(rootView: connectionView)
        
        connectionPopover = NSPopover()
        connectionPopover?.contentSize = NSSize(width: 380, height: 420)
        connectionPopover?.behavior = .transient
        connectionPopover?.animates = true
        connectionPopover?.contentViewController = connectionHostingController
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openConnectionPopover),
            name: NSNotification.Name("OpenConnectionPopover"),
            object: nil
        )
    }
    
    // MARK: - 主弹窗切换
    @objc private func toggleMainPopover() {
        guard let button = statusItem?.button else { return }
        guard let popover = mainPopover else { return }
        
        if let connPopover = connectionPopover, connPopover.isShown {
            connPopover.performClose(nil)
        }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            configureAllScrollViews()
        }
    }
    
    @objc private func closeMainPopover() {
        mainPopover?.performClose(nil)
    }
    
    @objc private func openConnectionPopover() {
        guard let button = statusItem?.button else { return }
        guard let popover = connectionPopover else { return }
        
        if let mainPop = mainPopover, mainPop.isShown {
            mainPop.performClose(nil)
        }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            configureAllScrollViews()
        }
    }
}
