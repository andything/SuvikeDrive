//
//  NetworkTester.swift
//  SuvikeDrive
//
//  模块功能：服务器连通性测试工具服务
//     职责：完整链路测试：DNS解析 → TCP连通 → HTTP探测 → 身份认证 → WebDAV协议校验
//          添加远程目录列表功能
//     依赖：Foundation、Network、NetworkSessionService、NetworkTypes
//

import Foundation
import Network

final class NetworkTester {
    static let shared = NetworkTester()
    
    private let sessionService = NetworkSessionService.shared
    
    private init() {}
    
    // MARK: - 连接测试（包含目录列表）
    func testConnection(
        url: String,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil,
        protocolType: String = "webdav",
        useHTTPS: Bool = true,
        allowSelfSigned: Bool = false,
        timeout: TimeInterval = 10,
        completion: @escaping (NetworkTestResult) -> Void
    ) {
        var details: [String: String] = [:]
        var directoryEntries: [String] = []
        let startTime = Date()
        
        let scheme = useHTTPS ? "https" : "http"
        let portString = port.map { ":\($0)" } ?? ""
        let fullURL = "\(scheme)://\(url)\(portString)"
        details["目标地址"] = fullURL
        details["协议"] = protocolType.uppercased()
        details["端口"] = port.map { "\($0)" } ?? "默认"
        details["用户名"] = (username?.isEmpty ?? true) ? "(未设置)" : (username ?? "(未设置)")
        
        print("开始连接测试: \(fullURL)")
        
        resolveDNS(host: url) { resolvedIP in
            if let ip = resolvedIP {
                details["DNS 解析"] = "成功: \(ip)"
                print("DNS 解析成功: \(ip)")
            } else {
                details["DNS 解析"] = "解析失败"
                print("DNS 解析失败: \(url)")
                let result = NetworkTestResult(
                    success: false,
                    message: "DNS 解析失败，请检查地址是否正确",
                    details: details
                )
                completion(result)
                return
            }
            
            let testPort = port ?? (useHTTPS ? 443 : 80)
            self.testTCPConnection(host: url, port: testPort) { tcpSuccess, tcpError in
                if tcpSuccess {
                    details["TCP 连接"] = "成功"
                    print("TCP 连接成功")
                } else {
                    details["TCP 连接"] = "失败: \(tcpError ?? "超时")"
                    print("TCP 连接失败: \(tcpError ?? "未知错误")")
                    let result = NetworkTestResult(
                        success: false,
                        message: "TCP 连接失败: \(tcpError ?? "无法连接到服务器")",
                        details: details
                    )
                    completion(result)
                    return
                }
                
                self.testHTTPRequest(
                    url: fullURL,
                    username: username ?? "",
                    password: password ?? "",
                    allowSelfSigned: allowSelfSigned,
                    timeout: timeout
                ) { httpSuccess, statusCode, httpError in
                    if httpSuccess {
                        details["HTTP 请求"] = "\(statusCode ?? 200)"
                        print("HTTP 请求成功: \(statusCode ?? 200)")
                    } else {
                        details["HTTP 请求"] = "\(statusCode ?? 0): \(httpError ?? "请求失败")"
                        print("HTTP 请求失败: \(httpError ?? "未知错误")")
                    }
                    
                    if let user = username, !user.isEmpty, let pass = password, !pass.isEmpty {
                        self.testAuthentication(
                            url: fullURL,
                            username: user,
                            password: pass,
                            allowSelfSigned: allowSelfSigned,
                            timeout: timeout
                        ) { authSuccess, authMessage, authStatusCode in
                            if authSuccess {
                                details["认证测试"] = "认证成功"
                                print("认证测试成功")
                            } else {
                                details["认证测试"] = "\(authMessage) (HTTP \(authStatusCode))"
                                print("认证测试失败: \(authMessage)")
                            }
                            
                            // ✅ 列出远程目录
                            if authSuccess || (authStatusCode == 404 || authStatusCode == 401) {
                                self.listRemoteDirectory(
                                    url: fullURL,
                                    username: user,
                                    password: pass,
                                    allowSelfSigned: allowSelfSigned,
                                    timeout: timeout
                                ) { entries, listError in
                                    if let entries = entries, !entries.isEmpty {
                                        directoryEntries = entries
                                        details["远程目录"] = "找到 \(entries.count) 个条目"
                                        print("📁 远程目录: \(entries.joined(separator: ", "))")
                                    } else if let error = listError {
                                        details["远程目录"] = "列表失败: \(error)"
                                        print("📁 远程目录列表失败: \(error)")
                                    } else {
                                        details["远程目录"] = "空目录"
                                        print("📁 远程目录为空")
                                    }
                                    
                                    self.finalizeResult(
                                        details: details,
                                        directoryEntries: directoryEntries,
                                        startTime: startTime,
                                        completion: completion
                                    )
                                }
                            } else {
                                self.finalizeResult(
                                    details: details,
                                    directoryEntries: directoryEntries,
                                    startTime: startTime,
                                    completion: completion
                                )
                            }
                        }
                    } else {
                        self.finalizeResult(
                            details: details,
                            directoryEntries: directoryEntries,
                            startTime: startTime,
                            completion: completion
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - 列出远程目录
    func listRemoteDirectory(
        url: String,
        username: String,
        password: String,
        allowSelfSigned: Bool = false,
        timeout: TimeInterval = 10,
        completion: @escaping ([String]?, String?) -> Void
    ) {
        guard let urlObj = URL(string: url) else {
            completion(nil, "无效的 URL")
            return
        }
        
        var request = URLRequest(url: urlObj)
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = timeout
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        // ✅ 添加认证头
        if !username.isEmpty && !password.isEmpty {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64 = authData.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let session = createSession(allowSelfSigned: allowSelfSigned)
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(nil, "无效的响应")
                return
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 207 {
                guard let data = data else {
                    completion(nil, "无数据返回")
                    return
                }
                
                // ✅ 解析 XML 获取目录列表
                let entries = self.parseWebDAVResponse(data: data)
                completion(entries, nil)
            } else if httpResponse.statusCode == 401 {
                completion(nil, "认证失败，请检查用户名和密码")
            } else if httpResponse.statusCode == 404 {
                completion(nil, "路径不存在 (404)")
            } else {
                completion(nil, "HTTP \(httpResponse.statusCode)")
            }
        }
        task.resume()
    }
    
    // MARK: - 解析 WebDAV PROPFIND 响应
    private func parseWebDAVResponse(data: Data) -> [String] {
        var entries: [String] = []
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            return entries
        }
        
        // ✅ 使用简单的 XML 解析提取 href
        let pattern = "<d:href[^>]*>([^<]+)</d:href>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let nsString = xmlString as NSString
        
        regex?.enumerateMatches(in: xmlString, options: [], range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            if let match = match, match.numberOfRanges > 1 {
                let href = nsString.substring(with: match.range(at: 1))
                if href.count > 1 {
                    // 解码 URL 编码
                    let decoded = href.removingPercentEncoding ?? href
                    // 过滤掉当前目录 "."
                    if decoded != "/" && decoded != "." {
                        entries.append(decoded)
                    }
                }
            }
        }
        
        // ✅ 去重并排序
        let uniqueEntries = Array(Set(entries)).sorted()
        
        // ✅ 如果解析失败，尝试备用方法
        if uniqueEntries.isEmpty {
            // 尝试匹配不带命名空间前缀的 href
            let fallbackPattern = "<href[^>]*>([^<]+)</href>"
            let fallbackRegex = try? NSRegularExpression(pattern: fallbackPattern, options: .caseInsensitive)
            fallbackRegex?.enumerateMatches(in: xmlString, options: [], range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
                if let match = match, match.numberOfRanges > 1 {
                    let href = nsString.substring(with: match.range(at: 1))
                    if href.count > 1 {
                        let decoded = href.removingPercentEncoding ?? href
                        if decoded != "/" && decoded != "." {
                            entries.append(decoded)
                        }
                    }
                }
            }
        }
        
        return Array(Set(entries)).sorted()
    }
    
    // MARK: - DNS解析（异步）
    private func resolveDNS(host: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ipAddress: String?
            
            // ✅ 使用 getaddrinfo 解析
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            
            var info: UnsafeMutablePointer<addrinfo>?
            if getaddrinfo(host, nil, &hints, &info) == 0 {
                var ptr = info
                while ptr != nil {
                    let sockaddr = ptr?.pointee.ai_addr
                    if let sockaddr = sockaddr {
                        let sockaddrIn = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        let addr = sockaddrIn.sin_addr
                        let ip = String(cString: inet_ntoa(addr))
                        if !ip.isEmpty && ip != "0.0.0.0" {
                            ipAddress = ip
                            break
                        }
                    }
                    ptr = ptr?.pointee.ai_next
                }
                freeaddrinfo(info)
            }
            
            DispatchQueue.main.async {
                completion(ipAddress)
            }
        }
    }
    
    // MARK: - TCP连通探测（异步）
    private func testTCPConnection(host: String, port: Int, completion: @escaping (Bool, String?) -> Void) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )
        
        var didComplete = false
        
        connection.stateUpdateHandler = { state in
            if didComplete { return }
            switch state {
            case .ready:
                didComplete = true
                DispatchQueue.main.async {
                    completion(true, nil)
                }
            case .failed(let error):
                didComplete = true
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3) {
            if !didComplete {
                didComplete = true
                connection.cancel()
                DispatchQueue.main.async {
                    completion(false, "连接超时")
                }
            }
        }
    }
    
    // MARK: HTTP基础探测
    private func testHTTPRequest(
        url: String,
        username: String,
        password: String,
        allowSelfSigned: Bool,
        timeout: TimeInterval,
        completion: @escaping (Bool, Int?, String?) -> Void
    ) {
        guard let urlObj = URL(string: url) else {
            completion(false, nil, "无效的 URL")
            return
        }
        
        var request = URLRequest(url: urlObj)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        
        let session = createSession(allowSelfSigned: allowSelfSigned)
        
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(false, nil, error.localizedDescription)
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                completion(true, httpResponse.statusCode, nil)
            } else {
                completion(false, nil, "无效的响应")
            }
        }
        task.resume()
    }
    
    // MARK: Basic身份认证测试
    private func testAuthentication(
        url: String,
        username: String,
        password: String,
        allowSelfSigned: Bool,
        timeout: TimeInterval,
        completion: @escaping (Bool, String, Int) -> Void
    ) {
        guard let urlObj = URL(string: url) else {
            completion(false, "无效的 URL", 0)
            return
        }
        
        var request = URLRequest(url: urlObj)
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = timeout
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let authString = "\(username):\(password)"
        if let authData = authString.data(using: .utf8) {
            let base64 = authData.base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
        
        let session = createSession(allowSelfSigned: allowSelfSigned)
        
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(false, error.localizedDescription, 0)
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 207 {
                    completion(true, "认证成功", httpResponse.statusCode)
                } else if httpResponse.statusCode == 401 {
                    completion(false, "认证失败，请检查用户名和密码", httpResponse.statusCode)
                } else {
                    completion(false, "HTTP \(httpResponse.statusCode)", httpResponse.statusCode)
                }
            } else {
                completion(false, "无效的响应", 0)
            }
        }
        task.resume()
    }
    
