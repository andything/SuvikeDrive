//
//  SettingsManager.swift
//  SuvikeDrive
//
//  功能: 设置业务逻辑管理（纯逻辑，无 UI）
//        通过 EventBus 与 UI 通信
//

import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    
    private let configManager = ConfigurationManager.shared
    private var subscriptionTokens: [SubscriptionToken] = []
    
    private init() {
        setupEventListeners()
    }
    
    // MARK: - 设置事件监听
    private func setupEventListeners() {
        // 监听加载设置请求
        let loadToken = EventBus.shared.subscribe(
            to: LoadSettingsRequest.self,
            priority: .high
        ) { [weak self] _ in
            self?.handleLoadSettings()
        }
        subscriptionTokens.append(loadToken)
        
        // 监听保存设置请求
        let saveToken = EventBus.shared.subscribe(
            to: SaveSettingsRequest.self,
            priority: .high
        ) { [weak self] event in
            self?.handleSaveSettings(event)
        }
        subscriptionTokens.append(saveToken)
        
        // ✅ 添加：监听 SettingsSaved 事件（避免死信队列）
        let savedToken = EventBus.shared.subscribe(
            to: SettingsSaved.self,
            priority: .low
        ) { event in
            if event.success {
                Logger.shared.debug("设置保存成功")
            } else {
                Logger.shared.warning("设置保存失败: \(event.error ?? "未知错误")")
            }
        }
        subscriptionTokens.append(savedToken)
    }
    
    // MARK: - 处理加载设置
    private func handleLoadSettings() {
        DispatchQueue.global(qos: .userInitiated).async {
            var settings: [String: Any] = [:]
            
            // 通用设置
            settings["app.startAtLogin"] = self.configManager.get(key: "app.startAtLogin", defaultValue: false)
            settings["app.autoMount"] = self.configManager.get(key: "app.autoMount", defaultValue: false)
            settings["app.showDesktop"] = self.configManager.get(key: "app.showDesktop", defaultValue: true)
            settings["app.shortName"] = self.configManager.get(key: "app.shortName", defaultValue: true)
            settings["app.delayMount"] = self.configManager.get(key: "app.delayMount", defaultValue: 3)
            settings["app.refreshInterval"] = self.configManager.get(key: "app.refreshInterval", defaultValue: 60)
            
            // 网络设置
            settings["network.timeout"] = self.configManager.get(key: "network.timeout", defaultValue: 30)
            settings["network.maxRetries"] = self.configManager.get(key: "network.maxRetries", defaultValue: 3)
            
            // 日志设置
            settings["log.enabled"] = self.configManager.get(key: "log.enabled", defaultValue: true)
            settings["log.level"] = self.configManager.get(key: "log.level", defaultValue: "信息")
            settings["analytics.enabled"] = self.configManager.get(key: "analytics.enabled", defaultValue: false)
            
            // 加密设置
            settings["export.forceEncrypt"] = self.configManager.get(key: "export.forceEncrypt", defaultValue: true)
            settings["export.password"] = ConfigCrypto.getPassword(forKey: "export.password") ?? ""
            
            // 缓存设置
            settings["cache.enabled"] = self.configManager.get(key: "cache.enabled", defaultValue: true)
            settings["cache.autoCleanup"] = self.configManager.get(key: "cache.autoCleanup", defaultValue: true)
            settings["cache.maxDiskSize"] = self.configManager.get(key: "cache.maxDiskSize", defaultValue: "500 MB")
            settings["cache.maxMemoryEntries"] = self.configManager.get(key: "cache.maxMemoryEntries", defaultValue: "100")
            settings["cache.ttl"] = self.configManager.get(key: "cache.ttl", defaultValue: "7天")
            settings["cache.maxSize"] = self.configManager.get(key: "cache.maxSize", defaultValue: "10 GB")
            
            // 状态栏流量监控
            settings["app.statusBarTrafficMonitor"] = self.configManager.get(key: "app.statusBarTrafficMonitor", defaultValue: true)
            
            DispatchQueue.main.async {
                EventBus.shared.publish(
                    SettingsLoaded(settings: settings)
                )
            }
        }
    }
    
    // MARK: - 处理保存设置
    private func handleSaveSettings(_ event: SaveSettingsRequest) {
        DispatchQueue.global(qos: .userInitiated).async {
            let settings = event.settings
            let success = true
            let error: String? = nil
            
            // 保存各项设置
            for (key, value) in settings {
                // 密码特殊处理（存到 Keychain）
                if key == "export.password" {
                    if let password = value as? String, !password.isEmpty {
                        _ = ConfigCrypto.savePassword(password, forKey: "export.password")
                    } else {
                        ConfigCrypto.deletePassword(forKey: "export.password")
                    }
                    continue
                }
                
                self.configManager.set(key: key, value: value)
            }
            
            // 应用日志级别
            if let logLevel = settings["log.level"] as? String {
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
            
            DispatchQueue.main.async {
                EventBus.shared.publish(
                    SettingsSaved(success: success, error: error)
                )
                
                NotificationCenter.default.post(name: .ConfigurationChanged, object: nil)
            }
        }
    }
    
    // MARK: - 清理
    func cleanup() {
        subscriptionTokens.forEach { $0.unsubscribe() }
        subscriptionTokens.removeAll()
    }
}
