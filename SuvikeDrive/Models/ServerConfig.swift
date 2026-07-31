//
//  ServerConfig.swift
//  SuvikeDrive
//
//  功能: 服务器配置数据模型
//

import AppKit
import Foundation

// ✅ ProtocolType 已在 ProtocolModule.swift 中定义

// MARK: - 服务器配置
struct ServerConfig: Codable, Identifiable {
    // 基础标识
    let id: String
    var name: String
    var protocolType: ProtocolType
    
    // 连接信息
    var url: String
    var username: String?
    var password: String?
    var mountPath: String?
    
    // 连接配置
    var timeout: Int
    var maxRetries: Int
    var retryInterval: Int
    
    // 挂载配置
    var autoMount: Bool
    var mountOptions: [String: String]
    
    // 时间戳
    var createdAt: Date
    var lastMountAt: Date?
    var lastErrorAt: Date?
    var lastError: String?
    
    // 协议专属配置
    var protocolConfig: [String: AnyCodable]
    
    // 状态
    var isEnabled: Bool
    var mountCount: Int
    
    // MARK: - 初始化
    init(
        id: String = UUID().uuidString,
        name: String,
        protocolType: ProtocolType,
        url: String,
        username: String? = nil,
        password: String? = nil,
        mountPath: String? = nil,
        timeout: Int = 30,
        maxRetries: Int = 3,
        retryInterval: Int = 5,
        autoMount: Bool = false,
        mountOptions: [String: String] = [:],
        protocolConfig: [String: AnyCodable] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.url = url
        self.username = username
        self.password = password
        self.mountPath = mountPath
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.retryInterval = retryInterval
        self.autoMount = autoMount
        self.mountOptions = mountOptions
        self.createdAt = Date()
        self.lastMountAt = nil
        self.lastErrorAt = nil
        self.lastError = nil
        self.protocolConfig = protocolConfig
        self.isEnabled = isEnabled
        self.mountCount = 0
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, name, protocolType, url, username, password, mountPath
        case timeout, maxRetries, retryInterval, autoMount, mountOptions
        case createdAt, lastMountAt, lastErrorAt, lastError
        case protocolConfig, isEnabled, mountCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        protocolType = try container.decode(ProtocolType.self, forKey: .protocolType)
        url = try container.decode(String.self, forKey: .url)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        mountPath = try container.decodeIfPresent(String.self, forKey: .mountPath)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 30
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 3
        retryInterval = try container.decodeIfPresent(Int.self, forKey: .retryInterval) ?? 5
        autoMount = try container.decodeIfPresent(Bool.self, forKey: .autoMount) ?? false
        mountOptions = try container.decodeIfPresent([String: String].self, forKey: .mountOptions) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastMountAt = try container.decodeIfPresent(Date.self, forKey: .lastMountAt)
        lastErrorAt = try container.decodeIfPresent(Date.self, forKey: .lastErrorAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        protocolConfig = try container.decodeIfPresent([String: AnyCodable].self, forKey: .protocolConfig) ?? [:]
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mountCount = try container.decodeIfPresent(Int.self, forKey: .mountCount) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(protocolType, forKey: .protocolType)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encodeIfPresent(mountPath, forKey: .mountPath)
        try container.encode(timeout, forKey: .timeout)
        try container.encode(maxRetries, forKey: .maxRetries)
        try container.encode(retryInterval, forKey: .retryInterval)
        try container.encode(autoMount, forKey: .autoMount)
        try container.encode(mountOptions, forKey: .mountOptions)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastMountAt, forKey: .lastMountAt)
        try container.encodeIfPresent(lastErrorAt, forKey: .lastErrorAt)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(protocolConfig, forKey: .protocolConfig)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mountCount, forKey: .mountCount)
    }
    
    // MARK: - 便捷方法
    
    func getProtocolConfig<T>(key: String, defaultValue: T) -> T {
        return protocolConfig[key]?.value as? T ?? defaultValue
    }
    
    mutating func setProtocolConfig<T>(key: String, value: T) {
        protocolConfig[key] = AnyCodable(value)
    }
    
    /// ✅ 获取挂载路径 - 使用 SuvikeDrive 目录
    func getMountPath() -> String {
        if let customPath = mountPath, !customPath.isEmpty {
            return customPath
        }
        // ✅ 使用 SuvikeDrive 目录
        let home = NSHomeDirectory()
        let suvikeDrivePath = "\(home)/SuvikeDrive"
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: suvikeDrivePath) {
            try? FileManager.default.createDirectory(
                atPath: suvikeDrivePath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        let sanitizedName = sanitizeName(name)
        return "\(suvikeDrivePath)/\(sanitizedName)"
    }
    
    /// ✅ 获取完整 URL（包含协议）
    func getFullURL() -> String {
        var fullURL = url.trimmingCharacters(in: .whitespaces)
        
        if !fullURL.contains("://") {
            switch protocolType {
            case .webdav:
                fullURL = "https://\(fullURL)"
            case .smb:
                fullURL = "smb://\(fullURL)"
            case .ftp:
                fullURL = "ftp://\(fullURL)"
            case .sftp:
                fullURL = "sftp://\(fullURL)"
            case .nfs:
                fullURL = "nfs://\(fullURL)"
            }
        }
        
        return fullURL
    }
    
    func getHost() -> String? {
        guard let url = URL(string: getFullURL()) else { return nil }
        return url.host
    }
    
    /// ✅ 获取端口
    func getPort() -> Int {
        // 首先检查 protocolConfig 中的 port
        if let port = protocolConfig["port"]?.value as? Int {
            return port
        }
        if let port = protocolConfig["port"]?.value as? String, let intPort = Int(port) {
            return intPort
        }
        // 然后检查 URL 中的端口
        if let url = URL(string: getFullURL()), let port = url.port {
            return port
        }
        // 默认端口
        return protocolType.defaultPort
    }
    
    func getPath() -> String {
        guard let url = URL(string: getFullURL()) else { return "/" }
        let path = url.path
        return path.isEmpty ? "/" : path
    }
    
    func getDisplayName() -> String {
        return "[\(protocolType.displayName)] \(name)"
    }
    
    func getStatusDescription() -> String {
        if let lastError = lastError, let lastErrorAt = lastErrorAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return "错误: \(lastError) (于 \(formatter.string(from: lastErrorAt)))"
        }
        if let lastMountAt = lastMountAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return "上次挂载: \(formatter.string(from: lastMountAt))"
        }
        return "从未挂载"
    }
    
    func isValid() -> Bool {
        guard !name.isEmpty else { return false }
        guard !url.isEmpty else { return false }
        guard Utils.shared.validateURL(getFullURL()) else { return false }
        guard timeout >= 5 && timeout <= 300 else { return false }
        guard maxRetries >= 0 && maxRetries <= 10 else { return false }
        guard retryInterval >= 1 && retryInterval <= 60 else { return false }
        return true
    }
    
    mutating func recordMountSuccess() {
        lastMountAt = Date()
        mountCount += 1
        lastError = nil
        lastErrorAt = nil
    }
    
    mutating func recordMountFailure(error: String) {
        lastError = error
        lastErrorAt = Date()
    }
    
    mutating func resetError() {
        lastError = nil
        lastErrorAt = nil
    }
    
    func sanitized() -> ServerConfig {
        var sanitized = self
        sanitized.password = nil
        return sanitized
    }
    
    // MARK: - 私有辅助方法
    
    private func sanitizeName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}

