//
//  ServerConfigManager.swift
//  SuvikeDrive
//
//  功能: 服务器配置业务逻辑管理（纯逻辑，无 UI）
//        通过 EventBus 与 UI 通信
//

import Foundation

class ServerConfigManager {
    static let shared = ServerConfigManager()
    
    private let configManager = ConfigurationManager.shared
    private var subscriptionTokens: [SubscriptionToken] = []
    private var isLoading = false
    
    private init() {
        setupEventListeners()
    }
    
    // MARK: - 设置事件监听
    private func setupEventListeners() {
        // 监听保存请求
        let saveToken = EventBus.shared.subscribe(
            to: SaveServerConfigRequest.self,
            priority: .high
        ) { [weak self] event in
            self?.handleSaveRequest(event)
        }
        subscriptionTokens.append(saveToken)
        
        // 监听加载请求
        let loadToken = EventBus.shared.subscribe(
            to: LoadServerConfigRequest.self,
            priority: .high
        ) { [weak self] event in
            self?.handleLoadRequest(event)
        }
        subscriptionTokens.append(loadToken)
        
        // 监听删除请求
        let deleteToken = EventBus.shared.subscribe(
            to: DeleteServerConfigRequest.self,
            priority: .high
        ) { [weak self] event in
            self?.handleDeleteRequest(event)
        }
        subscriptionTokens.append(deleteToken)
        
        // 监听加载列表请求
        let listToken = EventBus.shared.subscribe(
            to: LoadServerListRequest.self,
            priority: .medium
        ) { [weak self] _ in
            self?.handleLoadListRequest()
        }
        subscriptionTokens.append(listToken)
        
        // 监听连接测试请求
        let testToken = EventBus.shared.subscribe(
            to: TestConnectionRequest.self,
            priority: .medium
        ) { [weak self] event in
            self?.handleTestRequest(event)
        }
        subscriptionTokens.append(testToken)
    }
    
