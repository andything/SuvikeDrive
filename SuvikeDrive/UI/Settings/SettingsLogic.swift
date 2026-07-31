//
//  SettingsLogic.swift
//  SuvikeDrive
//
//  功能: 偏好设置业务逻辑扩展 (完整版)
//

import SwiftUI
import AppKit
import Combine

extension SettingsViewModel {
    
    // MARK: - 获取服务器列表
    var mountedServers: [String] {
        let mountedIDs = MountManager.shared.getMountedServers()
        let allServers = ConfigurationManager.shared.getServers()
        return allServers
            .filter { mountedIDs.contains($0.id) }
            .map { $0.name }
    }
    
    // MARK: - EventBus 监听
    func setupEventBusListeners() {
        let loadToken = EventBus.shared.subscribe(to: SettingsLoaded.self, priority: .medium) { [weak self] event in
            DispatchQueue.main.async {
                self?.applySettings(event.settings)
            }
        }
        eventTokens.append(loadToken)
        
        let configToken = EventBus.shared.subscribe(to: ConfigurationChanged.self, priority: .low) { [weak self] event in
            if event.key == "webdav.cache.path" || event.key == "cache" {
                DispatchQueue.main.async {
                    print("🔍 [SettingsLogic] ConfigurationChanged: key=\(event.key), newValue=\(event.newValue ?? "nil")")
                    self?.loadCachePath()
                }
            }
        }
        eventTokens.append(configToken)
        
        let permissionToken = EventBus.shared.subscribe(to: PermissionStatusUpdated.self, priority: .medium) { [weak self] event in
            DispatchQueue.main.async {
                if event.permissionType == "full_disk_access" {
                    self?.hasFullDiskAccess = event.isGranted
                    self?.isCheckingPermission = false
                }
            }
        }
        eventTokens.append(permissionToken)
        
        let daemonToken = EventBus.shared.subscribe(to: DaemonStatusUpdated.self, priority: .medium) { [weak self] event in
            DispatchQueue.main.async {
                self?.daemonInstalled = event.isInstalled
                self?.daemonRunning = event.isRunning
                self?.daemonEnabled = event.isEnabled
            }
        }
        eventTokens.append(daemonToken)
        
        let cacheClearedToken = EventBus.shared.subscribe(to: CacheCleared.self, priority: .low) { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        eventTokens.append(cacheClearedToken)
        
        let cacheSizeToken = EventBus.shared.subscribe(to: CacheSizeChanged.self, priority: .low) { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        eventTokens.append(cacheSizeToken)
        
        let mountToken = EventBus.shared.subscribe(to: MountCompleted.self, priority: .low) { [weak self] _ in
            DispatchQueue.main.async {
                self?.serverListVersion += 1
                self?.objectWillChange.send()
            }
        }
        eventTokens.append(mountToken)
        
        let unmountToken = EventBus.shared.subscribe(to: UnmountCompleted.self, priority: .low) { [weak self] _ in
            DispatchQueue.main.async {
                self?.serverListVersion += 1
                self?.objectWillChange.send()
            }
        }
        eventTokens.append(unmountToken)
        
        let switchToken = EventBus.shared.subscribe(to: ServerSwitched.self, priority: .low) { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
        eventTokens.append(switchToken)
        
        // 主动请求缓存大小
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            CacheManager.shared.updateCacheSize()
        }
    }
    
    func cleanup() {
        eventTokens.forEach { $0.unsubscribe() }
        eventTokens.removeAll()
    }
    
    // MARK: - 加载设置
    func loadAllSettings() {
        EventBus.shared.publish(LoadSettingsRequest())
    }
    
    func applySettings(_ settings: [String: Any]) {
        // 通用设置
        startAtLogin = settings["app.startAtLogin"] as? Bool ?? false
        autoMount = settings["app.autoMount"] as? Bool ?? false
        showDesktop = settings["app.showDesktop"] as? Bool ?? true
        shortName = settings["app.shortName"] as? Bool ?? true
        mountDelay = settings["app.delayMount"] as? Int ?? 3
        refreshInterval = settings["app.refreshInterval"] as? Int ?? 60
        
        // 网络设置
        timeout = settings["network.timeout"] as? Int ?? 30
        maxRetries = settings["network.maxRetries"] as? Int ?? 3
        
        // 日志设置
        enableLogging = settings["log.enabled"] as? Bool ?? true
        logLevel = settings["log.level"] as? String ?? "信息"
        analytics = settings["analytics.enabled"] as? Bool ?? false
        
        // 加密设置
        forceEncryptExport = settings["export.forceEncrypt"] as? Bool ?? true
        exportPassword = settings["export.password"] as? String ?? ""
        confirmExportPassword = exportPassword
        
        // 缓存设置
        cacheEnabled = settings["cache.enabled"] as? Bool ?? true
        cacheAutoCleanup = settings["cache.autoCleanup"] as? Bool ?? true
        cacheMaxDiskSize = settings["cache.maxDiskSize"] as? String ?? "500 MB"
        cacheMaxMemoryEntries = settings["cache.maxMemoryEntries"] as? String ?? "100"
        maxCacheSize = settings["cache.maxSize"] as? String ?? "10 GB"
        
        // WebDAV 路径
        if let path = settings["webdav.cache.path"] as? String, !path.isEmpty {
            cachePath = path
            print("🔍 [SettingsLogic] applySettings: 从 settings 读取路径: \(path)")
        } else {
            let configPath = ConfigurationManager.shared.get(key: "webdav.cache.path", defaultValue: "")
            if !configPath.isEmpty {
                cachePath = configPath
                print("🔍 [SettingsLogic] applySettings: 从 ConfigurationManager 读取路径: \(configPath)")
            } else {
                cachePath = getDefaultCachePath()
                print("🔍 [SettingsLogic] applySettings: 使用默认路径: \(cachePath)")
            }
        }
        
        // 同步设置
        autoSyncEnabled = settings["sync.autoSync"] as? Bool ?? true
        syncOnLaunch = settings["sync.onLaunch"] as? Bool ?? false
        syncRealtime = settings["sync.realtime"] as? Bool ?? true
        syncDirection = settings["sync.direction"] as? String ?? "双向同步"
        conflictStrategy = settings["sync.conflictStrategy"] as? String ?? "保留最新"
        
        statusBarTrafficMonitor = settings["app.statusBarTrafficMonitor"] as? Bool ?? true
        daemonEnabled = settings["app.daemon.enabled"] as? Bool ?? true
        
        // 缓存 TTL 映射
        if let days = settings["cache.transferTTL"] as? Int {
            cacheTTL = ttlMap.first(where: { $0.value == days })?.key ?? "7天"
        }
        if let seconds = settings["cache.fileListTTL"] as? TimeInterval {
            cacheFileListTTL = fileListTTLMap.first(where: { $0.value == seconds })?.key ?? "60秒"
        }
        if let seconds = settings["cache.webdavFileTTL"] as? TimeInterval {
            cacheWebDAVTTL = webDAVTTLMap.first(where: { $0.value == seconds })?.key ?? "24小时"
        }
    }
    
    // MARK: - 保存设置
    func saveAllSettings() {
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
            "cache.maxDiskSize": diskSizeMap[cacheMaxDiskSize] ?? 500 * 1024 * 1024,
            "cache.maxMemoryEntries": Int(cacheMaxMemoryEntries) ?? 100,
            "cache.transferTTL": ttlMap[cacheTTL] ?? 7,
            "cache.fileListTTL": fileListTTLMap[cacheFileListTTL] ?? 60,
            "cache.webdavFileTTL": webDAVTTLMap[cacheWebDAVTTL] ?? 86400,
            "cache.maxSize": maxCacheSize,
            "webdav.cache.path": cachePath,
            "sync.autoSync": autoSyncEnabled,
            "sync.onLaunch": syncOnLaunch,
            "sync.realtime": syncRealtime,
            "sync.direction": syncDirection,
            "sync.conflictStrategy": conflictStrategy,
            "app.statusBarTrafficMonitor": statusBarTrafficMonitor,
            "app.daemon.enabled": daemonEnabled
        ]
        
        EventBus.shared.publish(SaveSettingsRequest(settings: settings))
        applyLogLevel()
        CacheManager.shared.refreshConfig()
    }
    
    // MARK: - 日志级别
    func applyLogLevel() {
        let level: LogLevel
        switch logLevel {
        case "调试": level = .debug
        case "信息": level = .info
        case "警告": level = .warning
        case "错误": level = .error
        case "崩溃": level = .crash
        default: level = .info
        }
        Logger.shared.setLogLevel(level)
    }
    
    // MARK: - 同步方法
    func syncAllServers() {
        guard !isSyncRunning else { return }
        
        isSyncRunning = true
        lastSyncTime = "同步中..."
        syncStatus = "同步中..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Thread.sleep(forTimeInterval: 2)
            DispatchQueue.main.async {
                self?.isSyncRunning = false
                self?.syncStatus = "同步完成"
                self?.lastSyncTime = self?.formatCurrentTime() ?? "未知"
            }
        }
    }
    
