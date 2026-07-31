//
//  SMB.swift
//  SuvikeDrive
//
//  功能: SMB协议模块
//

import Foundation

class SMBModule: ProtocolModule {
    let type: ProtocolType = .smb
    let name: String = "SMB"
    let version: String = "1.0.0"
    let capabilities: ProtocolCapabilities = [
        .fileList, .upload, .download, .delete, .move, .copy,
        .createDirectory, .rename, .permissions, .resumeDownload,
        .resumeUpload, .heartbeat, .capacity, .ping
    ]
    
    private var connections: [String: SMBConnection] = [:]
    private let queue = DispatchQueue(label: "com.suvikedrive.smb")
    
    func initialize() throws {
        Logger.shared.debug("SMB协议模块初始化")
    }
    
    func shutdown() throws {
        queue.sync {
            for (serverID, connection) in connections {
                connection.disconnect()
                Logger.shared.debug("SMB连接已关闭: \(serverID)")
            }
            connections.removeAll()
        }
    }
    
    func connect(serverID: String, config: ServerConfig) throws {
        queue.sync {
            if connections[serverID] != nil {
                return
            }
            
            let connection = SMBConnection(config: config)
            connections[serverID] = connection
            Logger.shared.debug("SMB连接已建立: \(serverID)")
        }
    }
    
    func disconnect(serverID: String) throws {
        queue.sync {
            if let connection = connections[serverID] {
                connection.disconnect()
                connections.removeValue(forKey: serverID)
                Logger.shared.debug("SMB连接已断开: \(serverID)")
            }
        }
    }
    
    func isConnected(serverID: String) -> Bool {
        var result = false
        queue.sync {
            result = connections[serverID]?.isConnected ?? false
        }
        return result
    }
    
    func mount(serverID: String, mountPath: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        var credentials: [String: Any] = [:]
        if let username = connection.config.username {
            credentials["username"] = username
        }
        if let password = connection.config.password {
            credentials["password"] = password
        }
        
        // 获取 domain
        let domain = connection.config.getProtocolConfig(key: "domain", defaultValue: "")
        if !domain.isEmpty {
            credentials["domain"] = domain
        }
        
        var options: [String: Any] = [:]
        options["protocol"] = connection.config.getProtocolConfig(key: "protocolVersion", defaultValue: "3.0")
        options["signing"] = connection.config.getProtocolConfig(key: "signing", defaultValue: false)
        options["encryption"] = connection.config.getProtocolConfig(key: "encryption", defaultValue: false)
        
        DiskAPI.shared.mount(
            url: connection.config.getFullURL(),
            mountPath: mountPath,
            credentials: credentials,
            options: options
        ) { result in
            switch result {
            case .success:
                Logger.shared.debug("SMB挂载成功: \(serverID) -> \(mountPath)")
            case .failure(let error):
                Logger.shared.error("SMB挂载失败: \(error.localizedDescription)")
            }
        }
    }
    
    func unmount(serverID: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        DiskAPI.shared.unmount(
            mountPath: connection.config.getMountPath(),
            force: false
        ) { result in
            switch result {
            case .success:
                Logger.shared.debug("SMB卸载成功: \(serverID)")
            case .failure(let error):
                Logger.shared.error("SMB卸载失败: \(error.localizedDescription)")
            }
        }
    }
    
    func isMounted(serverID: String) -> Bool {
        guard let connection = getConnection(serverID: serverID) else { return false }
        return DiskAPI.shared.isMounted(connection.config.getMountPath())
    }
    
    // MARK: - 缓存 Key 生成
    private func cacheKey(serverID: String, path: String) -> String {
        return "smb_\(serverID)_\(path)"
    }
    
    func listFiles(serverID: String, path: String) throws -> [FileInfo] {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let key = cacheKey(serverID: serverID, path: path)
        
        if let cached = CacheManager.shared.getFileList(key: key) {
            return cached
        }
        
        let mountPath = connection.config.getMountPath()
        let fullPath = Utils.shared.joinPath(mountPath, path)
        
        let result = DiskAPI.shared.listFiles(at: fullPath)
        
        switch result {
        case .success(let files):
            let fileInfos = files.map { file in
                FileInfo(
                    name: file.name,
                    path: Utils.shared.joinPath(path, file.name),
                    isDirectory: file.isDirectory,
                    size: file.size,
                    modificationDate: file.modificationDate,
                    permissions: file.permissions,
                    owner: nil,
                    group: nil,
                    creationDate: nil,
                    lastAccessDate: nil
                )
            }
            CacheManager.shared.setFileList(key: key, files: fileInfos)
            return fileInfos
        case .failure(let error):
            throw ProtocolError.connectionFailed(error.localizedDescription)
        }
        }