    // MARK: - 处理保存请求
    private func handleSaveRequest(_ event: SaveServerConfigRequest) {
        // 打印调试信息
        print("📋 [ServerConfigManager] 收到保存请求: isEditing=\(event.isEditing), serverID=\(event.serverID ?? "nil")")
        print("📋 [ServerConfigManager] config.url=\(event.config.url)")
        print("📋 [ServerConfigManager] config.protocolConfig=\(event.config.protocolConfig)")
        
        // ✅ 修复：安全获取端口值
        let portValue = event.config.getPort()
        print("📋 [ServerConfigManager] config.getPort()=\(String(describing: portValue))")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var normalizedConfig = event.config
            
            // 标准化 URL（分离端口）
            let (host, extractedPort) = self.extractHostAndPort(from: normalizedConfig.url)
            if !host.isEmpty {
                normalizedConfig.url = host
            }
            // ✅ 修复：使用 if let 安全解包提取的端口
            if let port = extractedPort {
                normalizedConfig.setProtocolConfig(key: "port", value: port)
            }
            
            // ✅ 修复：检查端口值，如果为 0 或 nil 则设置默认值
            if normalizedConfig.getPort() == 0 {
                normalizedConfig.setProtocolConfig(key: "port", value: normalizedConfig.protocolType.defaultPort)
            }
            
            var success = false
            let error: String? = nil
            let serverID = event.serverID ?? normalizedConfig.id
            
            if event.isEditing, let id = event.serverID {
                // ✅ 编辑模式：直接传入 normalizedConfig
                self.configManager.updateServer(normalizedConfig)
                success = true
                print("✅ [ServerConfigManager] 更新服务器: id=\(id)")
            } else {
                // 新增模式
                self.configManager.addServer(normalizedConfig)
                success = true
                print("✅ [ServerConfigManager] 添加服务器: id=\(normalizedConfig.id)")
            }
            
            // 验证保存结果
            let savedServers = self.configManager.getServers()
            if let saved = savedServers.first(where: { $0.id == serverID }) {
                print("📋 [ServerConfigManager] 保存后验证: url=\(saved.url)")
                print("📋 [ServerConfigManager] 保存后验证: protocolConfig=\(saved.protocolConfig)")
                print("📋 [ServerConfigManager] 保存后验证: getPort()=\(String(describing: saved.getPort()))")
            }
            
            // ✅ 发布保存结果（纯 EventBus）
            DispatchQueue.main.async {
                EventBus.shared.publish(
                    ServerConfigSaved(serverID: serverID, success: success, error: error)
                )
                
                // 同时发布列表更新
                let servers = self.configManager.getServers()
                EventBus.shared.publish(
                    ServerListLoaded(servers: servers)
                )
                
                // ✅ 发布配置变更事件（替代 NotificationCenter）
                EventBus.shared.publish(
                    ConfigurationChanged(
                        key: "servers",
                        oldValue: nil,
                        newValue: servers
                    )
                )
            }
        }
    }
    
    // MARK: - 处理加载请求
    private func handleLoadRequest(_ event: LoadServerConfigRequest) {
        guard !isLoading else { return }
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let server = self.configManager.getServer(id: event.serverID)
            
            DispatchQueue.main.async {
                self.isLoading = false
                if let server = server {
                    EventBus.shared.publish(
                        ServerConfigLoaded(serverID: event.serverID, config: server)
                    )
                } else {
                    EventBus.shared.publish(
                        ServerConfigSaved(serverID: event.serverID, success: false, error: "服务器配置未找到")
                    )
                }
            }
        }
    }
    
    // MARK: - 处理加载列表请求
    private func handleLoadListRequest() {
        DispatchQueue.global(qos: .userInitiated).async {
            let servers = self.configManager.getServers()
            DispatchQueue.main.async {
                EventBus.shared.publish(
                    ServerListLoaded(servers: servers)
                )
            }
        }
    }
    
    // MARK: - 处理删除请求
    private func handleDeleteRequest(_ event: DeleteServerConfigRequest) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.configManager.removeServer(id: event.serverID)
            
            DispatchQueue.main.async {
                EventBus.shared.publish(
                    ServerConfigDeleted(serverID: event.serverID, success: true)
                )
                
                let servers = self.configManager.getServers()
                EventBus.shared.publish(
                    ServerListLoaded(servers: servers)
                )
                
                // ✅ 发布配置变更事件（替代 NotificationCenter）
                EventBus.shared.publish(
                    ConfigurationChanged(
                        key: "servers",
                        oldValue: nil,
                        newValue: servers
                    )
                )
            }
        }
    }
    
    // MARK: - 处理连接测试请求
    private func handleTestRequest(_ event: TestConnectionRequest) {
        let config = event.config
        
        let useHTTPS = config.getProtocolConfig(key: "https", defaultValue: true)
        let allowSelfSigned = config.getProtocolConfig(key: "selfSigned", defaultValue: false)
        
        // ✅ 修复：getPort() 返回非可选 Int，直接使用
        let port = config.getPort()
        
        NetworkManager.shared.testConnection(
            url: config.url,
            port: port,
            username: config.username,
            password: config.password,
            protocolType: config.protocolType.rawValue,
            useHTTPS: useHTTPS,
            allowSelfSigned: allowSelfSigned
        ) { result in
            DispatchQueue.main.async {
                EventBus.shared.publish(
                    TestConnectionResultEvent(result: result)
                )
            }
        }
    }
    
    // MARK: - 辅助方法：提取主机名和端口
    private func extractHostAndPort(from urlString: String) -> (host: String, port: Int?) {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let prefixes = ["https://", "http://", "ftp://", "sftp://", "smb://", "nfs://"]
        for prefix in prefixes {
            if raw.hasPrefix(prefix) {
                raw = String(raw.dropFirst(prefix.count))
                break
            }
        }
        
        // IPv6 地址: [::1]:8080
        if raw.hasPrefix("[") {
            if let closeBracketIndex = raw.firstIndex(of: "]") {
                let ipv6Part = String(raw[...closeBracketIndex])
                let remaining = String(raw[raw.index(after: closeBracketIndex)...])
                if remaining.hasPrefix(":") {
                    let portString = String(remaining.dropFirst())
                    if let p = Int(portString), p > 0, p < 65536 {
                        return (ipv6Part, p)
                    }
                }
                return (ipv6Part, nil)
            }
        }
        
        // 域名/IPv4: host:port
        if let colonIndex = raw.lastIndex(of: ":") {
            let prefix = String(raw[..<colonIndex])
            if !prefix.contains(":") {
                let portString = String(raw[raw.index(after: colonIndex)...])
                if let p = Int(portString), p > 0, p < 65536 {
                    return (prefix, p)
                }
            }
        }
        
        return (raw, nil)
    }
    
    // MARK: - 清理
    func cleanup() {
        subscriptionTokens.forEach { $0.unsubscribe() }
        subscriptionTokens.removeAll()
    }
}
