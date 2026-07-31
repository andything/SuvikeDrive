//
//  NetworkRequestService.swift
//  SuvikeDrive
//
//  模块功能：HTTP请求业务服务
//  职责：封装通用GET/POST、JSON请求、文件上传下载、自动重试、并发队列限流
//        管理上传/下载进度监听，统一错误映射
//        新增：流量统计（入站/出站字节数）
//  依赖：Foundation、Combine、NetworkSessionService、NetworkTypes
//

import Foundation
import Combine

final class NetworkRequestService {
    static let shared = NetworkRequestService()
    
    private let sessionService = NetworkSessionService.shared
    private let requestQueue = DispatchQueue(label: "com.suvikedrive.network.request")
    private let maxConcurrentRequests = 10
    private var activeRequests = 0
    private var pendingRequests: [(URLRequest, (Data?, URLResponse?, Error?) -> Void)] = []
    private var maxRetries: Int = 3
    
    // ✅ 核心修复：增加一个专用的串行队列，来保护下载和上传的观察者字典
    private let observationQueue = DispatchQueue(label: "com.suvikedrive.network.observation")
    
    private var downloadObservations: [Int: NSKeyValueObservation] = [:]
    private var uploadObservations: [Int: NSKeyValueObservation] = [:]
    
    // MARK: - 流量统计
    private(set) var totalBytesIn: Int64 = 0
    private(set) var totalBytesOut: Int64 = 0
    private var trafficLock = NSLock()
    private var trafficRecords: [TrafficRecord] = []
    private let maxTrafficRecords = 1000
    
    // 流量更新回调（主线程）
    var onTrafficUpdate: ((_ bytesIn: Int64, _ bytesOut: Int64) -> Void)?
    
    private init() {}
    
    func setMaxRetries(_ retries: Int) {
        maxRetries = retries
    }
    
    // MARK: 基础HTTP请求
    func request(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        retries: Int? = nil,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout ?? sessionService.session.configuration.timeoutIntervalForRequest
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = body
            if headers["Content-Type"] == nil {
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            }
        }
        