        func getFileInfo(serverID: String, path: String) throws -> FileInfo {
            let files = try listFiles(serverID: serverID, path: Utils.shared.normalizePath(path))
            let fileName = (path as NSString).lastPathComponent
            return files.first { $0.name == fileName } ?? FileInfo(
                name: fileName,
                path: path,
                isDirectory: false,
                size: 0,
                modificationDate: Date(),
                permissions: "rw-",
                owner: nil,
                group: nil,
                creationDate: nil,
                lastAccessDate: nil
            )
        }
    
    func createDirectory(serverID: String, path: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let mountPath = connection.config.getMountPath()
        let fullPath = Utils.shared.joinPath(mountPath, path)
        
        let result = DiskAPI.shared.createDirectory(at: fullPath)
        
        switch result {
        case .success:
            let key = cacheKey(serverID: serverID, path: Utils.shared.normalizePath(path))
            CacheManager.shared.invalidateFileList(key: key)
            let parentPath = (path as NSString).deletingLastPathComponent
            let parentKey = cacheKey(serverID: serverID, path: parentPath)
            CacheManager.shared.invalidateFileList(key: parentKey)
        case .failure(let error):
            throw ProtocolError.connectionFailed(error.localizedDescription)
        }
    }
    
    func deleteItem(serverID: String, path: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let mountPath = connection.config.getMountPath()
        let fullPath = Utils.shared.joinPath(mountPath, path)
        
        let result = DiskAPI.shared.deleteItem(at: fullPath)
        
        switch result {
        case .success:
            let key = cacheKey(serverID: serverID, path: Utils.shared.normalizePath(path))
            CacheManager.shared.invalidateFileList(key: key)
            let parentPath = (path as NSString).deletingLastPathComponent
            let parentKey = cacheKey(serverID: serverID, path: parentPath)
            CacheManager.shared.invalidateFileList(key: parentKey)
            CacheManager.shared.invalidateFileList(prefix: "smb_\(serverID)_")
        case .failure(let error):
            throw ProtocolError.connectionFailed(error.localizedDescription)
        }
    }
    
    func moveItem(serverID: String, from: String, to: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let mountPath = connection.config.getMountPath()
        let fromPath = Utils.shared.joinPath(mountPath, from)
        let toPath = Utils.shared.joinPath(mountPath, to)
        
        let result = DiskAPI.shared.moveItem(at: fromPath, to: toPath)
        
        switch result {
        case .success:
            let fromKey = cacheKey(serverID: serverID, path: Utils.shared.normalizePath(from))
            let toKey = cacheKey(serverID: serverID, path: Utils.shared.normalizePath(to))
            CacheManager.shared.invalidateFileList(key: fromKey)
            CacheManager.shared.invalidateFileList(key: toKey)
            let fromParent = (from as NSString).deletingLastPathComponent
            let toParent = (to as NSString).deletingLastPathComponent
            CacheManager.shared.invalidateFileList(key: cacheKey(serverID: serverID, path: fromParent))
            CacheManager.shared.invalidateFileList(key: cacheKey(serverID: serverID, path: toParent))
        case .failure(let error):
            throw ProtocolError.connectionFailed(error.localizedDescription)
        }
    }
    
    func copyItem(serverID: String, from: String, to: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let mountPath = connection.config.getMountPath()
        let fromPath = Utils.shared.joinPath(mountPath, from)
        let toPath = Utils.shared.joinPath(mountPath, to)
        
        let result = DiskAPI.shared.copyItem(at: fromPath, to: toPath)
        
        switch result {
        case .success:
            let toKey = cacheKey(serverID: serverID, path: Utils.shared.normalizePath(to))
            CacheManager.shared.invalidateFileList(key: toKey)
            let toParent = (to as NSString).deletingLastPathComponent
            CacheManager.shared.invalidateFileList(key: cacheKey(serverID: serverID, path: toParent))
        case .failure(let error):
            throw ProtocolError.connectionFailed(error.localizedDescription)
        }
    }
    
    func downloadFile(serverID: String, remotePath: String, localPath: String, progress: @escaping (Double) -> Void) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let mountPath = connection.config.getMountPath()
        let fullRemotePath = Utils.shared.joinPath(mountPath, remotePath)
        