// MARK: - AnyCodable
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "不支持的类型")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - 字典转换
extension ServerConfig {
    static func fromDictionary(_ dict: [String: Any]) -> ServerConfig {
        let id = dict["id"] as? String ?? UUID().uuidString
        let name = dict["name"] as? String ?? "未命名服务器"
        let protocolTypeString = dict["protocol"] as? String ?? "webdav"
        let protocolType = ProtocolType(rawValue: protocolTypeString) ?? .webdav
        let url = dict["url"] as? String ?? ""
        let username = dict["username"] as? String
        let password = dict["password"] as? String
        let mountPath = dict["mountPath"] as? String
        let timeout = dict["timeout"] as? Int ?? 30
        let maxRetries = dict["maxRetries"] as? Int ?? 3
        let retryInterval = dict["retryInterval"] as? Int ?? 5
        let autoMount = dict["autoMount"] as? Bool ?? false
        let mountOptions = dict["mountOptions"] as? [String: String] ?? [:]
        let isEnabled = dict["isEnabled"] as? Bool ?? true
        
        var protocolConfig: [String: AnyCodable] = [:]
        if let config = dict["protocolConfig"] as? [String: Any] {
            for (key, value) in config {
                protocolConfig[key] = AnyCodable(value)
            }
        }
        
        var serverConfig = ServerConfig(
            id: id,
            name: name,
            protocolType: protocolType,
            url: url,
            username: username,
            password: password,
            mountPath: mountPath,
            timeout: timeout,
            maxRetries: maxRetries,
            retryInterval: retryInterval,
            autoMount: autoMount,
            mountOptions: mountOptions,
            protocolConfig: protocolConfig,
            isEnabled: isEnabled
        )
        
        if let createdAtTimestamp = dict["createdAt"] as? TimeInterval {
            serverConfig.createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
        }
        if let lastMountAtTimestamp = dict["lastMountAt"] as? TimeInterval {
            serverConfig.lastMountAt = Date(timeIntervalSince1970: lastMountAtTimestamp)
        }
        if let lastErrorAtTimestamp = dict["lastErrorAt"] as? TimeInterval {
            serverConfig.lastErrorAt = Date(timeIntervalSince1970: lastErrorAtTimestamp)
        }
        if let lastError = dict["lastError"] as? String {
            serverConfig.lastError = lastError
        }
        if let mountCount = dict["mountCount"] as? Int {
            serverConfig.mountCount = mountCount
        }
        
        return serverConfig
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "protocol": protocolType.rawValue,
            "url": url,
            "timeout": timeout,
            "maxRetries": maxRetries,
            "retryInterval": retryInterval,
            "autoMount": autoMount,
            "mountOptions": mountOptions,
            "createdAt": createdAt.timeIntervalSince1970,
            "isEnabled": isEnabled,
            "mountCount": mountCount
        ]
        
