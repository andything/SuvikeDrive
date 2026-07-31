//
//  ProtocolModuleManager.swift
//  SuvikeDrive
//
//  功能: 全存储协议统一管理
//

import AppKit
import Foundation

// MARK: - 协议类型枚举
enum ProtocolType: String, CaseIterable, Codable {
    case webdav = "webdav"
    case smb = "smb"
    case ftp = "ftp"
    case sftp = "sftp"
    case nfs = "nfs"
    
    var displayName: String {
        switch self {
        case .webdav: return "WebDAV"
        case .smb: return "SMB"
        case .ftp: return "FTP"
        case .sftp: return "SFTP"
        case .nfs: return "NFS"
        }
    }
    
    var defaultPort: Int {
        switch self {
        case .webdav: return 443
        case .smb: return 445
        case .ftp: return 21
        case .sftp: return 22
        case .nfs: return 2049
        }
    }
}

// MARK: - 连接状态枚举
enum ConnectionState {
    case idle
    case connecting
    case connected
    case mounted
    case disconnecting
    case disconnected
    case error
    case reconnecting
}

// MARK: - 协议能力集
struct ProtocolCapabilities: OptionSet {
    let rawValue: Int
    
    static let fileList = ProtocolCapabilities(rawValue: 1 << 0)
    static let upload = ProtocolCapabilities(rawValue: 1 << 1)
    static let download = ProtocolCapabilities(rawValue: 1 << 2)
    static let delete = ProtocolCapabilities(rawValue: 1 << 3)
    static let move = ProtocolCapabilities(rawValue: 1 << 4)
    static let copy = ProtocolCapabilities(rawValue: 1 << 5)
    static let createDirectory = ProtocolCapabilities(rawValue: 1 << 6)
    static let rename = ProtocolCapabilities(rawValue: 1 << 7)
    static let permissions = ProtocolCapabilities(rawValue: 1 << 8)
    static let symlink = ProtocolCapabilities(rawValue: 1 << 9)
    static let resumeDownload = ProtocolCapabilities(rawValue: 1 << 10)
    static let resumeUpload = ProtocolCapabilities(rawValue: 1 << 11)
    static let compression = ProtocolCapabilities(rawValue: 1 << 12)
    static let encryption = ProtocolCapabilities(rawValue: 1 << 13)
    static let heartbeat = ProtocolCapabilities(rawValue: 1 << 14)
    static let capacity = ProtocolCapabilities(rawValue: 1 << 15)
    static let ping = ProtocolCapabilities(rawValue: 1 << 16)
}

// MARK: - 配置架构
struct ConfigSchema {
    let sections: [ConfigSection]
    
    init(sections: [ConfigSection] = []) {
        self.sections = sections
    }
}

struct ConfigSection {
    let name: String
    let fields: [ConfigField]
    let isExpanded: Bool
    
    init(name: String, fields: [ConfigField], isExpanded: Bool = true) {
        self.name = name
        self.fields = fields
        self.isExpanded = isExpanded
    }
}

struct ConfigField {
    let key: String
    let label: String
    let type: ConfigFieldType
    let defaultValue: Any?
    let placeholder: String?
    let options: [ConfigOption]?
    let validation: ConfigValidation?
    let isRequired: Bool
    let isSecure: Bool
    
    init(
        key: String,
        label: String,
        type: ConfigFieldType,
        defaultValue: Any? = nil,
        placeholder: String? = nil,
        options: [ConfigOption]? = nil,
        validation: ConfigValidation? = nil,
        isRequired: Bool = false,
        isSecure: Bool = false
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.options = options
        self.validation = validation
        self.isRequired = isRequired
        self.isSecure = isSecure
    }
}

enum ConfigFieldType: String {
    case text
    case password
    case number
    case boolean
    case dropdown
    case url
    case path
    case port
    case textarea
    case checkbox
}

struct ConfigOption {
    let label: String
    let value: String
    
    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

struct ConfigValidation {
    let pattern: String?
    let minValue: Double?
    let maxValue: Double?
    let minLength: Int?
    let maxLength: Int?
    let customValidator: ((Any) -> Bool)?
    