        let ret = retries ?? maxRetries
        performRequestWithRetry(request, remainingRetries: ret, completion: completion)
    }
    
    // MARK: JSON请求自动解析
    func requestJSON<T: Decodable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: [String: Any]? = nil,
        timeout: TimeInterval? = nil,
        retries: Int? = nil,
        completion: @escaping (Result<T, NetworkError>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout ?? sessionService.session.configuration.timeoutIntervalForRequest
        
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                completion(.failure(.invalidRequestBody))
                return
            }
        }
        
        let ret = retries ?? maxRetries
        performRequestWithRetry(request, remainingRetries: ret) { result in
            switch result {
            case .success(let data):
                do {
                    let decoder = JSONDecoder()
                    let obj = try decoder.decode(T.self, from: data)
                    completion(.success(obj))
                } catch {
                    completion(.failure(.decodingError(error)))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }
    
    // MARK: 文件下载
    
    func download(
        url: URL,
        destination: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, NetworkError>) -> Void
    ) {
        let request = URLRequest(url: url, timeoutInterval: sessionService.session.configuration.timeoutIntervalForRequest * 3)
        let task = sessionService.session.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                completion(.failure(.downloadFailed(error)))
                return
            }
            guard let tempURL = tempURL else {
                completion(.failure(.downloadFailed(nil)))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                completion(.success(destination))
            } catch {
                completion(.failure(.fileOperationFailed(error)))
            }
        }
        
        let obs = task.progress.observe(\.fractionCompleted, options: [.new]) { p, change in
            let fraction = change.newValue ?? p.fractionCompleted
            DispatchQueue.main.async {
                progress(fraction)
            }
        }
        task.resume()
        
        // ✅ 核心修复：使用串行队列保护字典写入，防止多线程并发导致 EXC_BAD_ACCESS
        observationQueue.sync {
            downloadObservations[task.taskIdentifier] = obs
        }
    }
    
    // MARK: 文件上传
    
    func upload(
        url: URL,
        file: URL,
        headers: [String: String] = [:],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = sessionService.session.configuration.timeoutIntervalForRequest * 3
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let task = sessionService.session.uploadTask(with: request, fromFile: file) { data, resp, err in
            if let err = err {
                completion(.failure(.uploadFailed(err)))
                return
            }
            guard let data = data else {
                completion(.failure(.uploadFailed(nil)))
                return
            }
            completion(.success(data))
        }
        
        let obs = task.progress.observe(\.fractionCompleted, options: [.new]) { p, change in
            let fraction = change.newValue ?? p.fractionCompleted
            DispatchQueue.main.async {
                progress(fraction)
            }
        }
        task.resume()
        
        // ✅ 核心修复：使用串行队列保护字典写入，防止多线程并发导致 EXC_BAD_ACCESS
        observationQueue.sync {
            uploadObservations[task.taskIdentifier] = obs
        }
    }
    
    // MARK: - 清理与取消（可选）
    func cancelDownload(taskIdentifier: Int) {
        // 加上 _ =
        _ = observationQueue.sync {
            downloadObservations.removeValue(forKey: taskIdentifier)
        }
    }
    
    func cancelUpload(taskIdentifier: Int) {
        // 加上 _ =
        _ = observationQueue.sync {
            uploadObservations.removeValue(forKey: taskIdentifier)
        }
    }
    
    // MARK: - 流量统计
    
    private func recordTraffic(bytesIn: Int64, bytesOut: Int64, success: Bool = true, error: String? = nil) {
        trafficLock.lock()
        defer { trafficLock.unlock() }
        
        totalBytesIn += bytesIn
        totalBytesOut += bytesOut
        
        let record = TrafficRecord(
            timestamp: Date(),
            url: "",
            bytesIn: bytesIn,
            bytesOut: bytesOut,
            duration: 0,
            success: success,
            error: error
        )
        trafficRecords.append(record)
        if trafficRecords.count > maxTrafficRecords {
            trafficRecords.removeFirst()
        }
        
        DispatchQueue.main.async {
            self.onTrafficUpdate?(self.totalBytesIn, self.totalBytesOut)
        }
    }
    
    func getTrafficStats() -> (bytesIn: Int64, bytesOut: Int64, records: [TrafficRecord]) {
        trafficLock.lock()
        defer { trafficLock.unlock() }
        return (totalBytesIn, totalBytesOut, trafficRecords)
    }
    
    func resetTrafficStats() {
        trafficLock.lock()
        defer { trafficLock.unlock() }
        totalBytesIn = 0
        totalBytesOut = 0
        trafficRecords.removeAll()
    }
    
    // MARK: 内部重试调度
    private func performRequestWithRetry(
        _ request: URLRequest,
        remainingRetries: Int,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        performRequest(request) { [weak self] res in
            switch res {
            case .success:
                completion(res)
            case .failure(let err):
                guard let self = self else { return }
                if remainingRetries > 0, self.shouldRetry(error: err) {
                    Logger.shared.warning("请求失败，剩余重试次数: \(remainingRetries)，错误: \(err.localizedDescription)")
                    let delay = TimeInterval((self.maxRetries - remainingRetries + 1)) * 2
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.performRequestWithRetry(request, remainingRetries: remainingRetries - 1, completion: completion)
                    }
                } else {
                    completion(.failure(err))
                }
            }
        }
    }
    
    private func shouldRetry(error: NetworkError) -> Bool {
        switch error {
        case .timeout, .connectionFailed, .connectionLost, .noInternetConnection:
            return true
        default:
            return false
        }
    }
    
    private func performRequest(
        _ request: URLRequest,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        requestQueue.async(flags: .barrier) {
            self.activeRequests += 1
            if self.activeRequests > self.maxConcurrentRequests {
                self.pendingRequests.append((request, { data, resp, err in
                    if let err = err {
                        completion(.failure(.requestFailed(err)))
                        return
                    }
                    guard let data = data else {
                        completion(.failure(.invalidResponse))
                        return
                    }
                    completion(.success(data))
                }))
                return
            }
            self.executeRequest(request, completion: completion)
        }
    }
    
    private func executeRequest(
        _ request: URLRequest,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        let requestBodySize = request.httpBody?.count ?? 0
        
        if requestBodySize > 0 {
            recordTraffic(bytesIn: 0, bytesOut: Int64(requestBodySize))
        }
        
        let task = sessionService.session.dataTask(with: request) { data, resp, err in
            self.requestQueue.async {
                self.activeRequests -= 1
                self.processNextPendingRequest()
            }
            
            if let err = err {
                let netErr = self.mapError(err, response: resp)
                self.recordTraffic(bytesIn: 0, bytesOut: 0, success: false, error: netErr.localizedDescription)
                DispatchQueue.main.async { completion(.failure(netErr)) }
                return
            }
            
            guard let httpResp = resp as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(.invalidResponse)) }
                return
            }
            
            let responseSize = data?.count ?? 0
            self.recordTraffic(bytesIn: Int64(responseSize), bytesOut: 0)
            
            guard (200...299).contains(httpResp.statusCode) else {
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? "HTTP错误"
                DispatchQueue.main.async {
                    completion(.failure(.httpError(statusCode: httpResp.statusCode, message: msg)))
                }
                return
            }
            
            DispatchQueue.main.async { completion(.success(data ?? Data())) }
        }
        task.resume()
    }
    
    private func processNextPendingRequest() {
        guard !pendingRequests.isEmpty else { return }
        let (req, comp) = pendingRequests.removeFirst()
        executeRequest(req) { res in
            switch res {
            case .success(let d): comp(d, nil, nil)
            case .failure(let e): comp(nil, nil, e)
            }
        }
    }
    
    private func mapError(_ error: Error, response: URLResponse?) -> NetworkError {
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain {
            switch nsErr.code {
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorCannotConnectToHost: return .connectionFailed
            case NSURLErrorNetworkConnectionLost: return .connectionLost
            case NSURLErrorNotConnectedToInternet: return .noInternetConnection
            case NSURLErrorSecureConnectionFailed: return .sslError
            case NSURLErrorServerCertificateUntrusted: return .untrustedCertificate
            default: return .requestFailed(error)
            }
        }
        return .requestFailed(error)
    }
}
