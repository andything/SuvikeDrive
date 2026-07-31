//
//  WebDAVMounter.swift
//  SuvikeDrive
//
//  模块：WebDAV挂载管理器
//  功能：使用 WebDAV 客户端 + 符号链接让 Finder 显示
//  依赖：WebDAVHelper、CacheManager、SymlinkManager、NetworkManager
//

@preconcurrency import Foundation

// MARK: - 卸载模式定义
enum UnmountMode {
    case onlySymlink
    case removeCache
}

// MARK: - 同步任务令牌
final class SyncTaskToken {
    var isCancelled: Bool = false
}

final class WebDAVMounter {
    static let shared = WebDAVMounter()
    private init() {}
    
    private let cacheManager = CacheManager.shared
    private let symlinkManager = SymlinkManager.shared
    private var syncTaskMap: [String: SyncTaskToken] = [:]
    private let taskLock = NSLock()
    
    // MARK: - 同步配置
    private let maxSyncDepth = 6
    private let maxFilesPerLevel = 300
    private let maxConcurrentDownloads = 3
    private let downloadTimeout: TimeInterval = 60
    private let downloadMaxRetries = 3
    private let downloadQueue = OperationQueue()
    
    private func setupDownloadQueue() {
        downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads
        downloadQueue.qualityOfService = .utility
    }
    
    // MARK: - 挂载
    func mount(serverID: String, config: ServerConfig, connection: WebDAVConnection) throws {
        let fullRemoteURL = buildFullURL(config: config)
        let cacheDir = cacheManager.getServerMirrorDirectory(serverID: serverID, serverName: config.name)
        
        Logger.shared.info("==========连接信息==========", module: "WebDAVMounter")
        Logger.shared.info("服务器ID: \(serverID)", module: "WebDAVMounter")
        Logger.shared.info("显示名称: \(config.name)", module: "WebDAVMounter")
        Logger.shared.info("目标地址: \(fullRemoteURL)", module: "WebDAVMounter")
        Logger.shared.info("缓存目录: \(cacheDir.path)", module: "WebDAVMounter")
        Logger.shared.info("============================", module: "WebDAVMounter")
        
        try testConnection(url: fullRemoteURL, config: config)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let symlinkPath = try symlinkManager.createSymlink(
            linkName: WebDAVHelper.sanitizeVolumeName(config.name),
            targetPath: cacheDir.path
        )
        
        if !connection.isMounted {
            let token = SyncTaskToken()
            taskLock.lock()
            syncTaskMap[serverID] = token
            taskLock.unlock()
            startCacheSync(serverID: serverID, config: config, cacheDir: cacheDir, token: token)
        }
        
        connection.isMounted = true
        connection.mountPath = symlinkPath
        
        Logger.shared.info("✅ 连接成功: \(symlinkPath)", module: "WebDAVMounter")
        
        DispatchQueue.main.async {
            EventBus.shared.publish(MountCompleted(serverID: serverID, mountPath: symlinkPath))
            WebDAVHelper.refreshFinder()
        }
    }
    
    // MARK: - 断开连接
    func unmount(serverID: String, connection: WebDAVConnection, mode: UnmountMode = .onlySymlink) throws {
        guard let mountPath = connection.mountPath else {
            throw NSError(domain: "WebDAVMounter", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "无挂载路径"])
        }
        
        connection.disconnect()
        Logger.shared.info("[\(serverID)] WebDAV 连接已断开", module: "WebDAVMounter")
        
        NetworkManager.shared.cancelAllTasks(serverID: serverID)
        Logger.shared.info("[\(serverID)] 已取消所有网络任务", module: "WebDAVMounter")
        
        downloadQueue.cancelAllOperations()
        Logger.shared.info("[\(serverID)] 已取消下载队列", module: "WebDAVMounter")
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop")
        let symlinkPath = desktop.appendingPathComponent(connection.config.name).path
        if FileManager.default.fileExists(atPath: symlinkPath) {
            try? FileManager.default.removeItem(atPath: symlinkPath)
            Logger.shared.info("✅ 桌面符号链接已删除: \(symlinkPath)", module: "WebDAVMounter")
        }
        
        taskLock.lock()
        if let token = syncTaskMap[serverID] {
            token.isCancelled = true
            Logger.shared.info("[\(serverID)] 发送终止信号，停止缓存同步任务", module: "WebDAVMounter")
        }
        taskLock.unlock()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        try? symlinkManager.removeSymlink(at: mountPath)
        