    init(
        pattern: String? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        customValidator: ((Any) -> Bool)? = nil
    ) {
        self.pattern = pattern
        self.minValue = minValue
        self.maxValue = maxValue
        self.minLength = minLength
        self.maxLength = maxLength
        self.customValidator = customValidator
    }
}

// MARK: - 容量信息
struct CapacityInfo {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    
    var formattedTotal: String {
        return ByteCountFormatter().string(fromByteCount: Int64(total))
    }
    
    var formattedUsed: String {
        return ByteCountFormatter().string(fromByteCount: Int64(used))
    }
    
    var formattedFree: String {
        return ByteCountFormatter().string(fromByteCount: Int64(free))
    }
}

// MARK: - 文件信息
struct FileInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modificationDate: Date
    let permissions: String?
    let owner: String?
    let group: String?
    let creationDate: Date?
    let lastAccessDate: Date?
}

// MARK: - 协议模块协议
protocol ProtocolModule: AnyObject {
    var type: ProtocolType { get }
    var name: String { get }
    var version: String { get }
    var capabilities: ProtocolCapabilities { get }
    
    func initialize() throws
    func shutdown() throws
    
    func connect(serverID: String, config: ServerConfig) throws
    func disconnect(serverID: String) throws
    func isConnected(serverID: String) -> Bool
    
    func mount(serverID: String, mountPath: String) throws
    func unmount(serverID: String) throws
    func isMounted(serverID: String) -> Bool
    
    func listFiles(serverID: String, path: String) throws -> [FileInfo]
    func getFileInfo(serverID: String, path: String) throws -> FileInfo
    func createDirectory(serverID: String, path: String) throws
    func deleteItem(serverID: String, path: String) throws
    func moveItem(serverID: String, from: String, to: String) throws
    func copyItem(serverID: String, from: String, to: String) throws
    
    func downloadFile(serverID: String, remotePath: String, localPath: String, progress: @escaping (Double) -> Void) throws
    func uploadFile(serverID: String, localPath: String, remotePath: String, progress: @escaping (Double) -> Void) throws
    func cancelTransfer(serverID: String, transferID: String) throws
    
    func ping(serverID: String) -> Bool
    func getCapacity(serverID: String) -> CapacityInfo?
    
    func getConfigSchema() -> ConfigSchema
    func validateConfig(_ config: [String: Any]) -> [String: String]
}

// MARK: - 协议模块扩展（提供默认实现）
extension ProtocolModule {
    func getConfigSchema() -> ConfigSchema {
        return ConfigSchema(sections: [
            ConfigSection(name: "连接设置", fields: [
                ConfigField(key: "url", label: "服务器地址", type: .url, isRequired: true),
                ConfigField(key: "username", label: "用户名", type: .text),
                ConfigField(key: "password", label: "密码", type: .password, isSecure: true)
            ])
        ])
    }
    
    func validateConfig(_ config: [String: Any]) -> [String: String] {
        var errors: [String: String] = [:]
        if let url = config["url"] as? String, url.isEmpty {
            errors["url"] = "服务器地址不能为空"
        }
        return errors
    }
    
    func cancelTransfer(serverID: String, transferID: String) throws {
        throw ProtocolError.notSupported
    }
    
    func getCapacity(serverID: String) -> CapacityInfo? {
        return nil
    }
    
    func ping(serverID: String) -> Bool {
        return false
    }
}

// MARK: - 协议错误
enum ProtocolError: Error {
    case downloadFailed(Error?)
    case uploadFailed(Error?)
    case moduleNotAvailable
    case connectionFailed(String)
    case authenticationFailed
    case timeout
    case fileNotFound
    case permissionDenied
    case transferFailed(String)
    case invalidPath
    case notSupported
    case mountFailed(String)
    case unmountFailed(String)
    case instanceNotFound
    