        do {
            let fileManager = FileManager.default
            let sourceURL = URL(fileURLWithPath: fullRemotePath)
            let destURL = URL(fileURLWithPath: localPath)
            
            if fileManager.fileExists(atPath: localPath) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
            progress(1.0)
        } catch {
            throw ProtocolError.downloadFailed(error)
        }
    }
    
    func uploadFile(serverID: String, localPath: String, remotePath: String, progress: @escaping (Double) -> Void) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        let mountPath = connection.config.getMountPath()
        let fullRemotePath = Utils.shared.joinPath(mountPath, remotePath)
        
        do {
            let fileManager = FileManager.default
            let sourceURL = URL(fileURLWithPath: localPath)
            let destURL = URL(fileURLWithPath: fullRemotePath)
            
            let destDir = destURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: destDir.path) {
                try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            if fileManager.fileExists(atPath: fullRemotePath) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
            progress(1.0)
        } catch {
            throw ProtocolError.uploadFailed(error)
        }
    }
    
    func cancelTransfer(serverID: String, transferID: String) throws {
        Logger.shared.debug("取消SMB传输: \(transferID)")
    }
    
    func ping(serverID: String) -> Bool {
        guard let connection = getConnection(serverID: serverID) else { return false }
        let mountPath = connection.config.getMountPath()
        return DiskAPI.shared.isMounted(mountPath)
    }
    
    func getCapacity(serverID: String) -> CapacityInfo? {
        guard let connection = getConnection(serverID: serverID) else { return nil }
        
        let mountPath = connection.config.getMountPath()
        let result = DiskAPI.shared.getDiskInfo(at: mountPath)
        
        switch result {
        case .success(let diskInfo):
            return CapacityInfo(
                total: diskInfo.totalSize,
                used: diskInfo.usedSize,
                free: diskInfo.freeSize
            )
        case .failure:
            return nil
        }
    }
    
    func getConfigSchema() -> ConfigSchema {
        return ConfigSchema(sections: [
            ConfigSection(
                name: "基础连接",
                fields: [
                    ConfigField(
                        key: "url",
                        label: "服务器地址",
                        type: .url,
                        defaultValue: "",
                        placeholder: "smb://server/share",
                        isRequired: true
                    ),
                    ConfigField(
                        key: "username",
                        label: "用户名",
                        type: .text,
                        defaultValue: "",
                        placeholder: "用户名",
                        isRequired: true
                    ),
                    ConfigField(
                        key: "password",
                        label: "密码",
                        type: .password,
                        defaultValue: "",
                        placeholder: "密码",
                        isRequired: true,
                        isSecure: true
                    )
                ]
            ),
            ConfigSection(
                name: "高级设置",
                fields: [
                    ConfigField(
                        key: "domain",
                        label: "域",
                        type: .text,
                        defaultValue: "",
                        placeholder: "WORKGROUP"
                    ),
                    ConfigField(
                        key: "protocolVersion",
                        label: "协议版本",
                        type: .dropdown,
                        defaultValue: "3.0",
                        options: [
                            ConfigOption(label: "SMB 3.0", value: "3.0"),
                            ConfigOption(label: "SMB 2.1", value: "2.1"),
                            ConfigOption(label: "SMB 1.0", value: "1.0")
                        ]
                    ),
                    ConfigField(
                        key: "signing",
                        label: "启用签名",
                        type: .boolean,
                        defaultValue: false
                    ),
                    ConfigField(
                        key: "encryption",
                        label: "启用加密",
                        type: .boolean,
                        defaultValue: false
                    ),
                    ConfigField(
                        key: "timeout",
                        label: "超时时间(秒)",
                        type: .number,
                        defaultValue: 30,
                        validation: ConfigValidation(minValue: 5, maxValue: 120)
                    )
                ]
            )
        ])
    }
    
    func validateConfig(_ config: [String: Any]) -> [String: String] {
        var errors: [String: String] = [:]
        
        if let url = config["url"] as? String, url.isEmpty {
            errors["url"] = "服务器地址不能为空"
        }
        
        if let username = config["username"] as? String, username.isEmpty {
            errors["username"] = "用户名不能为空"
        }
        
        if let password = config["password"] as? String, password.isEmpty {
            errors["password"] = "密码不能为空"
        }
        
        if let timeout = config["timeout"] as? Int, timeout < 5 || timeout > 120 {
            errors["timeout"] = "超时时间应在5-120秒之间"
        }
        
        return errors
    }
    
    private func getConnection(serverID: String) -> SMBConnection? {
        var connection: SMBConnection?
        queue.sync {
            connection = connections[serverID]
        }
        return connection
    }
}

class SMBConnection {
    let config: ServerConfig
    var isConnected: Bool = false
    
    init(config: ServerConfig) {
        self.config = config
        self.isConnected = true
    }
    
    func disconnect() {
        isConnected = false
    }
}