        let cacheDir = cacheManager.getServerMirrorDirectory(serverID: serverID, serverName: connection.config.name)
        if mode == .removeCache {
            do {
                try FileManager.default.removeItem(at: cacheDir)
                Logger.shared.info("[\(serverID)] 本地缓存目录已清除: \(cacheDir.path)", module: "WebDAVMounter")
            } catch {
                Logger.shared.warning("[\(serverID)] 缓存目录删除失败: \(error.localizedDescription)", module: "WebDAVMounter")
            }
        }
        
        taskLock.lock()
        syncTaskMap.removeValue(forKey: serverID)
        taskLock.unlock()
        
        connection.isMounted = false
        connection.mountPath = nil
        
        Logger.shared.info("✅ 断开连接完成: \(mountPath)，模式:\(mode)", module: "WebDAVMounter")
        
        DispatchQueue.main.async {
            EventBus.shared.publish(UnmountCompleted(serverID: serverID))
            WebDAVHelper.refreshFinder()
            self.flushFinderIcons()
        }
    }
    
    // MARK: - 取消同步任务
    func cancelSyncTask(serverID: String) {
        taskLock.lock()
        if let token = syncTaskMap[serverID] {
            token.isCancelled = true
            Logger.shared.info("[\(serverID)] 发送终止信号，停止缓存同步任务", module: "WebDAVMounter")
        }
        taskLock.unlock()
        
        downloadQueue.cancelAllOperations()
        Logger.shared.info("[\(serverID)] 下载队列已取消", module: "WebDAVMounter")
    }
    
    // MARK: - 缓存同步（后台队列）
    private func startCacheSync(serverID: String, config: ServerConfig, cacheDir: URL, token: SyncTaskToken) {
        setupDownloadQueue()
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.syncRemoteFiles(serverID: serverID, config: config, cacheDir: cacheDir, token: token)
        }
    }
    
    // MARK: - 两阶段同步：只创建目录结构和占位文件
    private func syncRemoteFiles(serverID: String, config: ServerConfig, cacheDir: URL, token: SyncTaskToken) {
        Logger.shared.info("开始缓存同步: \(serverID)", module: "WebDAVMounter")
        
        Logger.shared.info("[\(serverID)] 第一阶段：创建目录结构...", module: "WebDAVMounter")
        syncDirectoryStructure(
            serverID: serverID,
            config: config,
            remotePath: "/",
            localBaseDir: cacheDir,
            depth: 0,
            token: token
        )
        
        if token.isCancelled {
            Logger.shared.info("[\(serverID)] 同步任务已取消", module: "WebDAVMounter")
            return
        }
        
        Logger.shared.info("[\(serverID)] 第二阶段：创建占位文件...", module: "WebDAVMounter")
        syncPlaceholderFiles(
            serverID: serverID,
            config: config,
            remotePath: "/",
            localBaseDir: cacheDir,
            depth: 0,
            token: token
        )
        
        Logger.shared.info("[\(serverID)] 缓存同步完成（仅占位文件）", module: "WebDAVMounter")
    }
    
    // MARK: - 第一阶段：只创建目录结构
    private func syncDirectoryStructure(
        serverID: String,
        config: ServerConfig,
        remotePath: String,
        localBaseDir: URL,
        depth: Int,
        token: SyncTaskToken
    ) {
        if token.isCancelled { return }
        if depth > maxSyncDepth {
            Logger.shared.debug("[\(serverID)] 达到最大深度 \(maxSyncDepth): \(remotePath)", module: "WebDAVMounter")
            return
        }
        
        do {
            let files = try listRemoteFiles(config: config, path: remotePath)
            let limitedFiles = files.prefix(maxFilesPerLevel)
            
            for file in limitedFiles {
                if token.isCancelled { return }
                
                let fullRemotePath = remotePath == "/" ? "/" + file.name : remotePath + "/" + file.name
                let localURL = cacheManager.getMirrorFilePath(
                    serverID: serverID,
                    serverName: config.name,
                    remotePath: fullRemotePath
                )
                
                if file.isDirectory {
                    if !FileManager.default.fileExists(atPath: localURL.path) {
                        try? FileManager.default.createDirectory(
                            at: localURL,
                            withIntermediateDirectories: true
                        )
                    }
                }
            }
        } catch {
            Logger.shared.error("创建目录结构失败 [\(remotePath)]: \(error)", module: "WebDAVMounter")
        }
    }
    
    // MARK: - 第二阶段：创建占位文件（空文件，不下载实际内容）
    private func syncPlaceholderFiles(
        serverID: String,
        config: ServerConfig,
        remotePath: String,
        localBaseDir: URL,
        depth: Int,
        token: SyncTaskToken
    ) {
        if token.isCancelled { return }
        if depth > maxSyncDepth {
            Logger.shared.debug("[\(serverID)] 达到最大深度 \(maxSyncDepth): \(remotePath)", module: "WebDAVMounter")
            return
        }
        
        do {
            let files = try listRemoteFiles(config: config, path: remotePath)
            let limitedFiles = files.prefix(maxFilesPerLevel)
            
            let directories = limitedFiles.filter { $0.isDirectory }
            let fileItems = limitedFiles.filter { !$0.isDirectory }
            
            for dir in directories {
                if token.isCancelled { return }
                syncPlaceholderFiles(
                    serverID: serverID,
                    config: config,
                    remotePath: dir.path,
                    localBaseDir: localBaseDir,
                    depth: depth + 1,
                    token: token
                )
            }
            
            for file in fileItems {
                if token.isCancelled { return }
                
                let fullRemotePath = remotePath == "/" ? "/" + file.name : remotePath + "/" + file.name
                let localURL = cacheManager.getMirrorFilePath(
                    serverID: serverID,
                    serverName: config.name,
                    remotePath: fullRemotePath
                )
                
                if !FileManager.default.fileExists(atPath: localURL.path) {
                    let parentDir = localURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: parentDir.path) {
                        try? FileManager.default.createDirectory(
                            at: parentDir,
                            withIntermediateDirectories: true
                        )
                    }
                    
                    createPlaceholderFile(at: localURL, fileInfo: file)
                }
            }
        } catch {
            Logger.shared.error("创建占位文件失败 [\(remotePath)]: \(error)", module: "WebDAVMounter")
        }
    }
    
    // MARK: - 创建占位文件
    private func createPlaceholderFile(at url: URL, fileInfo: WebDAVFileInfo) {
        let success = FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        
        if success {
            let metadata: [String: Any] = [
                "name": fileInfo.name,
                "path": fileInfo.path,
                "size": fileInfo.size,
                "isDirectory": fileInfo.isDirectory,
                "lastModified": fileInfo.lastModified,
                "isPlaceholder": true,
                "downloaded": false
            ]
            
            let metadataURL = url.appendingPathExtension("metadata")
            if let metadataData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
                try? metadataData.write(to: metadataURL)
            }
            
            Logger.shared.debug("📄 创建占位文件: \(url.lastPathComponent)", module: "WebDAVMounter")
        }
    }
    
    // MARK: - 检查文件是否已下载
    func isFileDownloaded(serverID: String, remotePath: String) -> Bool {
        let localURL = cacheManager.getMirrorFilePath(serverID: serverID, remotePath: remotePath)
        let metadataURL = localURL.appendingPathExtension("metadata")
        
        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
           let downloaded = metadata["downloaded"] as? Bool {
            return downloaded && FileManager.default.fileExists(atPath: localURL.path)
        }
        return false
    }
    
    // MARK: - 下载实际文件内容（用户点击下载时调用）
    func downloadActualFile(serverID: String, config: ServerConfig, remotePath: String) throws {
        let localURL = cacheManager.getMirrorFilePath(
            serverID: serverID,
            serverName: config.name,
            remotePath: remotePath
        )
        
        try? FileManager.default.removeItem(at: localURL)
        try? FileManager.default.removeItem(at: localURL.appendingPathExtension("metadata"))
        
        let parentDir = localURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        try downloadFile(config: config, remotePath: remotePath, localURL: localURL)
        
        let metadata: [String: Any] = [
            "name": localURL.lastPathComponent,
            "path": remotePath,
            "downloaded": true,
            "downloadTime": Date().timeIntervalSince1970,
            "size": (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        ]
        let metadataData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try? metadataData?.write(to: localURL.appendingPathExtension("metadata"))
        
        Logger.shared.info("✅ 文件已下载: \(localURL.path)", module: "WebDAVMounter")
    }
    
    // MARK: - 远程文件操作
    
    func listRemoteFiles(config: ServerConfig, path: String) throws -> [WebDAVFileInfo] {
        var normalizedPath = path
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        if normalizedPath != "/" && normalizedPath.hasSuffix("/") {
            normalizedPath = String(normalizedPath.dropLast())
        }
        
        let baseURL = buildFullURL(config: config)
        let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let pathComponent = normalizedPath == "/" ? "" : normalizedPath
        let urlString = baseURLString + pathComponent
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"])
        }
        
        var headers: [String: String] = [:]
        headers["Depth"] = "1"
        headers["Content-Type"] = "application/xml; charset=utf-8"
        
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        let requestBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:">
          <prop>
            <resourcetype/>
            <displayname/>
            <getcontentlength/>
            <getlastmodified/>
          </prop>
        </propfind>
        """
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: [WebDAVFileInfo] = []
        var requestError: Error?
        
        NetworkManager.shared.request(
            url: url,
            method: .propfind,
            headers: headers,
            body: requestBody.data(using: .utf8),
            timeout: 30
        ) { networkResult in
            switch networkResult {
            case .success(let data):
                let delegate = WebDAVParserDelegate()
                delegate.setCurrentPath(normalizedPath)
                let parser = XMLParser(data: data)
                parser.delegate = delegate
                parser.parse()
                result = delegate.files
            case .failure(let error):
                if case .httpError(let code, _) = error, code == 404 {
                    requestError = NSError(domain: "WebDAVMounter", code: 404,
                                           userInfo: [NSLocalizedDescriptionKey: "路径不存在"])
                } else {
                    requestError = error
                }
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
        
        if let error = requestError {
            throw error
        }
        
        return result
    }
    
    func downloadFile(config: ServerConfig, remotePath: String, localURL: URL) throws {
        let baseURL = buildFullURL(config: config)
        let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var normalizedPath = remotePath
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        let urlString = baseURLString + normalizedPath
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"])
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?
        
        try? FileManager.default.removeItem(at: localURL)
        
        NetworkManager.shared.download(
            url: url,
            destination: localURL
        ) { _ in
            // 进度回调
        } completion: { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                downloadError = error
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + downloadTimeout)
        
        if let error = downloadError {
            throw error
        }
    }
    
    // MARK: - 上传文件
    func uploadFile(config: ServerConfig, localURL: URL, remotePath: String, progress: @escaping (Double) -> Void) throws {
        let baseURL = buildFullURL(config: config)
        let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var normalizedPath = remotePath
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        let urlString = baseURLString + normalizedPath
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"])
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/octet-stream"
        headers["Content-Length"] = String(fileSize)
        
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var uploadError: Error?
        var uploadSuccess = false
        
        NetworkManager.shared.upload(
            url: url,
            file: localURL,
            headers: headers
        ) { uploadProgress in
            progress(uploadProgress)
        } completion: { result in
            switch result {
            case .success:
                uploadSuccess = true
            case .failure(let error):
                uploadError = error
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 600)
        
        if let error = uploadError {
            throw error
        }
        
        if !uploadSuccess {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "上传失败: 未知错误"])
        }
    }
    
    // MARK: - 创建远程目录
    func createRemoteDirectory(config: ServerConfig, path: String) throws {
        let baseURL = buildFullURL(config: config)
        let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var normalizedPath = path
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        if !normalizedPath.hasSuffix("/") {
            normalizedPath = normalizedPath + "/"
        }
        let urlString = baseURLString + normalizedPath
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"])
        }
        
        var headers: [String: String] = [:]
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var createError: Error?
        var createSuccess = false
        
        NetworkManager.shared.request(
            url: url,
            method: .mkcol,
            headers: headers,
            timeout: 30
        ) { result in
            switch result {
            case .success:
                createSuccess = true
            case .failure(let error):
                if case .httpError(let statusCode, _) = error, statusCode == 405 {
                    createSuccess = true
                } else {
                    createError = error
                }
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
        
        if let error = createError {
            throw error
        }
        
        if !createSuccess {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "创建目录失败"])
        }
    }
    
    // MARK: - 测试连接
    private func testConnection(url: String, config: ServerConfig) throws {
        guard let url = URL(string: url) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(url)"])
        }
        
        var headers: [String: String] = [:]
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var connectionError: Error?
        
        NetworkManager.shared.request(
            url: url,
            method: .options,
            headers: headers,
            timeout: 15
        ) { result in
            switch result {
            case .success:
                Logger.shared.info("✅ 服务器可达", module: "WebDAVMounter")
            case .failure(let error):
                if case .httpError(let statusCode, _) = error, statusCode == 401 {
                    Logger.shared.info("✅ 服务器可达（需认证）", module: "WebDAVMounter")
                } else {
                    connectionError = error
                }
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 20)
        
        if let error = connectionError {
            throw error
        }
    }
    
    // MARK: - 辅助方法
    func buildFullURL(config: ServerConfig) -> String {
        var baseURL = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let useHTTPS = config.getProtocolConfig(key: "https", defaultValue: true)
        let protocolPrefix = useHTTPS ? "https://" : "http://"
        
        if baseURL.hasPrefix("https://") {
            baseURL = String(baseURL.dropFirst(8))
        } else if baseURL.hasPrefix("http://") {
            baseURL = String(baseURL.dropFirst(7))
        }
        
        var host = baseURL
        var path = ""
        if let slashIndex = baseURL.firstIndex(of: "/") {
            host = String(baseURL[..<slashIndex])
            path = String(baseURL[slashIndex...])
        }
        
        let port = config.getPort()
        let defaultPort = useHTTPS ? 443 : 80
        
        var fullURL = protocolPrefix + host
        if port != defaultPort {
            fullURL += ":\(port)"
        }
        
        if !path.isEmpty {
            if !path.hasPrefix("/") {
                path = "/" + path
            }
            if !path.hasSuffix("/") {
                path = path + "/"
            }
            fullURL += path
        } else {
            fullURL += "/"
        }
        
        return fullURL
    }
    
    private func flushFinderIcons() {
        let script = """
        tell application "Finder"
            update every item
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
    
    // MARK: - 移动/重命名远程文件
    func moveRemoteFile(config: ServerConfig, from: String, to: String) throws {
        let baseURL = buildFullURL(config: config)
        let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var fromPath = from
        var toPath = to
        
        if !fromPath.hasPrefix("/") {
            fromPath = "/" + fromPath
        }
        if !toPath.hasPrefix("/") {
            toPath = "/" + toPath
        }
        
        let fromURLString = baseURLString + fromPath
        let toURLString = baseURLString + toPath
        
        guard let fromURL = URL(string: fromURLString),
              let toURL = URL(string: toURLString) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])
        }
        
        var headers: [String: String] = [:]
        headers["Destination"] = toURL.absoluteString
        headers["Overwrite"] = "T"
        
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var moveError: Error?
        var moveSuccess = false
        
        NetworkManager.shared.request(
            url: fromURL,
            method: .move,
            headers: headers,
            timeout: 60
        ) { result in
            switch result {
            case .success:
                moveSuccess = true
            case .failure(let error):
                if case .httpError(let statusCode, _) = error,
                   [200, 201, 204].contains(statusCode) {
                    moveSuccess = true
                } else {
                    moveError = error
                }
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
        
        if let error = moveError {
            throw error
        }
        
        if !moveSuccess {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "移动/重命名失败"])
        }
    }
    
    // MARK: - 删除远程文件
    func deleteRemoteFile(config: ServerConfig, path: String) throws {
        let baseURL = buildFullURL(config: config)
        let baseURLString = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var filePath = path
        if !filePath.hasPrefix("/") {
            filePath = "/" + filePath
        }
        let urlString = baseURLString + filePath
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"])
        }
        
        var headers: [String: String] = [:]
        if let username = config.username, let password = config.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64String = authData.base64EncodedString()
                headers["Authorization"] = "Basic \(base64String)"
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var deleteError: Error?
        var deleteSuccess = false
        
        NetworkManager.shared.request(
            url: url,
            method: .delete,
            headers: headers,
            timeout: 60
        ) { result in
            switch result {
            case .success:
                deleteSuccess = true
            case .failure(let error):
                if case .httpError(let statusCode, _) = error, statusCode == 404 {
                    deleteSuccess = true
                } else {
                    deleteError = error
                }
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 60)
        
        if let error = deleteError {
            throw error
        }
        
        if !deleteSuccess {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "删除失败"])
        }
    }
    
    // MARK: - 删除远程目录（递归）
    func deleteRemoteDirectory(config: ServerConfig, path: String) throws {
        let items = try listRemoteFiles(config: config, path: path)
        for item in items {
            if item.isDirectory {
                try deleteRemoteDirectory(config: config, path: item.path)
            } else {
                try deleteRemoteFile(config: config, path: item.path)
            }
        }
        try deleteRemoteFile(config: config, path: path)
    }
    
    // MARK: - 下载带重试
    private func downloadFileWithRetry(
        config: ServerConfig,
        remotePath: String,
        localURL: URL
    ) throws {
        var lastError: Error?
        var attempt = 0
        
        while attempt < downloadMaxRetries {
            attempt += 1
            do {
                try downloadFile(config: config, remotePath: remotePath, localURL: localURL)
                Logger.shared.debug("下载文件: \(remotePath)", module: "WebDAVMounter")
                return
            } catch {
                lastError = error
                let isTimeout = (error as NSError).code == NSURLErrorTimedOut
                let isConnectionLost = (error as NSError).code == NSURLErrorNetworkConnectionLost
                
                if isTimeout || isConnectionLost {
                    Logger.shared.warning("下载失败 (尝试 \(attempt)/\(downloadMaxRetries)): \(remotePath)", module: "WebDAVMounter")
                    let delay = pow(2.0, Double(attempt)) * 1.0
                    Thread.sleep(forTimeInterval: delay)
                } else {
                    throw error
                }
            }
        }
        
        throw lastError ?? NSError(domain: "WebDAVMounter", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "下载失败: \(remotePath)"])
    }
    
    // MARK: - 挂载到 Finder
    func mountViaFinder(config: ServerConfig) throws {
        let url = buildFullURL(config: config)
        let username = config.username ?? ""
        let password = config.password ?? ""
        let port = config.getPort()
        let host = URL(string: url)?.host ?? "www.yiqipro.com"
        
        let mountPointName = "\(host)_\(port)"
        let mountPath = "/Volumes/\(mountPointName)"
        
        if !FileManager.default.fileExists(atPath: mountPath) {
            try FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)
        }
        
        let webdavPath: String = config.getProtocolConfig(key: "webdavPath", defaultValue: "/")
        let normalizedPath = webdavPath.hasPrefix("/") ? webdavPath : "/" + webdavPath
        
        var fullURL = url
        if normalizedPath != "/" {
            fullURL += normalizedPath
        }
        
        var authURL = fullURL
        if !username.isEmpty && !password.isEmpty {
            let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            
            if let urlComponents = URLComponents(string: fullURL) {
                var components = urlComponents
                components.user = encodedUsername
                components.password = encodedPassword
                if let urlWithAuth = components.string {
                    authURL = urlWithAuth
                }
            }
        }
        
        let script = """
        do shell script "/sbin/mount_webdav '\(authURL)' '\(mountPath)'" with administrator privileges
        """
        
        var error: NSDictionary?
        let scriptObject = NSAppleScript(source: script)
        _ = scriptObject?.executeAndReturnError(&error)
        
        if let error = error {
            throw NSError(domain: "WebDAVMounter", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "挂载失败: \(error)"])
        }
    }
    
    func unmountViaFinder(volumeName: String, port: Int) {
        let host = "www.yiqipro.com"
        let mountPointName = "\(host)_\(port)"
        
        let script = """
        tell application "Finder"
            try
                eject (every disk whose name is "\(mountPointName)")
            end try
        end tell
        """
        
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let desktop = home.appendingPathComponent("Desktop")
            let symlinkPath = desktop.appendingPathComponent(volumeName).path
            if FileManager.default.fileExists(atPath: symlinkPath) {
                try FileManager.default.removeItem(atPath: symlinkPath)
            }
        } catch {
            Logger.shared.warning("删除桌面符号链接失败: \(error)", module: "WebDAVMounter")
        }
    }
}

