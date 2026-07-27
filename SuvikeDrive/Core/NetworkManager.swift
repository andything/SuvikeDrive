//
//  NetworkManager.swift
//  SuvikeDrive
//
//  模块功能：网络层统一对外门面
//     职责：上层业务唯一入口，聚合所有网络服务
//          对外暴露统一接口，内部转发至各个Service
//          流量数据、网络状态通过@Published对外分发
//          保留历史兼容接口，上层代码无需大规模修改
//
//     依赖：所有Network下Service、NetworkInterfaceMonitor、NetworkTypes
//

import AppKit
import Foundation
import Network
import Combine

class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    // 底层服务实例
    let sessionService = NetworkSessionService.shared
    let requestService = NetworkRequestService.shared
    let reachabilityService = NetworkReachabilityService.shared
    let tester = NetworkTester.shared
    let connectionPool = ConnectionPool()
    
    // 网卡流量监控
    private let interfaceMonitor = NetworkInterfaceMonitor.shared
    private var isInterfaceMonitoring = false
    
    // 对外流量状态
    @Published private(set) var downloadSpeed: Double = 0
    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var totalDownload: UInt64 = 0
    @Published private(set) var totalUpload: UInt64 = 0
    
    // 网络连通状态代理转发
    var urlSession: URLSession { sessionService.session }
    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var isReachable: Bool = false
    
    private init() {
        bindReachability()
        startInterfaceMonitoring(interval: 1.0)
    }
    
    // MARK: 绑定可达性状态
    private func bindReachability() {
        reachabilityService.startMonitoring()
        reachabilityService.$networkStatus.assign(to: \.networkStatus, on: self).store(in: &cancellables)
        reachabilityService.$isReachable.assign(to: \.isReachable, on: self).store(in: &cancellables)
    }
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: 网卡流量监控包装
    func startInterfaceMonitoring(interval: TimeInterval = 1.0) {
        guard !isInterfaceMonitoring else { return }
        interfaceMonitor.onTrafficUpdate = { [weak self] down, up, totalDown, totalUp in
            guard let self = self else { return }
            self.downloadSpeed = down
            self.uploadSpeed = up
            self.totalDownload = totalDown
            self.totalUpload = totalUp
        }
        interfaceMonitor.startMonitoring(interval: interval)
        isInterfaceMonitoring = true
    }
    
    func stopInterfaceMonitoring() {
        interfaceMonitor.stopMonitoring()
        isInterfaceMonitoring = false
    }
    
    func resetTrafficStats() {
        interfaceMonitor.resetTrafficStats()
        downloadSpeed = 0
        uploadSpeed = 0
        totalDownload = 0
        totalUpload = 0
    }
    
    // MARK: Session/代理/SSL 转发
    func trustSelfSignedCertificates(_ trust: Bool) {
        sessionService.trustSelfSignedCertificates(trust)
    }
    func setProxy(host: String, port: Int) {
        sessionService.setProxy(host: host, port: port)
    }
    func clearProxy() {
        sessionService.clearProxy()
    }
    func useSystemProxy(_ use: Bool) {
        sessionService.useSystemProxy(use)
    }
    func setTimeout(_ timeout: TimeInterval) {
        sessionService.setTimeout(timeout)
    }
    func setMaxRetries(_ retries: Int) {
        requestService.setMaxRetries(retries)
    }
    
    // MARK: HTTP请求转发
    func request(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        retries: Int? = nil,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        requestService.request(url: url, method: method, headers: headers, body: body, timeout: timeout, retries: retries, completion: completion)
    }
    
    func requestJSON<T: Decodable>(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: [String: Any]? = nil,
        timeout: TimeInterval? = nil,
        retries: Int? = nil,
        completion: @escaping (Result<T, NetworkError>) -> Void
    ) {
        requestService.requestJSON(url: url, method: method, headers: headers, body: body, timeout: timeout, retries: retries, completion: completion)
    }
    
    func download(
        url: URL,
        destination: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, NetworkError>) -> Void
    ) {
        requestService.download(url: url, destination: destination, progress: progress, completion: completion)
    }
    
    func upload(
        url: URL,
        file: URL,
        headers: [String: String] = [:],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        requestService.upload(url: url, file: file, headers: headers, progress: progress, completion: completion)
    }
    
    // MARK: 连接池转发
    func getConnection(for host: String, port: Int) -> Connection? {
        connectionPool.getConnection(host: host, port: port)
    }
    func returnConnection(_ connection: Connection) {
        connectionPool.returnConnection(connection)
    }
    func cleanupConnections() {
        connectionPool.cleanup()
    }
    
    // MARK: 服务器连接测试转发
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
        tester.testConnection(url: url, port: port, username: username, password: password, protocolType: protocolType, useHTTPS: useHTTPS, allowSelfSigned: allowSelfSigned, timeout: timeout, completion: completion)
    }
}