    var localizedDescription: String {
        switch self {
        case .moduleNotAvailable:
            return "协议模块不可用"
        case .connectionFailed(let message):
            return "连接失败: \(message)"
        case .authenticationFailed:
            return "认证失败"
        case .timeout:
            return "操作超时"
        case .fileNotFound:
            return "文件未找到"
        case .permissionDenied:
            return "权限被拒绝"
        case .transferFailed(let message):
            return "传输失败: \(message)"
        case .invalidPath:
            return "无效路径"
        case .notSupported:
            return "操作不支持"
        case .mountFailed(let message):
            return "挂载失败: \(message)"
        case .unmountFailed(let message):
            return "卸载失败: \(message)"
        case .downloadFailed(let error):
            return "下载失败: \(error?.localizedDescription ?? "未知错误")"
        case .uploadFailed(let error):
            return "上传失败: \(error?.localizedDescription ?? "未知错误")"
        case .instanceNotFound:
            return "协议实例未找到"
        }
    }
}

// MARK: - 协议管理器
class ProtocolModuleManager {
    static let shared = ProtocolModuleManager()
    
    private var modules: [ProtocolType: ProtocolModule] = [:]
    private var instances: [String: ProtocolModule] = [:]
    private var instanceConfigs: [String: ServerConfig] = [:]
    private var connectionStatus: [String: ConnectionState] = [:]
    private let queue = DispatchQueue(label: "com.suvikedrive.protocolmanager")
    
    private init() {
        registerDefaultModules()
    }
    
    // MARK: - 注册模块
    private func registerDefaultModules() {
        let modules: [(type: ProtocolType, module: ProtocolModule)] = [
            (.webdav, WebDAVModule.shared),
        ]
        
        for item in modules {
            self.modules[item.type] = item.module
            Logger.shared.debug("协议模块已注册: \(item.type.displayName)")
        }
    }
    
    // MARK: - 获取模块
    func getModule(type: ProtocolType) -> ProtocolModule? {
        var result: ProtocolModule?
        queue.sync {
            result = self.modules[type]
        }
        return result
    }
    
    func getInstance(serverID: String) -> ProtocolModule? {
        var result: ProtocolModule?
        queue.sync {
            result = self.instances[serverID]
        }
        return result
    }
    
    func getInstanceConfig(serverID: String) -> ServerConfig? {
        var result: ServerConfig?
        queue.sync {
            result = self.instanceConfigs[serverID]
        }
        return result
    }
    
    func getConnectionStatus(serverID: String) -> ConnectionState {
        var result: ConnectionState = .idle
        queue.sync {
            result = self.connectionStatus[serverID] ?? .idle
        }
        return result
    }
    
    // MARK: - 实例管理
    func getOrCreateInstance(serverID: String, type: ProtocolType) throws -> ProtocolModule {
        if let existing = getInstance(serverID: serverID) {
            return existing
        }
        
        guard let module = getModule(type: type) else {
            throw ProtocolError.moduleNotAvailable
        }
        
        try module.initialize()
        
        queue.async {
            self.instances[serverID] = module
            self.connectionStatus[serverID] = .idle
        }
        
        return module
    }
    
    func registerInstance(serverID: String, config: ServerConfig) throws {
        guard let module = getModule(type: config.protocolType) else {
            throw ProtocolError.moduleNotAvailable
        }
        
        try module.initialize()
        
        queue.async {
            self.instances[serverID] = module
            self.instanceConfigs[serverID] = config
            self.connectionStatus[serverID] = .idle
        }
        
        Logger.shared.debug("协议实例已注册: \(serverID)")
    }
    
    func removeInstance(serverID: String) {
        queue.async {
            if let instance = self.instances[serverID] {
                Logger.shared.info("[\(serverID)] 开始移除协议实例...", module: "ProtocolModuleManager")
                
                // 1. 先取消所有网络任务
                NetworkManager.shared.cancelAllTasks(serverID: serverID)
                Logger.shared.info("[\(serverID)] 已取消所有网络任务", module: "ProtocolModuleManager")
                
                // 2. 如果是 WebDAV 模块，强制断开连接并取消会话
                if let webdavModule = instance as? WebDAVModule {
                    webdavModule.forceDisconnect(serverID: serverID)
                    Logger.shared.info("[\(serverID)] WebDAV 模块已强制断开", module: "ProtocolModuleManager")
                }
                
                // 3. 正常断开和关闭
                try? instance.disconnect(serverID: serverID)
                try? instance.shutdown()
                
                // 4. 清理资源
                self.instances.removeValue(forKey: serverID)
                self.instanceConfigs.removeValue(forKey: serverID)
                self.connectionStatus.removeValue(forKey: serverID)
                
                Logger.shared.info("[\(serverID)] 协议实例已移除", module: "ProtocolModuleManager")
            }
        }
    }
    