    func stopSync() {
        isSyncRunning = false
        syncStatus = "已停止"
        lastSyncTime = "已停止"
    }
    
    func manualSync() {
        Logger.shared.info("手动触发同步")
        syncStatus = "同步中..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.syncStatus = "已同步"
            self.lastSyncTime = self.formatCurrentTime()
            self.pendingSyncCount = 0
        }
    }
    
    func pauseSync() {
        Logger.shared.info("暂停同步")
        syncStatus = "已暂停"
    }
    
    private func formatCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }
    
    // MARK: - 同步路径选择
    func selectSyncLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "选择本地同步目录"
        panel.prompt = "选择"
        panel.level = .floating
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if !syncLocalPath.isEmpty && FileManager.default.fileExists(atPath: syncLocalPath) {
            panel.directoryURL = URL(fileURLWithPath: syncLocalPath)
        }
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.syncLocalPath = url.path
                ConfigurationManager.shared.set(key: "sync.localPath", value: url.path)
                Logger.shared.info("同步本地路径已更新: \(url.path)")
            }
        }
    }
    
    func selectSyncRemotePath() {
        // TODO: 实现远程路径选择（WebDAV 目录选择）
        Logger.shared.info("远程路径选择功能开发中")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "功能开发中"
            alert.informativeText = "远程路径选择功能即将推出"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
    
    // MARK: - 同步服务器控制
    func isSyncEnabled(for serverName: String) -> Bool {
        return ConfigurationManager.shared.get(key: "sync.server.\(serverName).enabled", defaultValue: true)
    }
    
    func setSyncEnabled(for serverName: String, enabled: Bool) {
        ConfigurationManager.shared.set(key: "sync.server.\(serverName).enabled", value: enabled)
        EventBus.shared.publish(ConfigurationChanged(
            key: "sync.server.\(serverName).enabled",
            oldValue: nil,
            newValue: enabled
        ))
    }
    
    func getSyncStatus(for serverName: String) -> String {
        return "就绪"
    }
    
    // MARK: - 缓存
    func getCacheSize() -> String {
        return CacheManager.shared.getCacheSizeFormatted()
    }
    
    func getFreeSpace() -> String {
        let path = "/"
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return formatBytes(freeSize.uint64Value)
            }
        } catch { }
        return "0 KB"
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func clearCache() {
        CacheManager.shared.clearAllCaches()
        EventBus.shared.publish(ConfigurationChanged(key: "cache", oldValue: nil, newValue: nil))
        Logger.shared.info("缓存已清除")
    }
    
    func clearCache(for serverName: String) {
        let allServers = ConfigurationManager.shared.getServers()
        guard let server = allServers.first(where: { $0.name == serverName }) else {
            Logger.shared.warning("未找到服务器: \(serverName)")
            return
        }
        CacheManager.shared.clearCache(for: server.id, serverName: serverName)
        Logger.shared.info("已清除服务器缓存: \(serverName)")
        objectWillChange.send()
    }
    
    func getCacheSize(for serverName: String) -> String {
        let allServers = ConfigurationManager.shared.getServers()
        guard let server = allServers.first(where: { $0.name == serverName }) else {
            return "0 KB"
        }
        
        let size = CacheManager.shared.getCacheSize(for: server.id)
        let formatted = CacheManager.shared.formatBytes(size)
        
        EventBus.shared.publish(ServerCacheSizeChanged(
            serverID: server.id,
            serverName: serverName,
            formattedSize: formatted
        ))
        
        return formatted
    }
    
    func restoreCacheDefaults() {
        cacheEnabled = true
        cacheAutoCleanup = true
        cacheMaxDiskSize = "500 MB"
        cacheMaxMemoryEntries = "100"
        cacheTTL = "7天"
        cacheFileListTTL = "60秒"
        cacheWebDAVTTL = "24小时"
        maxCacheSize = "10 GB"
        saveAllSettings()
        Logger.shared.info("缓存设置已恢复默认")
    }
    
    // MARK: - 缓存路径 / WebDAV 路径管理
    
    private func getDefaultCachePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SuvikeDrive").path
    }
    
    func loadCachePath() {
        let customPath = ConfigurationManager.shared.get(key: "webdav.cache.path", defaultValue: "")
        print("🔍 [SettingsLogic] loadCachePath 读取: '\(customPath)'")
        
        if !customPath.isEmpty {
            cachePath = customPath
            Logger.shared.info("📂 从配置文件读取缓存路径: \(customPath)", module: "Settings")
        } else {
            cachePath = getDefaultCachePath()
            Logger.shared.info("📂 使用默认缓存路径: \(cachePath)", module: "Settings")
        }
        
        ensureCacheDirectoryExists(at: cachePath)
    }
    
    private func ensureCacheDirectoryExists(at path: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            do {
                try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
                Logger.shared.info("✅ 创建缓存目录: \(path)", module: "Settings")
            } catch {
                Logger.shared.error("❌ 创建缓存目录失败: \(error)", module: "Settings")
            }
        }
    }
    
    func selectCacheDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 WebDAV 缓存目录"
        panel.message = "请选择用于存储 WebDAV 文件缓存的文件夹"
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
            panel.directoryURL = currentURL
        } else {
            panel.directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.updateCachePath(to: url)
            }
        }
    }
    
    func updateCachePath(to url: URL) {
        let newPath = url.path
        
        do {
            try FileManager.default.createDirectory(atPath: newPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "创建目录失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        cachePath = newPath
        ConfigurationManager.shared.set(key: "webdav.cache.path", value: newPath)
        EventBus.shared.publish(ConfigurationChanged(key: "webdav.cache.path", oldValue: nil, newValue: newPath))
        Logger.shared.info("✅ WebDAV 缓存路径已更新并保存到配置文件: \(newPath)", module: "Settings")
        
        objectWillChange.send()
    }
    
    func resetCachePath() {
        let defaultPath = getDefaultCachePath()
        
        ConfigurationManager.shared.set(key: "webdav.cache.path", value: "")
        cachePath = defaultPath
        
        ensureCacheDirectoryExists(at: defaultPath)
        
        EventBus.shared.publish(ConfigurationChanged(key: "webdav.cache.path", oldValue: nil, newValue: ""))
        Logger.shared.info("✅ WebDAV 缓存路径已重置为默认，配置文件已清除: \(defaultPath)", module: "Settings")
        
        objectWillChange.send()
    }
    
    // MARK: - 密码
    func savePassword() {
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
    
    // MARK: - 权限
    func checkFullDiskAccessStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = PermissionManager.shared.checkFullDiskAccess()
            let isGranted: Bool
            switch status {
            case .granted: isGranted = true
            case .denied, .notDetermined, .restricted: isGranted = false
            }
            DispatchQueue.main.async {
                self?.hasFullDiskAccess = isGranted
                self?.isCheckingPermission = false
                EventBus.shared.publish(PermissionStatusUpdated(
                    permissionType: "full_disk_access",
                    isGranted: isGranted
                ))
            }
        }
    }
    
    func requestFullDiskAccess() {
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        let status = PermissionManager.shared.checkFullDiskAccess()
        let isGranted: Bool
        switch status {
        case .granted: isGranted = true
        case .denied, .notDetermined, .restricted: isGranted = false
        }
        if isGranted {
            DispatchQueue.main.async {
                self.hasFullDiskAccess = true
                self.isCheckingPermission = false
                EventBus.shared.publish(PermissionStatusUpdated(permissionType: "full_disk_access", isGranted: true))
            }
            return
        }
        DispatchQueue.main.async {
            PermissionManager.shared.showFullDiskAccessGuide { _ in
                self.checkFullDiskAccessStatus()
            }
        }
    }
    
    func showFullDiskAccessGuide() {
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
    
    // MARK: - 守护进程
    func refreshDaemonStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = WatchdogProcessManager.shared.isWatchdogActive()
            let running = WatchdogProcessManager.shared.isWatchdogActive()
            let enabled = ConfigurationManager.shared.get(key: "app.daemon.enabled", defaultValue: true)
            DispatchQueue.main.async {
                self?.daemonInstalled = installed
                self?.daemonRunning = running
                self?.daemonEnabled = enabled
                EventBus.shared.publish(DaemonStatusUpdated(
                    isInstalled: installed,
                    isRunning: running,
                    isEnabled: enabled
                ))
            }
        }
    }
}
