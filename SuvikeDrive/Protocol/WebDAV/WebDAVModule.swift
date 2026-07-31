//
//  WebDAVModule.swift
//  SuvikeDrive
//
//  功能: WebDAV 协议模块
//  归属: Protocol/WebDAV
//

@preconcurrency import Foundation

final class WebDAVModule: ProtocolModule {
    static let shared = WebDAVModule()
    
    var type: ProtocolType { .webdav }
    var name: String { "WebDAV" }
    var version: String { "1.0.0" }
    var capabilities: ProtocolCapabilities {
        return [.fileList, .upload, .download, .delete, .move, .copy, .createDirectory, .rename]
    }
    
    private var connections: [String: WebDAVConnection] = [:]
    private let queue = DispatchQueue(label: "com.suvikedrive.webdavmodule")
    
    private init() {}
    
    // MARK: - ProtocolModule 方法
    
    func initialize() throws {
        Logger.shared.info("WebDAV 模块初始化", module: "WebDAVModule")
    }
    
    func shutdown() throws {
        Logger.shared.info("WebDAV 模块关闭", module: "WebDAVModule")
        queue.sync {
            for (serverID, connection) in connections {
                connection.disconnect()
                Logger.shared.info("[\(serverID)] 连接已关闭", module: "WebDAVModule")
            }
            connections.removeAll()
        }
    }
    
    func connect(serverID: String, config: ServerConfig) throws {
        queue.sync {
            if let existing = connections[serverID] {
                existing.disconnect()
            }
            let connection = WebDAVConnection(serverID: serverID, config: config)
            connections[serverID] = connection
            Logger.shared.info("[\(serverID)] WebDAV 连接已建立", module: "WebDAVModule")
        }
    }
    
    func disconnect(serverID: String) throws {
        queue.sync {
            if let connection = connections[serverID] {
                connection.disconnect()
                connections.removeValue(forKey: serverID)
                Logger.shared.info("[\(serverID)] WebDAV 连接已断开", module: "WebDAVModule")
            }
        }
    }
    
    func isConnected(serverID: String) -> Bool {
        var result = false
        queue.sync {
            if let connection = connections[serverID] {
                result = connection.isMounted || connection.getSession() != nil
            }
        }
        return result
    }
    
    func mount(serverID: String, mountPath: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        
        try WebDAVMounter.shared.mount(serverID: serverID, config: config, connection: connection)
    }
    
    func unmount(serverID: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        WebDAVMounter.shared.cancelSyncTask(serverID: serverID)
        try WebDAVMounter.shared.unmount(serverID: serverID, connection: connection, mode: .onlySymlink)
    }
    
    func isMounted(serverID: String) -> Bool {
        var result = false
        queue.sync {
            result = connections[serverID]?.isMounted ?? false
        }
        return result
    }
    
    func listFiles(serverID: String, path: String) throws -> [FileInfo] {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        
        let files = try WebDAVMounter.shared.listRemoteFiles(config: config, path: path)
        return files.map { file in
            FileInfo(
                name: file.name,
                path: file.path,
                isDirectory: file.isDirectory,
                size: UInt64(file.size),
                modificationDate: Date(),
                permissions: nil,
                owner: nil,
                group: nil,
                creationDate: nil,
                lastAccessDate: nil
            )
        }
    }
    
    func getFileInfo(serverID: String, path: String) throws -> FileInfo {
        let files = try listFiles(serverID: serverID, path: path)
        guard let file = files.first(where: { $0.path == path }) else {
            throw ProtocolError.fileNotFound
        }
        return file
    }
    
    func createDirectory(serverID: String, path: String) throws {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        try WebDAVMounter.shared.createRemoteDirectory(config: config, path: path)
    }
    
    func deleteItem(serverID: String, path: String) throws {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        try WebDAVMounter.shared.deleteRemoteFile(config: config, path: path)
    }
    
    func moveItem(serverID: String, from: String, to: String) throws {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        try WebDAVMounter.shared.moveRemoteFile(config: config, from: from, to: to)
    }
    
    func copyItem(serverID: String, from: String, to: String) throws {
        throw ProtocolError.notSupported
    }
    
    func downloadFile(serverID: String, remotePath: String, localPath: String, progress: @escaping (Double) -> Void) throws {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        try WebDAVMounter.shared.downloadFile(config: config, remotePath: remotePath, localURL: URL(fileURLWithPath: localPath))
        progress(1.0)
    }
    
    func uploadFile(serverID: String, localPath: String, remotePath: String, progress: @escaping (Double) -> Void) throws {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            throw ProtocolError.connectionFailed("配置不存在")
        }
        try WebDAVMounter.shared.uploadFile(
            config: config,
            localURL: URL(fileURLWithPath: localPath),
            remotePath: remotePath,
            progress: progress
        )
    }
    
    func cancelTransfer(serverID: String, transferID: String) throws {
        NetworkManager.shared.cancelAllTasks(serverID: serverID)
        Logger.shared.info("[\(serverID)] 已取消所有传输任务", module: "WebDAVModule")
    }
    
    func ping(serverID: String) -> Bool {
        guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            return false
        }
        
        let url = WebDAVMounter.shared.buildFullURL(config: config)
        guard let urlObj = URL(string: url) else { return false }
        
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        
        var headers: [String: String] = [:]
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        NetworkManager.shared.request(
            url: urlObj,
            method: .options,
            headers: headers,
            timeout: 10
        ) { networkResult in
            switch networkResult {
            case .success:
                result = true
            case .failure:
                result = false
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 15)
        return result
    }
    
    func getCapacity(serverID: String) -> CapacityInfo? {
        return nil
    }
    
    func getConfigSchema() -> ConfigSchema {
        return ConfigSchema(sections: [
            ConfigSection(name: "连接设置", fields: [
                ConfigField(key: "url", label: "服务器地址", type: .url, isRequired: true),
                ConfigField(key: "username", label: "用户名", type: .text),
                ConfigField(key: "password", label: "密码", type: .password, isSecure: true),
                ConfigField(key: "port", label: "端口", type: .port, defaultValue: 443),
                ConfigField(key: "webdavPath", label: "WebDAV 路径", type: .text, defaultValue: "/"),
                ConfigField(key: "https", label: "使用 HTTPS", type: .boolean, defaultValue: true)
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
    
    // MARK: - 内部方法
    
    private func getConnection(serverID: String) -> WebDAVConnection? {
        var result: WebDAVConnection?
        queue.sync {
            result = connections[serverID]
        }
        return result
    }
    
    // MARK: - 强制断开连接
    
    func forceDisconnect(serverID: String) {
        Logger.shared.info("[\(serverID)] 强制断开 WebDAV 连接...", module: "WebDAVModule")
        
        if let connection = connections[serverID] {
            connection.cancelAllTasks()
            connection.invalidateSession()
            connection.disconnect()
            connections.removeValue(forKey: serverID)
        }
        
        NetworkManager.shared.cancelAllTasks(serverID: serverID)
        WebDAVMounter.shared.cancelSyncTask(serverID: serverID)
        
        Logger.shared.info("[\(serverID)] WebDAV 连接已强制断开", module: "WebDAVModule")
    }
}