    // MARK: - 同步移除实例（用于卸载时立即清理）
    func removeInstanceSync(serverID: String) {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async {
            if let instance = self.instances[serverID] {
                Logger.shared.info("[\(serverID)] 开始同步移除协议实例...", module: "ProtocolModuleManager")
                
                // 取消所有网络任务
                NetworkManager.shared.cancelAllTasks(serverID: serverID)
                
                // 如果是 WebDAV 模块，强制断开
                if let webdavModule = instance as? WebDAVModule {
                    webdavModule.forceDisconnect(serverID: serverID)
                }
                
                try? instance.disconnect(serverID: serverID)
                try? instance.shutdown()
                
                self.instances.removeValue(forKey: serverID)
                self.instanceConfigs.removeValue(forKey: serverID)
                self.connectionStatus.removeValue(forKey: serverID)
                
                Logger.shared.info("[\(serverID)] 协议实例已同步移除", module: "ProtocolModuleManager")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    // MARK: - 协议操作（统一的入口）
    func connect(serverID: String, config: ServerConfig) throws {
        let module = try getOrCreateInstance(serverID: serverID, type: config.protocolType)
        try module.connect(serverID: serverID, config: config)
        updateConnectionStatus(serverID: serverID, status: .connected)
        
        queue.async {
            self.instanceConfigs[serverID] = config
        }
    }
    
    func disconnect(serverID: String) throws {
        guard let module = getInstance(serverID: serverID) else {
            throw ProtocolError.instanceNotFound
        }
        try module.disconnect(serverID: serverID)
        updateConnectionStatus(serverID: serverID, status: .disconnected)
    }
    
    func mount(serverID: String, mountPath: String) throws {
        guard let module = getInstance(serverID: serverID) else {
            throw ProtocolError.instanceNotFound
        }
        try module.mount(serverID: serverID, mountPath: mountPath)
        updateConnectionStatus(serverID: serverID, status: .mounted)
    }
    
    func unmount(serverID: String) throws {
        guard let module = getInstance(serverID: serverID) else {
            throw ProtocolError.instanceNotFound
        }
        try module.unmount(serverID: serverID)
        updateConnectionStatus(serverID: serverID, status: .connected)
    }
    
    func ping(serverID: String) -> Bool {
        guard let module = getInstance(serverID: serverID) else {
            return false
        }
        return module.ping(serverID: serverID)
    }
    
    // MARK: - 状态更新
    func updateConnectionStatus(serverID: String, status: ConnectionState) {
        queue.async {
            self.connectionStatus[serverID] = status
        }
    }
    
    // MARK: - 查询
    func getAvailableTypes() -> [ProtocolType] {
        var types: [ProtocolType] = []
        queue.sync {
            types = Array(self.modules.keys)
        }
        return types
    }
    
    func getProtocolCapabilities(type: ProtocolType) -> ProtocolCapabilities? {
        return getModule(type: type)?.capabilities
    }
    
    func isProtocolSupported(_ type: ProtocolType) -> Bool {
        return getModule(type: type) != nil
    }
    
    func getAllInstances() -> [String: ProtocolModule] {
        var result: [String: ProtocolModule] = [:]
        queue.sync {
            result = self.instances
        }
        return result
    }
    
    // MARK: - 协议可用性检测
    func checkProtocolAvailability(_ type: ProtocolType) -> Bool {
        switch type {
        case .webdav:
            return FileManager.default.fileExists(atPath: "/sbin/mount_webdav") ||
                   FileManager.default.fileExists(atPath: "/usr/bin/osascript")
        case .smb:
            return FileManager.default.fileExists(atPath: "/sbin/mount_smbfs")
        case .ftp:
            return FileManager.default.fileExists(atPath: "/usr/bin/curl")
        case .sftp:
            return FileManager.default.fileExists(atPath: "/usr/bin/sftp")
        case .nfs:
            return FileManager.default.fileExists(atPath: "/sbin/mount_nfs")
        }
    }
}