    private func createSession(allowSelfSigned: Bool) -> URLSession {
        if allowSelfSigned {
            let config = URLSessionConfiguration.default
            let delegate = SelfSignedCertificateDelegate()
            return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        } else {
            return URLSession.shared
        }
    }
    
    private func finalizeResult(
        details: [String: String],
        directoryEntries: [String],
        startTime: Date,
        completion: @escaping (NetworkTestResult) -> Void
    ) {
        let totalTime = Date().timeIntervalSince(startTime)
        var finalDetails = details
        finalDetails["总耗时"] = String(format: "%.2fms", totalTime * 1000)
        
        // ✅ 添加目录列表到详情 - 完整显示所有条目，不截断
        if !directoryEntries.isEmpty {
            finalDetails["📁 目录列表"] = directoryEntries.joined(separator: "\n")
        }
        
        let hasFailure = finalDetails.values.contains { value in
            value.contains("失败") ||
            value.contains("错误") ||
            value.contains("异常") ||
            value.contains("解析失败") ||
            value.contains("无法连接") ||
            value.contains("超时")
        }
        
        let allPassed = !hasFailure
        
        var message: String
        if allPassed {
            let entryCount = directoryEntries.count
            if entryCount > 0 {
                message = "✅ 连接成功！找到 \(entryCount) 个目录/文件"
            } else {
                message = "✅ 连接成功，但目录为空"
            }
        } else {
            let failedItems = finalDetails.filter { key, value in
                value.contains("失败") || value.contains("异常") ||
                value.contains("解析失败") || value.contains("无法连接") ||
                value.contains("超时")
            }
            if let firstFailed = failedItems.first {
                message = "❌ \(firstFailed.key) \(firstFailed.value)"
            } else {
                message = "部分测试失败，请检查"
            }
        }
        
        let result = NetworkTestResult(
            success: allPassed,
            message: message,
            details: finalDetails
        )
        
        DispatchQueue.main.async {
            completion(result)
        }
    }
}