// MARK: - WebDAV 文件信息
struct WebDAVFileInfo {
    var path: String = ""
    var name: String = ""
    var size: Int64 = 0
    var contentType: String = ""
    var isDirectory: Bool = false
    var lastModified: String = ""
}

// MARK: - WebDAV XML 解析器
@preconcurrency
final class WebDAVParserDelegate: NSObject, XMLParserDelegate {
    private(set) var files: [WebDAVFileInfo] = []
    
    private var currentDirectoryName: String = ""
    private var currentRequestPath: String = ""
    private var currentRequestPathEncoded: String = ""
    private var currentFile = WebDAVFileInfo()
    private var currentElement = ""
    private var currentString = ""
    private var currentElementPath: [String] = []
    private var isInResponse = false
    private var isDirectory = false
    private var lastHref = ""
    
    func setCurrentPath(_ path: String) {
        var normalizedPath = path
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        if normalizedPath != "/" && normalizedPath.hasSuffix("/") {
            normalizedPath = String(normalizedPath.dropLast())
        }
        currentRequestPath = normalizedPath
        
        if normalizedPath == "/" {
            currentDirectoryName = ""
        } else {
            currentDirectoryName = (normalizedPath as NSString).lastPathComponent
        }
        currentRequestPathEncoded = normalizedPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedPath
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentString = ""
        currentElementPath.append(elementName)
        
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        
        if localName == "response" {
            isInResponse = true
            isDirectory = false
            currentFile = WebDAVFileInfo()
        }
        if localName == "collection" {
            isDirectory = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentString += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentString.trimmingCharacters(in: .whitespacesAndNewlines)
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        
        _ = currentElementPath.popLast()
        guard isInResponse else { return }
        
        switch localName {
        case "href":
            currentFile.path = trimmed
        case "displayname":
            var displayName = trimmed
            displayName = decodeHTMLEntities(displayName)
            displayName = decodeURLString(displayName)
            currentFile.name = displayName
        case "getcontentlength":
            currentFile.size = Int64(trimmed) ?? 0
        case "getcontenttype":
            currentFile.contentType = trimmed
        case "resourcetype":
            if trimmed.contains("collection") {
                isDirectory = true
            }
        case "getlastmodified":
            currentFile.lastModified = trimmed
        case "response":
            if isInResponse {
                currentFile.isDirectory = isDirectory
                
                let href = currentFile.path
                var extractedName = ""
                var name = href
                if name.hasPrefix("/") { name = String(name.dropFirst()) }
                if name.hasSuffix("/") { name = String(name.dropLast()) }
                let components = name.components(separatedBy: "/")
                if let last = components.last, !last.isEmpty {
                    extractedName = decodeURLString(last)
                } else if !name.isEmpty {
                    extractedName = decodeURLString(name)
                }
                
                if currentFile.name.isEmpty {
                    currentFile.name = extractedName
                }
                
                let shouldSkip = checkIfRootDirectory(
                    href: href,
                    displayName: currentFile.name,
                    extractedName: extractedName,
                    isDirectory: isDirectory
                )
                
                if shouldSkip {
                    isInResponse = false
                    return
                }
                
                if currentFile.name.isEmpty {
                    currentFile.name = "未命名"
                }
                
                if !currentFile.path.isEmpty {
                    currentFile.path = decodeURLString(currentFile.path)
                }
                
                files.append(currentFile)
                isInResponse = false
                isDirectory = false
                currentFile = WebDAVFileInfo()
            }
        default:
            break
        }
    }
    
    private func checkIfRootDirectory(href: String, displayName: String, extractedName: String, isDirectory: Bool) -> Bool {
        if href == "/" || href == "./" || href.isEmpty { return true }
        if currentRequestPath == "/" { return false }
        
        if !currentDirectoryName.isEmpty {
            if displayName == currentDirectoryName { return true }
            if extractedName == currentDirectoryName { return true }
        }
        
        var hrefClean = href
        if hrefClean.hasPrefix("/") { hrefClean = String(hrefClean.dropFirst()) }
        if hrefClean.hasSuffix("/") { hrefClean = String(hrefClean.dropLast()) }
        let hrefDecoded = decodeURLString(hrefClean)
        
        var pathClean = currentRequestPath
        if pathClean.hasPrefix("/") { pathClean = String(pathClean.dropFirst()) }
        if pathClean.hasSuffix("/") { pathClean = String(pathClean.dropLast()) }
        
        if hrefDecoded == pathClean { return true }
        return false
    }
    
    private func decodeURLString(_ string: String) -> String {
        var result = string
        var previousResult = ""
        
        while result != previousResult {
            previousResult = result
            if let decoded = result.removingPercentEncoding {
                result = decoded
            } else {
                break
            }
        }
        
        return result
    }
    
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'",
            "&nbsp;": " ", "&#xA;": "", "&#xD;": ""
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
