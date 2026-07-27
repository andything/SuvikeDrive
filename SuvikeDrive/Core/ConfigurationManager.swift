//
//  ConfigurationManager.swift
//  SuvikeDrive
//
//  功能: 配置管理
//

import AppKit
import Foundation

class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private var _config: [String: Any] = [:]
    private let configFileName = "config.json"
    private var configPath: URL?
    
    var config: [String: Any] {
        get { _config }
        set { _config = newValue; saveConfiguration() }
    }
    
    private init() {
        setupPaths()
        loadConfiguration()
    }
    
    private func setupPaths() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("com.suvikedrive.drive")
        
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        
        configPath = appDir.appendingPathComponent(configFileName)
    }
    
    func loadConfiguration() {
        guard let path = configPath,
              FileManager.default.fileExists(atPath: path.path) else {
            _config = getDefaultConfiguration()
            return
        }
        
        do {
            let data = try Data(contentsOf: path)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                _config = json
            }
        } catch {
            _config = getDefaultConfiguration()
        }
    }
    
    func saveConfiguration() {
        guard let path = configPath else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: _config, options: .prettyPrinted)
            try data.write(to: path)
        } catch {
            print("保存配置失败: \(error)")
        }
    }
    
    func get<T>(key: String, defaultValue: T) -> T {
        let components = key.split(separator: ".")
        var current: Any = _config
        
        for component in components {
            if let dict = current as? [String: Any],
               let value = dict[String(component)] {
                current = value
            } else {
                return defaultValue
            }
        }
        
        return current as? T ?? defaultValue
    }
    
    func set<T>(key: String, value: T) {
        let components = key.split(separator: ".")
        
        if components.count == 1 {
            _config[String(components[0])] = value
            saveConfiguration()
            return
        }
        
        func setValue(in dict: inout [String: Any], components: [String.SubSequence], index: Int, value: T) {
            let key = String(components[index])
            if index == components.count - 1 {
                dict[key] = value
            } else {
                if dict[key] == nil {
                    dict[key] = [String: Any]()
                }
                if var subDict = dict[key] as? [String: Any] {
                    setValue(in: &subDict, components: components, index: index + 1, value: value)
                    dict[key] = subDict
                }
            }
        }
        
        var config = _config
        setValue(in: &config, components: components, index: 0, value: value)
        _config = config
        saveConfiguration()
    }
    
    // MARK: - ✅ 类型安全的服务器管理（使用 ServerConfig）
    
    /// 获取所有服务器配置（类型安全）
    func getServers() -> [ServerConfig] {
        let serversArray = get(key: "servers", defaultValue: [[String: Any]]())
        return serversArray.map { ServerConfig.fromDictionary($0) }
    }
    
    /// 获取单个服务器配置（类型安全）
    func getServer(id: String) -> ServerConfig? {
        return getServers().first { $0.id == id }
    }
    
    /// 添加服务器（类型安全）
    func addServer(_ server: ServerConfig) {
        var servers = getServers()
        servers.append(server)
        set(key: "servers", value: servers.map { $0.toDictionary() })
        postConfigurationChanged()
    }
    
    /// 删除服务器（类型安全）
    func removeServer(id: String) {
        var servers = getServers()
        servers.removeAll { $0.id == id }
        set(key: "servers", value: servers.map { $0.toDictionary() })
        postConfigurationChanged()
    }
    
    /// 更新服务器（类型安全）
    func updateServer(id: String, updates: [String: Any]) {
        var servers = getServers()
        if let index = servers.firstIndex(where: { $0.id == id }) {
            var server = servers[index]
            
            // 手动更新字段
            if let name = updates["name"] as? String { server.name = name }
            if let url = updates["url"] as? String { server.url = url }
            if let username = updates["username"] as? String { server.username = username }
            if let password = updates["password"] as? String { server.password = password }
            if let mountPath = updates["mountPath"] as? String { server.mountPath = mountPath }
            if let timeout = updates["timeout"] as? Int { server.timeout = timeout }
            if let maxRetries = updates["maxRetries"] as? Int { server.maxRetries = maxRetries }
            if let retryInterval = updates["retryInterval"] as? Int { server.retryInterval = retryInterval }
            if let autoMount = updates["autoMount"] as? Bool { server.autoMount = autoMount }
            if let mountOptions = updates["mountOptions"] as? [String: String] { server.mountOptions = mountOptions }
            if let isEnabled = updates["isEnabled"] as? Bool { server.isEnabled = isEnabled }
            if let protocolConfig = updates["protocolConfig"] as? [String: Any] {
                for (key, value) in protocolConfig {
                    server.setProtocolConfig(key: key, value: value)
                }
            }
            
            servers[index] = server
            set(key: "servers", value: servers.map { $0.toDictionary() })
            postConfigurationChanged()
        }
    }
    
    /// 更新服务器配置（直接传入完整 ServerConfig）
    func updateServer(_ server: ServerConfig) {
        var servers = getServers()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            set(key: "servers", value: servers.map { $0.toDictionary() })
            postConfigurationChanged()
        }
    }
    
    // MARK: - ✅ 兼容旧版字典 API（标记为废弃，逐步迁移）
    @available(*, deprecated, message: "使用类型安全的 getServers() 替代")
    func getServersLegacy() -> [[String: Any]] {
        return get(key: "servers", defaultValue: [[String: Any]]())
    }
    
    @available(*, deprecated, message: "使用类型安全的 addServer(_:) 替代")
    func addServerLegacy(_ server: [String: Any]) {
        var servers = get(key: "servers", defaultValue: [[String: Any]]())
        servers.append(server)
        set(key: "servers", value: servers)
        postConfigurationChanged()
    }
    
    @available(*, deprecated, message: "使用类型安全的 removeServer(id:) 替代")
    func removeServerLegacy(id: String) {
        var servers = get(key: "servers", defaultValue: [[String: Any]]())
        servers.removeAll { ($0["id"] as? String) == id }
        set(key: "servers", value: servers)
        postConfigurationChanged()
    }
    
    @available(*, deprecated, message: "使用类型安全的 updateServer(id:updates:) 替代")
    func updateServerLegacy(id: String, updates: [String: Any]) {
        var servers = get(key: "servers", defaultValue: [[String: Any]]())
        if let index = servers.firstIndex(where: { ($0["id"] as? String) == id }) {
            var server = servers[index]
            for (key, value) in updates {
                server[key] = value
            }
            servers[index] = server
            set(key: "servers", value: servers)
            postConfigurationChanged()
        }
    }
    
    // MARK: - 通知发送
    private func postConfigurationChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .ConfigurationChanged, object: nil)
            Logger.shared.debug("配置已变更，已发送通知")
        }
    }
    
    func getDefaultConfiguration() -> [String: Any] {
        return [
            "app": [
                "version": "1.0.0",
                "autoMount": false,
                "autoUpdate": true
            ],
            "servers": []
        ]
    }
    
    // MARK: - 重置配置
    
    func resetToDefaults() {
        _config = getDefaultConfiguration()
        saveConfiguration()
        applyConfiguration()
        Logger.shared.info("配置已重置为默认值")
        postConfigurationChanged()
    }
    
    private func applyConfiguration() {
        if let logLevel = get(key: "log.level", defaultValue: "info") {
            let level: LogLevel
            switch logLevel {
            case "debug": level = .debug
            case "info": level = .info
            case "warning": level = .warning
            case "error": level = .error
            default: level = .info
            }
            Logger.shared.setLogLevel(level)
        }
        
        let maxSize = get(key: "cache.maxSize", defaultValue: 524288000)
        ConfigurationManager.shared.set(key: "cache.maxSize", value: maxSize)
    }
}
