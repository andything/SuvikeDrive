//
//  FTP.swift
//  SuvikeDrive
//
//  功能: FTP协议模块
//

import Foundation

class FTPModule: ProtocolModule {
    let type: ProtocolType = .ftp
    let name: String = "FTP"
    let version: String = "1.0.0"
    let capabilities: ProtocolCapabilities = [
        .fileList, .upload, .download, .delete, .move, .copy,
        .createDirectory, .rename, .permissions, .resumeDownload,
        .resumeUpload, .heartbeat, .capacity, .ping
    ]
    
    private var connections: [String: FTPConnection] = [:]
    private let queue = DispatchQueue(label: "com.suvikedrive.ftp")
    
    func initialize() throws {
        Logger.shared.debug("FTP协议模块初始化")
    }
    
    func shutdown() throws {
        queue.sync {
            for (serverID, connection) in connections {
                connection.disconnect()
                Logger.shared.debug("FTP连接已关闭: \(serverID)")
            }
            connections.removeAll()
        }
    }
    
    func connect(serverID: String, config: ServerConfig) throws {
        queue.sync {
            if connections[serverID] != nil {
                return
            }
            let connection = FTPConnection(config: config)
            connections[serverID] = connection
            Logger.shared.debug("FTP连接已建立: \(serverID)")
        }
    }
    
    func disconnect(serverID: String) throws {
        queue.sync {
            if let connection = connections[serverID] {
                connection.disconnect()
                connections.removeValue(forKey: serverID)
                Logger.shared.debug("FTP连接已断开: \(serverID)")
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
        
        var options: [String: Any] = [:]
        options["mode"] = connection.config.getProtocolConfig(key: "mode", defaultValue: "passive")
        options["tls"] = connection.config.getProtocolConfig(key: "tls", defaultValue: false)
        options["encoding"] = connection.config.getProtocolConfig(key: "encoding", defaultValue: "UTF-8")
        
        DiskAPI.shared.mount(
            url: connection.config.getFullURL(),
            mountPath: mountPath,
            credentials: credentials,
            options: options
        ) { result in
            switch result {
            case .success:
                Logger.shared.debug("FTP挂载成功: \(serverID) -> \(mountPath)")
            case .failure(let error):
                Logger.shared.error("FTP挂载失败: \(error.localizedDescription)")
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
                Logger.shared.debug("FTP卸载成功: \(serverID)")
            case .failure(let error):
                Logger.shared.error("FTP卸载失败: \(error.localizedDescription)")
            }
        }
    }
    
    func isMounted(serverID: String) -> Bool {
        guard let connection = getConnection(serverID: serverID) else { return false }
        return DiskAPI.shared.isMounted(connection.config.getMountPath())
    }
    
    private func cacheKey(serverID: String, path: String) -> String {
        return "ftp_\(serverID)_\(path)"
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
            CacheManager.shared.invalidateFileList(prefix: "ftp_\(serverID)_")
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
        Logger.shared.debug("取消FTP传输: \(transferID)")
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
            ConfigSection(name: "基础连接", fields: [
                ConfigField(key: "url", label: "服务器地址", type: .url, defaultValue: "", placeholder: "ftp://server", isRequired: true),
                ConfigField(key: "username", label: "用户名", type: .text, defaultValue: "", placeholder: "用户名", isRequired: true),
                ConfigField(key: "password", label: "密码", type: .password, defaultValue: "", placeholder: "密码", isRequired: true, isSecure: true)
            ]),
            ConfigSection(name: "传输设置", fields: [
                ConfigField(key: "mode", label: "传输模式", type: .dropdown, defaultValue: "passive", options: [
                    ConfigOption(label: "被动模式 (PASV)", value: "passive"),
                    ConfigOption(label: "主动模式 (PORT)", value: "active")
                ]),
                ConfigField(key: "encoding", label: "字符编码", type: .dropdown, defaultValue: "UTF-8", options: [
                    ConfigOption(label: "UTF-8", value: "UTF-8"),
                    ConfigOption(label: "GB2312", value: "GB2312"),
                    ConfigOption(label: "ISO-8859-1", value: "ISO-8859-1")
                ])
            ]),
            ConfigSection(name: "安全设置", fields: [
                ConfigField(key: "tls", label: "启用TLS/SSL加密", type: .boolean, defaultValue: false),
                ConfigField(key: "verifySSL", label: "验证SSL证书", type: .boolean, defaultValue: true)
            ]),
            ConfigSection(name: "高级设置", fields: [
                ConfigField(key: "timeout", label: "超时时间(秒)", type: .number, defaultValue: 30, validation: ConfigValidation(minValue: 5, maxValue: 120)),
                ConfigField(key: "cacheEnabled", label: "启用缓存", type: .boolean, defaultValue: true)
            ])
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
    
    private func getConnection(serverID: String) -> FTPConnection? {
        var connection: FTPConnection?
        queue.sync {
            connection = connections[serverID]
        }
        return connection
    }
}

class FTPConnection {
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
