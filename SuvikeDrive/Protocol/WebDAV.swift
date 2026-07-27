//
//  WebDAV.swift
//  SuvikeDrive
//
//  功能: WebDAV协议模块
//

import Foundation

// MARK: - WebDAV 连接
class WebDAVConnection {
    let config: ServerConfig
    var isConnected: Bool = false
    var isMounted: Bool = false
    var mountPath: String?
    
    init(config: ServerConfig) {
        self.config = config
    }
    
    func disconnect() {
        isConnected = false
        isMounted = false
        mountPath = nil
    }
}

// MARK: - WebDAV 协议模块
class WebDAVModule: ProtocolModule {
    let type: ProtocolType = .webdav
    let name: String = "WebDAV"
    let version: String = "2.0.0"
    let capabilities: ProtocolCapabilities = [
        .fileList, .upload, .download, .delete, .move, .copy,
        .createDirectory, .permissions, .capacity, .ping
    ]
    
    private var connections: [String: WebDAVConnection] = [:]
    private let queue = DispatchQueue(label: "com.suvikedrive.webdav")
    
    func initialize() throws {}
    
    func shutdown() throws {
        queue.sync {
            for (_, connection) in connections {
                connection.disconnect()
            }
            connections.removeAll()
        }
    }
    
    func connect(serverID: String, config: ServerConfig) throws {
        queue.sync {
            if connections[serverID] != nil {
                return
            }
            let connection = WebDAVConnection(config: config)
            connection.isConnected = true
            connections[serverID] = connection
        }
    }
    
