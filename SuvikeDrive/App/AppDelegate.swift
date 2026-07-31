//
//  AppDelegate.swift
//  SuvikeDrive
//
//  功能: 应用代理，仅负责生命周期和状态栏启动开关
//  通信: 业务通知通过 EventBus
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - 窗口管理器
    private let windowManager = AppWindowManager.shared
    
    // MARK: - EventBus 订阅
    private var eventTokens: [SubscriptionToken] = []
    
    // MARK: - 挂载状态
    private var pendingMountServerID: String?
    private var isWaitingForFileList = false
    
    // MARK: - 看门狗模式
    private var isWatchdogMode: Bool {
        return ProcessInfo.processInfo.arguments.contains("--watchdog-mode")
    }
    
    // MARK: - 看门狗启动标记
    private var hasStartedWatchdog = false
    private let watchdogLock = NSLock()
    
    // ✅ 核心：懒加载持有 StatusBar 实例
    private lazy var statusBar: StatusBarController = {
        return StatusBarController()
    }()
    
    // MARK: - 应用生命周期
    func applicationWillFinishLaunching(_ notification: Notification) {
        if isWatchdogMode { return }
        
        AppLifecycleManager.shared.start()
        
        #if DEBUG
        Logger.shared.setLogLevel(.debug)
        #else
        Logger.shared.setLogLevel(.info)
        #endif
        
        print("📋 \(AppInfo.appName) 主进程启动 (PID: \(ProcessInfo.processInfo.processIdentifier))")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isWatchdogMode { return }
        
        print("📋 \(AppInfo.appName) 初始化开始")
        
        // 极速启动区
        configureGlobalScrollBarStyle()
        setupWatchdogNotifications()
        
        // ✅ 触发状态栏懒加载
        _ = statusBar
        
        print("📋 \(AppInfo.appName) 初始化完成")
        
        // ✅ 后台懒加载区 - 关键：先注册订阅者，再初始化 CacheManager
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // ✅ 第一步：设置 EventBus 监听（包含 CacheSizeChanged 订阅）
            self.setupEventBusListeners()
            
            // ✅ 第二步：启动 LogManager
            LogManager.shared.startListening()
            
            // ✅ 第三步：初始化其他组件
            AppCacheManager.setup()
            _ = NetworkManager.shared
            _ = ServerConfigManager.shared
            _ = SettingsManager.shared
            
            // ✅ 第四步：初始化 CacheManager（此时订阅者已就绪）
            _ = CacheManager.shared
            
            // ✅ 第五步：日志路径监听
            let logPathToken = EventBus.shared.subscribe(
                to: LogPathRequested.self,
                priority: .high
            ) { _ in
                let path = Logger.shared.getLogDirectory().path
                DispatchQueue.main.async {
                    EventBus.shared.publish(LogContentUpdated(content: "日志目录: \(path)"))
                }
            }
            self.eventTokens.append(logPathToken)
            
            // ✅ 第六步：后续任务
            DispatchQueue.main.async { [weak self] in
                self?.performPostLaunchTasks()
                
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.startWatchdogIfEnabled()
                }
            }
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return AppLifecycleHandler.shouldTerminate()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        notifyWatchdogShutdown()
        AppLifecycleHandler.willTerminate(eventTokens: &eventTokens)
        print("📋 \(AppInfo.appName) 主进程退出")
    }
    
    // MARK: - 启动后任务
    private func performPostLaunchTasks() {
        DispatchQueue.global(qos: .background).async {
            let restartMarker = "/tmp/com.suvikedrive.watchdog.restarted"
            let isRestartedByWatchdog = FileManager.default.fileExists(atPath: restartMarker)
            
            if isRestartedByWatchdog {
                print("🔄 检测到看门狗重启标记，跳过挂载清理")
                try? FileManager.default.removeItem(atPath: restartMarker)
            } else {
                MountManager.shared.unmountAllVolumes()
            }
            
            MountManager.shared.verifyMountStatesEnhanced()
            
            let autoMount = ConfigurationManager.shared.get(key: "app.autoMount", defaultValue: false)
            if autoMount && !isRestartedByWatchdog {
                print("📋 [AppDelegate] 自动挂载所有服务器...")
                let servers = ConfigurationManager.shared.getServers()
                for server in servers where server.autoMount {
                    MountManager.shared.mount(serverID: server.id, config: server) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let path):
                                print("✅ [AppDelegate] 自动挂载成功: \(server.name) -> \(path)")
                            case .failure(let error):
                                print("❌ [AppDelegate] 自动挂载失败: \(server.name) - \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 看门狗管理
    private func startWatchdogIfEnabled() {
        watchdogLock.lock()
        defer { watchdogLock.unlock() }
        
        guard !hasStartedWatchdog else { return }
        
        let enabled = ConfigurationManager.shared.get(key: "app.daemon.enabled", defaultValue: true)
        guard enabled else {
            print("ℹ️ 看门狗已禁用")
            return
        }
        
        if WatchdogProcessManager.shared.isWatchdogActive() {
            print("ℹ️ 看门狗已在运行")
            hasStartedWatchdog = true
            return
        }
        
        print("🛡️ 启动看门狗...")
        WatchdogProcessManager.shared.startWatchdog()
        hasStartedWatchdog = true
    }
    
    private func notifyWatchdogShutdown() {
        let disableFile = "/tmp/com.suvikedrive.watchdog.disable"
        try? "disabled".write(toFile: disableFile, atomically: true, encoding: .utf8)
        
        WatchdogProcessManager.shared.stopWatchdog()
        try? FileManager.default.removeItem(atPath: "/tmp/com.suvikedrive.watchdog.restarted")
    }
    
    // MARK: - 看门狗通知
    private func setupWatchdogNotifications() {
        NotificationCenter.default.addObserver(
            forName: .watchdogDidDetectHang,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let elapsed = notification.userInfo?["elapsed"] as? Int ?? 0
            print("⚠️ 检测到主进程挂起 (\(elapsed)秒无响应)")
            
            let alert = NSAlert()
            alert.messageText = "应用无响应"
            alert.informativeText = "检测到应用主进程已挂起 \(elapsed) 秒，是否立即重启？"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "重启")
            alert.addButton(withTitle: "等待")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self?.restartMainApp()
            }
        }
    }
    
    private func restartMainApp() {
        print("🔄 用户触发应用重启...")
        try? "".write(toFile: "/tmp/com.suvikedrive.watchdog.restarted", atomically: true, encoding: .utf8)
        
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", appPath]
        
        do {
            try task.run()
            print("✅ 应用重启命令已发送")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            print("❌ 重启应用失败: \(error)")
        }
    }
    
    // MARK: - ✅ EventBus 监听 (全 EventBus 通信)
    private func setupEventBusListeners() {
        print("📋 [AppDelegate] 设置 EventBus 监听...")
        
        // ============================================================
        // ✅ 0. 缓存大小事件（优先级最高，确保最先注册）
        // ============================================================
        
        // 订阅总缓存大小变化 - 直接转发给 CacheTab
        let cacheSizeToken = EventBus.shared.subscribe(
            to: CacheSizeChanged.self,
            priority: .high
        ) { event in
            print("📊 [AppDelegate] 缓存总大小: \(event.formattedSize)")
            // 通过 NotificationCenter 转发给 UI 组件
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .cacheSizeChanged,
                    object: nil,
                    userInfo: ["size": event.formattedSize]
                )
            }
        }
        eventTokens.append(cacheSizeToken)
        
        // 订阅单个服务器缓存大小变化 - 直接转发给 CacheTab
        let serverCacheSizeToken = EventBus.shared.subscribe(
            to: ServerCacheSizeChanged.self,
            priority: .high
        ) { event in
            print("📊 [AppDelegate] 服务器 \(event.serverName) 缓存: \(event.formattedSize)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .serverCacheSizeChanged,
                    object: nil,
                    userInfo: [
                        "serverID": event.serverID,
                        "serverName": event.serverName,
                        "size": event.formattedSize
                    ]
                )
            }
        }
        eventTokens.append(serverCacheSizeToken)
        
        // 订阅缓存清除事件
        let cacheClearedToken = EventBus.shared.subscribe(
            to: CacheCleared.self,
            priority: .high
        ) { event in
            print("🗑️ [AppDelegate] 缓存已清除")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .cacheCleared,
                    object: nil,
                    userInfo: ["serverID": event.serverID as Any]
                )
            }
        }
        eventTokens.append(cacheClearedToken)
        
        // ---------------------------------------------------------
        // 1. 配置变更事件
        // ---------------------------------------------------------
        let configToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .high
        ) { [weak self] event in
            self?.handleConfigurationEvent(event)
        }
        eventTokens.append(configToken)
        
        let watchdogConfigToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .low
        ) { [weak self] event in
            if event.key == "app.daemon.enabled" {
                let enabled = event.newValue as? Bool ?? true
                DispatchQueue.global(qos: .utility).async {
                    if enabled {
                        self?.startWatchdogIfEnabled()
                    } else {
                        self?.watchdogLock.lock()
                        self?.hasStartedWatchdog = false
                        self?.watchdogLock.unlock()
                        WatchdogProcessManager.shared.stopWatchdog()
                    }
                }
            }
        }
        eventTokens.append(watchdogConfigToken)
        
        // ---------------------------------------------------------
        // 2. 原有挂载、文件列表监听
        // ---------------------------------------------------------
        let mountToken = EventBus.shared.subscribe(
            to: MountCompleted.self,
            priority: .high
        ) { [weak self] (event: MountCompleted) in
            self?.handleMountCompleted(event)
        }
        eventTokens.append(mountToken)
        
        let fileListToken = EventBus.shared.subscribe(
            to: FileListLoaded.self,
            priority: .high
        ) { [weak self] (event: FileListLoaded) in
            self?.handleFileListLoaded(event)
        }
        eventTokens.append(fileListToken)
        
        // ---------------------------------------------------------
        // 3. OTA 更新监听
        // ---------------------------------------------------------
        let otaToken = EventBus.shared.subscribe(
            to: OTAUpdateAvailable.self,
            priority: .high
        ) { [weak self] (event: OTAUpdateAvailable) in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("📋 [AppDelegate] OTA 更新可用: \(event.version)")
                self.windowManager.openOTAWindow(with: event)
            }
        }
        eventTokens.append(otaToken)
        
        // ---------------------------------------------------------
        // 4. 菜单栏 挂载/卸载 请求事件
        // ---------------------------------------------------------
        let mountToggleToken = EventBus.shared.subscribe(
            to: MenuBarMountToggleRequested.self,
            priority: .high
        ) { [weak self] event in
            print("📋 [AppDelegate] 收到挂载切换请求: \(event.serverID)")
            self?.toggleMount(serverID: event.serverID)
        }
        eventTokens.append(mountToggleToken)
        
        // ---------------------------------------------------------
        // 5. 菜单栏 编辑服务器 请求事件
        // ---------------------------------------------------------
        let editServerToken = EventBus.shared.subscribe(
            to: MenuBarEditServerRequested.self,
            priority: .high
        ) { [weak self] event in
            print("📋 [AppDelegate] 收到编辑服务器请求: \(event.serverID)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.windowManager.openEditServerWindow(serverID: event.serverID)
            }
        }
        eventTokens.append(editServerToken)
        
        // ✅ 新增：日志导出请求事件
        let logExportToken = EventBus.shared.subscribe(
            to: LogExportRequested.self,
            priority: .high
        ) { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let zipURL = Logger.shared.exportLogs() else {
                    DispatchQueue.main.async {
                        print("❌ 导出日志失败")
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                    print("✅ 日志导出成功，已打开 Finder 定位: \(zipURL.path)")
                }
            }
        }
        eventTokens.append(logExportToken)
        
        // ---------------------------------------------------------
        // 6. 菜单栏 新连接/连接管理/文件管理 请求事件
        // ---------------------------------------------------------
        let newConnToken = EventBus.shared.subscribe(
            to: MenuBarOpenNewConnectionRequested.self,
            priority: .high
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.windowManager.openAddServerWindow()
            }
        }
        eventTokens.append(newConnToken)
        
        let connMgrToken = EventBus.shared.subscribe(
            to: MenuBarOpenConnectionManagerRequested.self,
            priority: .high
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.windowManager.openConnectionWindow()
            }
        }
        eventTokens.append(connMgrToken)
        
        let fileBrowserToken = EventBus.shared.subscribe(
            to: MenuBarOpenFileBrowserRequested.self,
            priority: .high
        ) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                let serverID = event.serverID ?? self?.pendingMountServerID ?? ""
                print("📋 [AppDelegate] 收到状态栏打开文件浏览器请求: \(serverID)")
                self?.windowManager.openFileBrowserWindow(serverID: serverID)
            }
        }
        eventTokens.append(fileBrowserToken)
        
        // 保持原来 OpenFileBrowserRequest 的兼容
        let oldFileBrowserToken = EventBus.shared.subscribe(
            to: OpenFileBrowserRequest.self,
            priority: .low
        ) { [weak self] (event: OpenFileBrowserRequest) in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("📋 [AppDelegate] 收到旧的打开文件浏览器请求: \(event.serverID)")
                self.windowManager.openFileBrowserWindow(serverID: event.serverID)
            }
        }
        eventTokens.append(oldFileBrowserToken)
        
        // ---------------------------------------------------------
        // 7. 菜单栏 设置/关于/OTA 请求事件
        // ---------------------------------------------------------
        let settingsToken = EventBus.shared.subscribe(
            to: MenuBarOpenSettingsRequested.self,
            priority: .high
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.windowManager.openSettingsWindow()
            }
        }
        eventTokens.append(settingsToken)
        
        let aboutToken = EventBus.shared.subscribe(
            to: MenuBarOpenAboutRequested.self,
            priority: .high
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.windowManager.openAboutWindow()
            }
        }
        eventTokens.append(aboutToken)
        
        let otaMenuToken = EventBus.shared.subscribe(
            to: MenuBarOpenOTARequested.self,
            priority: .high
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.windowManager.openOTAWindow()
            }
        }
        eventTokens.append(otaMenuToken)
        
        // ---------------------------------------------------------
        // 8. 菜单栏 退出应用
        // ---------------------------------------------------------
        let quitToken = EventBus.shared.subscribe(
            to: MenuBarAppQuitRequested.self,
            priority: .high
        ) { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        eventTokens.append(quitToken)
        
        // ✅ 新增：日志窗口打开事件
        let logOpenToken = EventBus.shared.subscribe(
            to: MenuBarOpenLogsRequested.self,
            priority: .high
        ) { _ in
            DispatchQueue.main.async {
                print("📋 [AppDelegate] 收到打开日志请求")
                AppWindowManager.shared.openLogsWindow()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let content = Logger.shared.getLogFileContent() ?? "暂无日志内容"
                    DispatchQueue.main.async {
                        EventBus.shared.publish(LogContentUpdated(content: content))
                    }
                }
            }
        }
        eventTokens.append(logOpenToken)
        
        // ✅ 新增：日志刷新请求事件
        let logRefreshToken = EventBus.shared.subscribe(
            to: LogRefreshRequested.self,
            priority: .high
        ) { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                let content = Logger.shared.getLogFileContent() ?? "暂无日志内容"
                DispatchQueue.main.async {
                    EventBus.shared.publish(LogContentUpdated(content: content))
                }
            }
        }
        eventTokens.append(logRefreshToken)
        
        // ✅ 新增：日志清空请求事件
        let logClearToken = EventBus.shared.subscribe(
            to: LogClearRequested.self,
            priority: .high
        ) { _ in
            Logger.shared.clearAllLogs()
            DispatchQueue.main.async {
                EventBus.shared.publish(LogContentUpdated(content: "日志已清空"))
            }
        }
        eventTokens.append(logClearToken)
        
        print("📋 [AppDelegate] EventBus 监听设置完成，共 \(eventTokens.count) 个订阅")
    }
    
    // MARK: - 事件处理
    private func handleConfigurationEvent(_ event: ConfigurationChanged) {
        print("📋 [AppDelegate] 收到事件: key=\(event.key)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch event.key {
            case "popover.openSettings":
                self.windowManager.openSettingsWindow()
            case "popover.openLogs":
                self.windowManager.openLogsWindow()
            case "popover.openAbout":
                self.windowManager.openAboutWindow()
            case "popover.openConnection":
                self.windowManager.openConnectionWindow()
            case "popover.openNewConnection":
                self.windowManager.openAddServerWindow()
            case "popover.openEditConnection":
                let serverID = event.newValue as? String
                self.windowManager.openEditServerWindow(serverID: serverID)
            case "popover.openOTA":
                self.windowManager.openOTAWindow()
            case "popover.openFileBrowser":
                let serverID = self.pendingMountServerID ?? ""
                self.windowManager.openFileBrowserWindow(serverID: serverID)
            case "server.delete":
                if let serverID = event.newValue as? String {
                    self.deleteConnection(serverID: serverID)
                }
            default:
                break
            }
        }
    }
    
    private func handleMountCompleted(_ event: MountCompleted) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let pendingID = self.pendingMountServerID,
               pendingID == event.serverID && self.isWaitingForFileList {
                print("📋 [AppDelegate] 已存在待处理的挂载: \(event.serverID)，跳过重复事件")
                return
            }
            
            guard event.success else {
                print("📋 [AppDelegate] 挂载失败: \(event.serverID), error: \(event.error ?? "未知错误")")
                self.isWaitingForFileList = false
                self.pendingMountServerID = nil
                return
            }
            
            print("📋 [AppDelegate] 挂载完成: \(event.serverID)，立刻打开文件管理器")
            self.isWaitingForFileList = false
            self.pendingMountServerID = nil
            self.windowManager.openFileBrowserWindow(serverID: event.serverID)
        }
    }
    
    private func handleFileListLoaded(_ event: FileListLoaded) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("📋 [AppDelegate] 文件列表加载完成: \(event.count) 个文件")
            if self.isWaitingForFileList && self.pendingMountServerID == event.serverID {
                self.isWaitingForFileList = false
                self.pendingMountServerID = nil
            }
        }
    }
    
    // MARK: - 挂载/卸载操作
    private func toggleMount(serverID: String) {
        guard let server = ConfigurationManager.shared.getServer(id: serverID) else {
            print("❌ 找不到服务器配置: \(serverID)")
            return
        }
        
        let isMounted = MountManager.shared.getMountedServers().contains(serverID)
        
        if isMounted {
            MountManager.shared.unmount(serverID: serverID, force: false) { result in
                if case .failure(let error) = result {
                    print("❌ 卸载失败: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.showAlert(title: "卸载失败", message: error.localizedDescription)
                    }
                }
            }
        } else {
            MountManager.shared.mount(serverID: serverID, config: server) { result in
                switch result {
                case .success(let path):
                    print("✅ 挂载成功: \(path)")
                case .failure(let error):
                    print("❌ 挂载失败: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.showAlert(title: "挂载失败", message: error.localizedDescription)
                    }
                }
            }
        }
    }
    
    // MARK: - 删除连接
    private func deleteConnection(serverID: String) {
        print("📋 [AppDelegate] 开始删除连接: \(serverID)")
        guard let config = ConfigurationManager.shared.getServer(id: serverID) else {
            print("⚠️ [AppDelegate] 配置不存在: \(serverID)")
            return
        }
        MountManager.shared.deleteConnection(serverID: serverID, config: config) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success:
                    print("✅ [AppDelegate] 删除连接成功: \(serverID)")
                    ConfigurationManager.shared.removeServer(id: serverID)
                    EventBus.shared.publish(LoadServerListRequest())
                case .failure(let error):
                    print("❌ [AppDelegate] 删除连接失败: \(error.localizedDescription)")
                    self.showAlert(title: "删除失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - 提示框
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 滚动条配置
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
}