        if let username = username { dict["username"] = username }
        if let password = password { dict["password"] = password }
        if let mountPath = mountPath { dict["mountPath"] = mountPath }
        if let lastMountAt = lastMountAt { dict["lastMountAt"] = lastMountAt.timeIntervalSince1970 }
        if let lastErrorAt = lastErrorAt { dict["lastErrorAt"] = lastErrorAt.timeIntervalSince1970 }
        if let lastError = lastError { dict["lastError"] = lastError }
        
        var configDict: [String: Any] = [:]
        for (key, value) in protocolConfig {
            configDict[key] = value.value
        }
        dict["protocolConfig"] = configDict
        
        return dict
    }
    
    func copy() -> ServerConfig {
        return ServerConfig(
            id: id,
            name: name,
            protocolType: protocolType,
            url: url,
            username: username,
            password: password,
            mountPath: mountPath,
            timeout: timeout,
            maxRetries: maxRetries,
            retryInterval: retryInterval,
            autoMount: autoMount,
            mountOptions: mountOptions,
            protocolConfig: protocolConfig,
            isEnabled: isEnabled
        )
    }
}

extension ServerConfig: Equatable {
    static func == (lhs: ServerConfig, rhs: ServerConfig) -> Bool {
        return lhs.id == rhs.id
    }
}

extension ServerConfig: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