    func disconnect(serverID: String) throws {
        queue.sync {
            if let connection = connections[serverID] {
                connection.disconnect()
                connections.removeValue(forKey: serverID)
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
    
    // MARK: - 挂载入口
    func mount(serverID: String, mountPath: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        if connection.isMounted {
            return
        }
        
        let serverName = connection.config.name
        let rawUrl = connection.config.getFullURL()
        let username = connection.config.username ?? ""
        let password = connection.config.password ?? ""
        
        // 强制统一转为HTTPS地址，修复http 400报错
        let fixedUrl = normalizeHTTPSUrl(raw: rawUrl)
        
        do {
            let mountedPath = try mountWithOSAScriptOnly(
                serverName: serverName,
                url: fixedUrl,
                username: username,
                password: password,
                mountPath: mountPath
            )
            connection.isMounted = true
            connection.mountPath = mountedPath
        } catch {
            throw ProtocolError.mountFailed(error.localizedDescription)
        }
    }
    
    // MARK: 仅保留可用的 osascript Finder 挂载，删除失效 mount_webdav
    private func mountWithOSAScriptOnly(
        serverName: String,
        url: String,
        username: String,
        password: String,
        mountPath: String
    ) throws -> String {
        // 检测是否已挂载
        if let existingPath = findMountedVolume(serverName: serverName) {
            print("📁 卷已挂载: \(existingPath)")
            return existingPath
        }
        
        // AppleScript 完整转义函数
        func escapeAS(_ str: String) -> String {
            return str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let safeUrl = escapeAS(url)
        let safeUser = escapeAS(username)
        let safePwd = escapeAS(password)
        
        let script = """
        tell application "Finder"
            try
                mount volume "\(safeUrl)" as user name "\(safeUser)" with password "\(safePwd)"
                return "success"
            on error errMsg
                return "error:" & errMsg
            end try
        end tell
        """
        
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8) ?? ""
        
        if !errMsg.isEmpty {
            print("osascript执行错误: \(errMsg)")
            throw ProtocolError.mountFailed("Finder挂载脚本执行失败: \(errMsg)")
        }
        
        guard output == "success" else {
            print("osascript返回失败: \(output)")
            throw ProtocolError.mountFailed("挂载失败，返回信息：\(output)")
        }
        
        // 轮询等待挂载出现
        var attempts = 0
        while attempts < 10 {
            if let path = findMountedVolume(serverName: serverName) {
                print("✅ Finder挂载成功，真实路径：\(path)")
                return path
            }
            Thread.sleep(forTimeInterval: 1)
            attempts += 1
        }
        print("⚠️ 挂载命令执行成功，但未检测到挂载卷，返回预设路径")
        return mountPath
    }
    
    // MARK: URL标准化，强制HTTPS
    private func normalizeHTTPSUrl(raw: String) -> String {
        var urlStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // http替换https
        if urlStr.starts(with: "http://") {
            urlStr = urlStr.replacingOccurrences(of: "http://", with: "https://")
        }
        // 无协议自动补https
        if !urlStr.starts(with: "http://") && !urlStr.starts(with: "https://") {
            urlStr = "https://\(urlStr)"
        }
        return urlStr
    }
    
    // MARK: 查找 /Volumes 内挂载卷
    private func findMountedVolume(serverName: String) -> String? {
        guard let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else {
            return nil
        }
        
        let normalizedName = serverName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        for volume in volumes {
            let normalizedVolume = volume.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
            
            if normalizedVolume == normalizedName ||
               normalizedVolume.contains(normalizedName) ||
               normalizedName.contains(normalizedVolume) {
                let path = "/Volumes/\(volume)"
                if FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }
    
    // MARK: - 卸载逻辑（diskutil兼容）
    func unmount(serverID: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let mountPath = connection.mountPath else {
            throw ProtocolError.unmountFailed("未找到挂载路径")
        }
        
        let process = Process()
        process.launchPath = "/usr/sbin/diskutil"
        process.arguments = ["unmount", mountPath]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                connection.isMounted = false
                connection.mountPath = nil
                print("✅ 正常卸载成功: \(mountPath)")
            } else {
                // 强制卸载
                let forceProcess = Process()
                forceProcess.launchPath = "/usr/sbin/diskutil"
                forceProcess.arguments = ["unmount", "force", mountPath]
                try forceProcess.run()
                forceProcess.waitUntilExit()
                if forceProcess.terminationStatus == 0 {
                    connection.isMounted = false
                    connection.mountPath = nil
                    print("✅ 强制卸载成功: \(mountPath)")
                } else {
                    throw ProtocolError.unmountFailed("常规与强制卸载均失败")
                }
            }
        } catch {
            throw ProtocolError.unmountFailed(error.localizedDescription)
        }
    }
    
    func isMounted(serverID: String) -> Bool {
        var result = false
        queue.sync {
            result = connections[serverID]?.isMounted ?? false
        }
        return result
    }
    
    // MARK: - 文件列表（修复：补充标准PROPFIND XML Body）
    func listFiles(serverID: String, path: String) throws -> [FileInfo] {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let requestURL = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        // 修复缺失的请求体
        let propfindXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:allprop/>
        </D:propfind>
        """
        request.httpBody = propfindXML.data(using: .utf8)
        
        // Basic Auth
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[FileInfo], Error> = .failure(ProtocolError.notSupported)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = .failure(error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 207 else {
                result = .failure(ProtocolError.notSupported)
                return
            }
            
            guard let data = data else {
                result = .failure(ProtocolError.notSupported)
                return
            }
            
            let files = self.parsePropfindResponse(data: data)
            result = .success(files)
        }
        
        task.resume()
        semaphore.wait()
        
        return try result.get()
    }
    
    // XML解析
    private func parsePropfindResponse(data: Data) -> [FileInfo] {
        var files: [FileInfo] = []
        
        guard let xml = try? XMLDocument(data: data) else {
            return files
        }
        
        let root = xml.rootElement()
        let responseElements = root?.elements(forName: "response") ?? []
        
        for response in responseElements {
            let href = response.elements(forName: "href").first?.stringValue ?? ""
            let propstat = response.elements(forName: "propstat").first
            let prop = propstat?.elements(forName: "prop").first
            
            let displayName = prop?.elements(forName: "displayname").first?.stringValue ?? ""
            let lastModified = prop?.elements(forName: "getlastmodified").first?.stringValue ?? ""
            let contentLength = prop?.elements(forName: "getcontentlength").first?.stringValue ?? "0"
            let isCollection = prop?.elements(forName: "resourcetype").first?.elements(forName: "collection").first != nil
            
            let size = UInt64(contentLength) ?? 0
            var name = displayName
            if name.isEmpty {
                name = (href as NSString).lastPathComponent
                if name.isEmpty || name == "/" {
                    name = (href as NSString).pathComponents.last ?? "/"
                }
            }
            
            let path = href.hasPrefix("/") ? href : "/\(href)"
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let modifiedDate = formatter.date(from: lastModified) ?? Date()
            
            let file = FileInfo(
                name: name,
                path: path,
                isDirectory: isCollection,
                size: size,
                modificationDate: modifiedDate,
                permissions: nil
            )
            
            if path != "/" && path != "" {
                files.append(file)
            }
        }
        
        return files
    }
    
    func getFileInfo(serverID: String, path: String) throws -> FileInfo {
        let files = try listFiles(serverID: serverID, path: path)
        for file in files {
            if file.path == path || file.name == (path as NSString).lastPathComponent {
                return file
            }
        }
        throw ProtocolError.notSupported
    }
    
    // MARK: 创建目录 MKCOL
    func createDirectory(serverID: String, path: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let requestURL = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "MKCOL"
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultError = error
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultError = ProtocolError.notSupported
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                resultError = ProtocolError.notSupported
            }
        }
        
        task.resume()
        semaphore.wait()
        
        if let error = resultError {
            throw error
        }
    }
    
    // MARK: 删除
    func deleteItem(serverID: String, path: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let requestURL = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultError = error
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultError = ProtocolError.notSupported
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                resultError = ProtocolError.notSupported
            }
        }
        
        task.resume()
        semaphore.wait()
        
        if let error = resultError {
            throw error
        }
    }
    
    // MARK: 移动 MOVE
    func moveItem(serverID: String, from: String, to: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let fromURL = baseURL.appendingPathComponent(from)
        let toURL = baseURL.appendingPathComponent(to)
        
        var request = URLRequest(url: fromURL)
        request.httpMethod = "MOVE"
        request.setValue(toURL.absoluteString, forHTTPHeaderField: "Destination")
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultError = error
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultError = ProtocolError.notSupported
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                resultError = ProtocolError.notSupported
            }
        }
        
        task.resume()
        semaphore.wait()
        
        if let error = resultError {
            throw error
        }
    }
    
    // MARK: 复制 COPY
    func copyItem(serverID: String, from: String, to: String) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let fromURL = baseURL.appendingPathComponent(from)
        let toURL = baseURL.appendingPathComponent(to)
        
        var request = URLRequest(url: fromURL)
        request.httpMethod = "COPY"
        request.setValue(toURL.absoluteString, forHTTPHeaderField: "Destination")
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultError = error
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultError = ProtocolError.notSupported
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                resultError = ProtocolError.notSupported
            }
        }
        
        task.resume()
        semaphore.wait()
        
        if let error = resultError {
            throw error
        }
    }
    
    // MARK: 下载
    func downloadFile(serverID: String, remotePath: String, localPath: String, progress: @escaping (Double) -> Void) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let requestURL = baseURL.appendingPathComponent(remotePath)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        let task = URLSession.shared.downloadTask(with: request) { url, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultError = error
                return
            }
            
            guard let tempURL = url else {
                resultError = ProtocolError.downloadFailed(nil)
                return
            }
            
            do {
                let localURL = URL(fileURLWithPath: localPath)
                if FileManager.default.fileExists(atPath: localPath) {
                    try FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: localURL)
                progress(1.0)
            } catch {
                resultError = error
            }
        }
        
        task.resume()
        semaphore.wait()
        
        if let error = resultError {
            throw error
        }
    }
    
    // MARK: 上传
    func uploadFile(serverID: String, localPath: String, remotePath: String, progress: @escaping (Double) -> Void) throws {
        guard let connection = getConnection(serverID: serverID) else {
            throw ProtocolError.connectionFailed("连接不存在")
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            throw ProtocolError.connectionFailed("无效的URL")
        }
        
        let fileURL = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: localPath) else {
            throw ProtocolError.uploadFailed(nil)
        }
        
        let requestURL = baseURL.appendingPathComponent(remotePath)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        
        let task = URLSession.shared.uploadTask(with: request, fromFile: fileURL) { _, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                resultError = error
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                resultError = ProtocolError.uploadFailed(nil)
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                resultError = ProtocolError.uploadFailed(nil)
            } else {
                progress(1.0)
            }
        }
        
        task.resume()
        semaphore.wait()
        
        if let error = resultError {
            throw error
        }
    }
    
    func cancelTransfer(serverID: String, transferID: String) throws {
        throw ProtocolError.notSupported
    }
    
    // MARK: Ping 连通检测
    func ping(serverID: String) -> Bool {
        guard let connection = getConnection(serverID: serverID) else { return false }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else { return false }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                success = true
            }
            semaphore.signal()
        }
        
        task.resume()
        semaphore.wait()
        
        return success
    }
    
    // MARK: 获取容量
    func getCapacity(serverID: String) -> CapacityInfo? {
        guard let connection = getConnection(serverID: serverID) else {
            return nil
        }
        
        guard let baseURL = URL(string: normalizeHTTPSUrl(raw: connection.config.getFullURL())) else {
            return nil
        }
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = """
        <?xml version="1.0"?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:quota-used-bytes/>
            <D:quota-available-bytes/>
          </D:prop>
        </D:propfind>
        """
        request.httpBody = body.data(using: .utf8)
        
        if let username = connection.config.username, !username.isEmpty {
            let password = connection.config.password ?? ""
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var capacity: CapacityInfo?
        
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 207 else {
                return
            }
            
            if let xml = try? XMLDocument(data: data) {
                let root = xml.rootElement()
                let propstat = root?.elements(forName: "propstat").first
                let prop = propstat?.elements(forName: "prop").first
                
                let quotaAvailable = prop?.elements(forName: "quota-available-bytes").first?.stringValue
                let quotaUsed = prop?.elements(forName: "quota-used-bytes").first?.stringValue
                
                if let available = quotaAvailable, let used = quotaUsed {
                    let usedBytes = UInt64(used) ?? 0
                    let freeBytes = UInt64(available) ?? 0
                    capacity = CapacityInfo(
                        total: usedBytes + freeBytes,
                        used: usedBytes,
                        free: freeBytes
                    )
                }
            }
        }
        
        task.resume()
        semaphore.wait()
        
        return capacity
    }
    
    // MARK: 配置表单
    func getConfigSchema() -> ConfigSchema {
        return ConfigSchema(sections: [
            ConfigSection(name: "基础连接", fields: [
                ConfigField(key: "url", label: "服务器地址", type: .url, defaultValue: "", placeholder: "www.yiqipro.com:15006", isRequired: true),
                ConfigField(key: "username", label: "用户名", type: .text, defaultValue: "", placeholder: "andything", isRequired: true),
                ConfigField(key: "password", label: "密码", type: .password, defaultValue: "", placeholder: "Sing20047985", isRequired: true, isSecure: true)
            ]),
            ConfigSection(name: "高级设置", fields: [
                ConfigField(key: "timeout", label: "超时时间(秒)", type: .number, defaultValue: 30, validation: ConfigValidation(minValue: 5, maxValue: 120))
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
    
    // MARK: 私有辅助
    private func getConnection(serverID: String) -> WebDAVConnection? {
        var connection: WebDAVConnection?
        queue.sync {
            connection = connections[serverID]
        }
        return connection
    }
}
