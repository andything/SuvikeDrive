//
//  NetworkRequestService.swift
//  SuvikeDrive
//
//  模块功能：HTTP请求业务服务
//  职责：封装通用GET/POST、JSON请求、文件上传下载、自动重试、并发队列限流
//        管理上传/下载进度监听，统一错误映射
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
    
    private var downloadObservations: [Int: NSKeyValueObservation] = [:]
    private var uploadObservations: [Int: NSKeyValueObservation] = [:]
    
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
        
        let obs = task.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { progress(p.fractionCompleted) }
        }
        task.resume()
        downloadObservations[task.taskIdentifier] = obs
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
        
        let obs = task.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { progress(p.fractionCompleted) }
        }
        task.resume()
        uploadObservations[task.taskIdentifier] = obs
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
        let task = sessionService.session.dataTask(with: request) { data, resp, err in
            self.requestQueue.async {
                self.activeRequests -= 1
                self.processNextPendingRequest()
            }
            if let err = err {
                let netErr = self.mapError(err, response: resp)
                DispatchQueue.main.async { completion(.failure(netErr)) }
                return
            }
            guard let httpResp = resp as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(.invalidResponse)) }
                return
            }
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
