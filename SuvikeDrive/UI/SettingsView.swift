//
//  SettingsView.swift
//  SuvikeDrive
//
//  功能: 偏好设置 UI（纯 UI，所有逻辑通过 EventBus 通信）
//

import SwiftUI
import AppKit

// MARK: - View Extension for Cursor
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - 胶囊标签样式
struct CapsuleTabView: View {
    let tabs: [String]
    @Binding var selection: Int
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.indices, id: \.self) { index in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = index
                    }
                }) {
                    Text(tabs[index])
                        .font(.system(size: 13, weight: selection == index ? .semibold : .regular))
                        .foregroundColor(selection == index ? .white : .secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                if selection == index {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "capsule", in: namespace)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - 胶囊完成按钮（带悬停效果）
struct SettingsCapsuleDoneButton: View {
    let action: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text("完成")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isHovering ? Color.accentColor.opacity(0.8) : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 胶囊操作按钮（带悬停效果）
struct SettingsCapsuleActionButton: View {
    let title: String
    let action: () -> Void
    var backgroundColor: Color = Color.gray.opacity(0.15)
    var foregroundColor: Color = .primary
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foregroundColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isHovering ? backgroundColor.opacity(1.2) : backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - SettingsView（纯 UI）
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    
    // 通用设置
    @State private var startAtLogin: Bool = false
    @State private var autoMount: Bool = false
    @State private var showDesktop: Bool = true
    @State private var shortName: Bool = true
    @State private var mountDelay: Int = 3
    @State private var refreshInterval: Int = 60
    
    // 网络设置
    @State private var timeout: Int = 30
    @State private var maxRetries: Int = 3
    
    // 日志设置
    @State private var enableLogging: Bool = true
    @State private var logLevel: String = "信息"
    @State private var analytics: Bool = false
    
    // 加密设置
    @State private var forceEncryptExport: Bool = true
    @State private var exportPassword: String = ""
    @State private var confirmExportPassword: String = ""
    @State private var showingPasswordMismatch = false
    
    // 缓存设置
    @State private var cacheEnabled: Bool = true
    @State private var cacheAutoCleanup: Bool = true
    @State private var cacheMaxDiskSize: String = "500 MB"
    @State private var cacheMaxMemoryEntries: String = "100"
    @State private var cacheTTL: String = "7天"
    @State private var maxCacheSize: String = "10 GB"
    @State private var cachePath: String = ""
    
    // 状态栏流量监控
    @State private var statusBarTrafficMonitor: Bool = true
    
    // 全盘访问权限
    @State private var hasFullDiskAccess: Bool = false
    @State private var isCheckingPermission: Bool = false
    
    // 守护进程状态
    @State private var daemonInstalled: Bool = false
    @State private var daemonRunning: Bool = false
    @State private var daemonEnabled: Bool = true
    
    // EventBus 订阅
    @State private var eventTokens: [SubscriptionToken] = []
    
    // 通知监听
    @State private var notificationObservers: [NSObjectProtocol] = []
    
    // 日志级别列表
    private let logLevels = ["调试", "信息", "警告", "错误", "崩溃"]
    
    // 缓存大小选项
    private let cacheSizeOptions = ["100 MB", "200 MB", "500 MB", "1 GB", "2 GB", "5 GB", "10 GB", "无限制"]
    private let cacheEntryOptions = ["50", "100", "200", "500", "1000"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 + 胶囊标签（同一行）
            HStack {
                Text("偏好设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                CapsuleTabView(
                    tabs: ["通用", "缓存", "高级"],
                    selection: $selectedTab
                )
                
                Spacer()
                
                SettingsCapsuleDoneButton(action: {
                    saveAllSettings()
                    dismiss()
                })
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(height: 52)
            
            Divider()
                .foregroundColor(Color(NSColor.separatorColor))
            
            ScrollView {
                Form {
                    switch selectedTab {
                    case 0:
                        generalTab
                    case 1:
                        cacheTab
                    case 2:
                        advancedTab
                    default:
                        EmptyView()
                    }
                }
                .formStyle(.grouped)
                .padding(.horizontal, 0)
            }
            .scrollIndicators(.never)
            .background(Color(NSColor.controlBackgroundColor))
            .id(selectedTab)
            
            Divider()
                .foregroundColor(Color(NSColor.separatorColor))
            
            if selectedTab == 1 {
                HStack {
                    Text("缓存: \(getCacheSize())  |  可用空间: \(getFreeSpace())")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    SettingsCapsuleActionButton(
                        title: "清除缓存",
                        action: {
                            clearCache()
                        },
                        backgroundColor: Color.red.opacity(0.15),
                        foregroundColor: .red
                    )
                    
                    SettingsCapsuleActionButton(
                        title: "恢复默认",
                        action: {
                            restoreCacheDefaults()
                        }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(height: 48)
                .transition(.opacity)
            }
        }
        .frame(width: 700, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupEventBusListeners()
            loadAllSettings()
            loadCachePath()
            checkFullDiskAccessStatus()
            refreshDaemonStatus()
            
            // 监听应用激活通知，刷新权限状态
            let activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                print("📋 [应用激活] 刷新权限状态")
                checkFullDiskAccessStatus()
            }
            notificationObservers.append(activeObserver)
        }
        .onDisappear {
            notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
            notificationObservers.removeAll()
            
            eventTokens.forEach { $0.unsubscribe() }
            eventTokens.removeAll()
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .alert("密码不匹配", isPresented: $showingPasswordMismatch) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("两次输入的密码不一致，请重新输入")
        }
    }
    
    // MARK: - EventBus 事件监听
    private func setupEventBusListeners() {
        let loadToken = EventBus.shared.subscribe(
            to: SettingsLoaded.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                applySettings(event.settings)
            }
        }
        eventTokens.append(loadToken)
        
        let saveToken = EventBus.shared.subscribe(
            to: SettingsSaved.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                if event.success {
                    Logger.shared.info("偏好设置已保存")
                } else {
                    Logger.shared.error("保存偏好设置失败: \(event.error ?? "未知错误")")
                }
            }
        }
        eventTokens.append(saveToken)
        
        // 监听权限状态更新
        let permissionToken = EventBus.shared.subscribe(
            to: PermissionStatusUpdated.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                if event.permissionType == "full_disk_access" {
                    self.hasFullDiskAccess = event.isGranted
                    self.isCheckingPermission = false
                    print("📋 [权限状态] 全盘访问: \(event.isGranted ? "已授权" : "未授权")")
                }
            }
        }
        eventTokens.append(permissionToken)
        
        // 监听守护进程状态更新
        let daemonToken = EventBus.shared.subscribe(
            to: DaemonStatusUpdated.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                self.daemonInstalled = event.isInstalled
                self.daemonRunning = event.isRunning
                self.daemonEnabled = event.isEnabled
                print("📋 [守护进程状态] 已安装: \(event.isInstalled), 运行中: \(event.isRunning), 已开启: \(event.isEnabled)")
            }
        }
        eventTokens.append(daemonToken)
    }
    
    // MARK: - 加载所有设置
    private func loadAllSettings() {
        EventBus.shared.publish(LoadSettingsRequest())
    }
    
    private func applySettings(_ settings: [String: Any]) {
        startAtLogin = settings["app.startAtLogin"] as? Bool ?? false
        autoMount = settings["app.autoMount"] as? Bool ?? false
        showDesktop = settings["app.showDesktop"] as? Bool ?? true
        shortName = settings["app.shortName"] as? Bool ?? true
        mountDelay = settings["app.delayMount"] as? Int ?? 3
        refreshInterval = settings["app.refreshInterval"] as? Int ?? 60
        
        timeout = settings["network.timeout"] as? Int ?? 30
        maxRetries = settings["network.maxRetries"] as? Int ?? 3
        
        enableLogging = settings["log.enabled"] as? Bool ?? true
        logLevel = settings["log.level"] as? String ?? "信息"
        analytics = settings["analytics.enabled"] as? Bool ?? false
        
        forceEncryptExport = settings["export.forceEncrypt"] as? Bool ?? true
        exportPassword = settings["export.password"] as? String ?? ""
        confirmExportPassword = exportPassword
        
        cacheEnabled = settings["cache.enabled"] as? Bool ?? true
        cacheAutoCleanup = settings["cache.autoCleanup"] as? Bool ?? true
        cacheMaxDiskSize = settings["cache.maxDiskSize"] as? String ?? "500 MB"
        cacheMaxMemoryEntries = settings["cache.maxMemoryEntries"] as? String ?? "100"
        cacheTTL = settings["cache.ttl"] as? String ?? "7天"
        maxCacheSize = settings["cache.maxSize"] as? String ?? "10 GB"
        
        statusBarTrafficMonitor = settings["app.statusBarTrafficMonitor"] as? Bool ?? true
        daemonEnabled = settings["app.daemon.enabled"] as? Bool ?? true
    }
    
    // MARK: - 保存所有设置
    private func saveAllSettings() {
        let settings: [String: Any] = [
            "app.startAtLogin": startAtLogin,
            "app.autoMount": autoMount,
            "app.showDesktop": showDesktop,
            "app.shortName": shortName,
            "app.delayMount": mountDelay,
            "app.refreshInterval": refreshInterval,
            "network.timeout": timeout,
            "network.maxRetries": maxRetries,
            "log.enabled": enableLogging,
            "log.level": logLevel,
            "analytics.enabled": analytics,
            "export.forceEncrypt": forceEncryptExport,
            "export.password": exportPassword,
            "cache.enabled": cacheEnabled,
            "cache.autoCleanup": cacheAutoCleanup,
            "cache.maxDiskSize": cacheMaxDiskSize,
            "cache.maxMemoryEntries": Int(cacheMaxMemoryEntries) ?? 100,
            "cache.ttl": cacheTTL,
            "cache.maxSize": maxCacheSize,
            "app.statusBarTrafficMonitor": statusBarTrafficMonitor,
            "app.daemon.enabled": daemonEnabled
        ]
        
        EventBus.shared.publish(SaveSettingsRequest(settings: settings))
        applyLogLevel()
    }
    
    // MARK: - 刷新守护进程状态
    private func refreshDaemonStatus() {
        DispatchQueue.global(qos: .utility).async {
            let installed = WatchdogProcessManager.shared.isWatchdogActive()
            let running = WatchdogProcessManager.shared.isWatchdogActive()
            let enabled = ConfigurationManager.shared.get(key: "app.daemon.enabled", defaultValue: true)
            
            DispatchQueue.main.async {
                self.daemonInstalled = installed
                self.daemonRunning = running
                self.daemonEnabled = enabled
                EventBus.shared.publish(DaemonStatusUpdated(
                    isInstalled: installed,
                    isRunning: running,
                    isEnabled: enabled
                ))
            }
        }
    }
    
    // MARK: - 应用日志级别
    private func applyLogLevel() {
        if !enableLogging {
            Logger.shared.setLogLevel(.off)
            return
        }
        
        let levelMap: [String: LogLevel] = [
            "调试": .debug,
            "信息": .info,
            "警告": .warning,
            "错误": .error,
            "崩溃": .crash
        ]
        
        if let level = levelMap[logLevel] {
            Logger.shared.setLogLevel(level)
        }
    }
    
    // MARK: - 缓存
    private func getCacheSize() -> String {
        return CacheManager.shared.getCacheSizeFormatted()
    }
    
    private func clearCache() {
        CacheManager.shared.clearAllCaches()
        NotificationCenter.default.post(name: .ConfigurationChanged, object: nil)
        Logger.shared.info("缓存已清除")
    }
    
    private func restoreCacheDefaults() {
        cacheMaxDiskSize = "500 MB"
        cacheMaxMemoryEntries = "100"
        cacheEnabled = true
        cacheAutoCleanup = true
        cacheTTL = "7天"
        maxCacheSize = "10 GB"
        saveAllSettings()
        Logger.shared.info("缓存设置已恢复默认")
    }
    
    // MARK: - 可用空间
    private func getFreeSpace() -> String {
        let path = "/"
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: path)
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return formatBytes(freeSize.uint64Value)
            }
        } catch {
            return "0 KB"
        }
        return "0 KB"
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - 缓存路径
    private func loadCachePath() {
        let customPath = ConfigurationManager.shared.get(key: "cache.customPath", defaultValue: "")
        if !customPath.isEmpty {
            cachePath = customPath
            return
        }
        
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        cachePath = appSupport.appendingPathComponent("com.suvikedrive.drive/Cache").path
    }
    
    private func selectCacheDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择缓存目录"
        panel.message = "请选择用于存储缓存的文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.level = .floating
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        let currentURL = URL(fileURLWithPath: cachePath)
        if FileManager.default.fileExists(atPath: currentURL.path) {
            panel.directoryURL = currentURL.deletingLastPathComponent()
        } else {
            panel.directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                updateCachePath(to: url)
            }
        }
    }
    
    private func updateCachePath(to url: URL) {
        let newPath: String
        if url.path.hasSuffix("/Cache") {
            newPath = url.path
        } else {
            newPath = url.appendingPathComponent("Cache").path
        }
        
        do {
            try FileManager.default.createDirectory(atPath: newPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "创建缓存目录失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        cachePath = newPath
        ConfigurationManager.shared.set(key: "cache.customPath", value: newPath)
        NotificationCenter.default.post(name: .ConfigurationChanged, object: nil)
        Logger.shared.info("缓存路径已更新: \(newPath)")
    }
    
    // MARK: - 密码
    private func savePassword() {
        if exportPassword != confirmExportPassword {
            showingPasswordMismatch = true
            return
        }
        
        if exportPassword.isEmpty {
            let alert = NSAlert()
            alert.messageText = "密码不能为空"
            alert.informativeText = "请设置一个导出密码"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        _ = ConfigCrypto.savePassword(exportPassword, forKey: "export.password")
        ConfigurationManager.shared.set(key: "export.forceEncrypt", value: forceEncryptExport)
        
        let alert = NSAlert()
        alert.messageText = "密码已更新"
        alert.informativeText = "导出配置将使用新密码加密"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
        
        Logger.shared.info("导出密码已更新")
    }
    
    // MARK: - 全盘访问权限
    private func checkFullDiskAccessStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = PermissionManager.shared.checkFullDiskAccess()
            let isGranted: Bool
            switch status {
            case .granted:
                isGranted = true
            case .denied, .notDetermined, .restricted:
                isGranted = false
            }
            DispatchQueue.main.async {
                self.hasFullDiskAccess = isGranted
                self.isCheckingPermission = false
                EventBus.shared.publish(PermissionStatusUpdated(
                    permissionType: "full_disk_access",
                    isGranted: isGranted
                ))
                print("📋 [权限状态] 全盘访问: \(isGranted ? "已授权 ✅" : "未授权 ❌")")
            }
        }
    }
    
    private func requestFullDiskAccess() {
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        
        let status = PermissionManager.shared.checkFullDiskAccess()
        let isGranted: Bool
        switch status {
        case .granted:
            isGranted = true
        case .denied, .notDetermined, .restricted:
            isGranted = false
        }
        
        if isGranted {
            DispatchQueue.main.async {
                self.hasFullDiskAccess = true
                self.isCheckingPermission = false
                EventBus.shared.publish(PermissionStatusUpdated(
                    permissionType: "full_disk_access",
                    isGranted: true
                ))
            }
            return
        }
        
        DispatchQueue.main.async {
            PermissionManager.shared.showFullDiskAccessGuide { granted in
                DispatchQueue.main.async {
                    self.checkFullDiskAccessStatus()
                }
            }
        }
    }
    
    private func showFullDiskAccessGuide() {
        let alert = NSAlert()
        alert.messageText = "全盘访问权限"
        alert.informativeText = """
        如需关闭全盘访问权限，请按以下步骤操作：
        
        1. 点击「打开设置」按钮
        2. 在「隐私与安全性」→「全盘访问」中
        3. 找到 \(AppInfo.appName)
        4. 取消勾选即可关闭权限
        
        注意：关闭权限后，应用将无法挂载远程磁盘。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "确定")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - 通用标签页
    @ViewBuilder
    var generalTab: some View {
        Section {
            Toggle("系统登录时打开 SuvikeDrive", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, newValue in
                    PermissionManager.shared.toggleStartAtLogin(enabled: newValue)
                }
            Toggle("应用启动时自动挂载所有连接", isOn: $autoMount)
            Toggle("在桌面显示已挂载的驱动器", isOn: $showDesktop)
            Toggle("在\"访达\"侧边栏中使用短设备名称", isOn: $shortName)
        }
        
        Section {
            HStack {
                Text("延时挂载")
                    .font(.body)
                Spacer()
                Picker("", selection: $mountDelay) {
                    Text("1 秒").tag(1)
                    Text("2 秒").tag(2)
                    Text("3 秒").tag(3)
                    Text("5 秒").tag(5)
                    Text("10 秒").tag(10)
                    Text("15 秒").tag(15)
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .disabled(!autoMount)
                .opacity(autoMount ? 1 : 0.5)
            }
            
            HStack {
                Text("刷新间隔")
                    .font(.body)
                Spacer()
                Picker("", selection: $refreshInterval) {
                    Text("不刷新").tag(0)
                    Text("1 分钟").tag(60)
                    Text("5 分钟").tag(300)
                    Text("10 分钟").tag(600)
                    Text("30 分钟").tag(1800)
                    Text("60 分钟").tag(3600)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
        }
        
        Section("数据管理") {
            HStack {
                Text("导出加密")
                    .font(.body)
                Spacer()
                Toggle("", isOn: $forceEncryptExport)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            HStack(spacing: 8) {
                Text("设置密码")
                    .font(.body)
                    .frame(width: 70, alignment: .leading)
                
                SecureField("", text: $exportPassword)
                    .textFieldStyle(.plain)
            }
            
            HStack(spacing: 8) {
                Text("确认密码")
                    .font(.body)
                    .frame(width: 70, alignment: .leading)
                
                SecureField("", text: $confirmExportPassword)
                    .textFieldStyle(.plain)
            }
            
            HStack {
                Text("导出配置时将使用此密码加密，导入时需要输入相同密码解密")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                SettingsCapsuleActionButton(
                    title: "保存",
                    action: {
                        savePassword()
                    },
                    backgroundColor: (exportPassword.isEmpty || confirmExportPassword.isEmpty) ? Color.gray.opacity(0.3) : Color.accentColor,
                    foregroundColor: (exportPassword.isEmpty || confirmExportPassword.isEmpty) ? .gray : .white
                )
                .disabled(exportPassword.isEmpty || confirmExportPassword.isEmpty)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 缓存标签页
    @ViewBuilder
    var cacheTab: some View {
        Section("缓存管理") {
            HStack {
                Text("启用缓存")
                    .font(.body)
                Spacer()
                Toggle("", isOn: $cacheEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: cacheEnabled) { _, newValue in
                        ConfigurationManager.shared.set(key: "cache.enabled", value: newValue)
                    }
            }
            
            HStack {
                Text("自动清理")
                    .font(.body)
                Spacer()
                Toggle("", isOn: $cacheAutoCleanup)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: cacheAutoCleanup) { _, newValue in
                        ConfigurationManager.shared.set(key: "cache.autoCleanup", value: newValue)
                        if newValue {
                            CacheManager.shared.refreshConfig()
                        }
                    }
            }
        }
        
        Section("缓存位置") {
            HStack {
                Text(cachePath)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                SettingsCapsuleActionButton(
                    title: "更改...",
                    action: {
                        selectCacheDirectory()
                    }
                )
            }
        }
        
        Section("缓存大小限制") {
            HStack {
                Text("磁盘缓存上限")
                    .font(.body)
                Spacer()
                Picker("", selection: $cacheMaxDiskSize) {
                    ForEach(cacheSizeOptions, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
            HStack {
                Text("内存缓存条目")
                    .font(.body)
                Spacer()
                Picker("", selection: $cacheMaxMemoryEntries) {
                    ForEach(cacheEntryOptions, id: \.self) { count in
                        Text(count).tag(count)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
        }
        
        Section("缓存统计") {
            HStack {
                Text("当前缓存大小")
                    .font(.body)
                Spacer()
                Text(getCacheSize())
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("内存缓存条目")
                    .font(.body)
                Spacer()
                Text("\(CacheManager.shared.getMemoryCacheSize())")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("磁盘缓存大小")
                    .font(.body)
                Spacer()
                Text(getCacheSize())
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("可用磁盘空间")
                    .font(.body)
                Spacer()
                Text(getFreeSpace())
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - 高级标签页
    @ViewBuilder
    var advancedTab: some View {
        Section {
            // 守护进程
            HStack {
                Text("守护进程")
                    .font(.body)
                Spacer()
                Text(daemonEnabled ? "已开启" : "已关闭")
                    .font(.caption)
                    .foregroundColor(daemonEnabled ? .green : .gray)
                Toggle("", isOn: Binding(
                    get: { daemonEnabled },
                    set: { newValue in
                        daemonEnabled = newValue
                        ConfigurationManager.shared.set(key: "app.daemon.enabled", value: newValue)
                        if newValue {
                            WatchdogProcessManager.shared.startWatchdog()
                        } else {
                            WatchdogProcessManager.shared.stopWatchdog()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .frame(height: 32)
            
            // 全盘访问权限
            HStack {
                Text("全盘访问权限")
                    .font(.body)
                Spacer()
                Text(hasFullDiskAccess ? "已授权" : "未授权")
                    .font(.caption)
                    .foregroundColor(hasFullDiskAccess ? .green : .orange)
                Toggle("", isOn: Binding(
                    get: { hasFullDiskAccess },
                    set: { newValue in
                        if newValue {
                            if !hasFullDiskAccess {
                                requestFullDiskAccess()
                            }
                        } else {
                            if hasFullDiskAccess {
                                showFullDiskAccessGuide()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .frame(height: 32)
            .onAppear {
                checkFullDiskAccessStatus()
            }
        }
        
        // 状态栏流量监控
        Section {
            HStack {
                Text("状态栏流量监控")
                    .font(.body)
                Spacer()
                Text(statusBarTrafficMonitor ? "已开启" : "已关闭")
                    .font(.caption)
                    .foregroundColor(statusBarTrafficMonitor ? .green : .gray)
                Toggle("", isOn: $statusBarTrafficMonitor)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: statusBarTrafficMonitor) { _, newValue in
                        if newValue {
                            NetworkManager.shared.startInterfaceMonitoring()
                            Logger.shared.info("状态栏流量监控已开启")
                        } else {
                            NetworkManager.shared.stopInterfaceMonitoring()
                            Logger.shared.info("状态栏流量监控已关闭")
                        }
                    }
            }
            .frame(height: 32)
        }
        
        Section {
            HStack {
                Text("请求超时 (秒)")
                    .font(.body)
                Spacer()
                Picker("", selection: $timeout) {
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("15").tag(15)
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("120").tag(120)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .frame(height: 32)
            
            HStack {
                Text("最大重试次数")
                    .font(.body)
                Spacer()
                Picker("", selection: $maxRetries) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("5").tag(5)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .frame(height: 32)
        }
        
        Section {
            Toggle("启用日志记录", isOn: $enableLogging)
                .onChange(of: enableLogging) { _, newValue in
                    if !newValue {
                        Logger.shared.setLogLevel(.off)
                    } else {
                        applyLogLevel()
                    }
                }
            
            HStack {
                Text("日志级别")
                    .font(.body)
                Spacer()
                Picker("", selection: $logLevel) {
                    ForEach(logLevels, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .disabled(!enableLogging)
                .opacity(enableLogging ? 1 : 0.5)
                .onChange(of: logLevel) { _, _ in
                    if enableLogging {
                        applyLogLevel()
                    }
                }
            }
            .frame(height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("调试 → 最详细  |  信息 → 常规  |  警告 → 潜在问题  |  错误 → 功能异常  |  崩溃 → 严重崩溃")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.top, 2)
            
            Toggle("发送匿名统计信息", isOn: $analytics)
        }
    }
}

#Preview {
    SettingsView()
}
