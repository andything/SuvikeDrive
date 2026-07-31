//
//  NetworkManager.swift
//  SuvikeDrive
//
//  模块功能：网络层统一对外门面
//     职责：上层业务唯一入口，聚合所有网络服务
//          对外暴露统一接口，内部转发至各个Service
//          流量数据、网络状态通过 @Published 对外分发
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
    
    // 对外流量状态（系统级 - 来自网卡监控）
    @Published private(set) var downloadSpeed: Double = 0
    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var totalDownload: UInt64 = 0
    @Published private(set) var totalUpload: UInt64 = 0
    
    // 应用级流量统计（来自 NetworkRequestService）
    @Published private(set) var appTotalDownload: Int64 = 0
    @Published private(set) var appTotalUpload: Int64 = 0
    
    // 网络连通状态代理转发
    var urlSession: URLSession { sessionService.session }
    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var isReachable: Bool = false
    
    // ✅ EventBus 防重入标志
    private var isPublishingTraffic = false
    
    // ✅ 网络专用队列（确保所有网络回调在后台线程）
    private let networkQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.suvikedrive.networkqueue"
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    private init() {
        bindReachability()
        startInterfaceMonitoring(interval: 1.0)
        
        // ✅ 绑定 NetworkRequestService 的流量更新
        requestService.onTrafficUpdate = { [weak self] bytesIn, bytesOut in
            DispatchQueue.main.async {
                self?.appTotalDownload = bytesIn
                self?.appTotalUpload = bytesOut
            }
        }
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
            
            // ✅ 更新 @Published 属性（兼容旧代码）
            self.downloadSpeed = down
            self.uploadSpeed = up
            self.totalDownload = totalDown
            self.totalUpload = totalUp
            
            // ✅ 通过 EventBus 发布流量更新事件（新方式）
            self.publishTrafficStats(download: down, upload: up, totalDown: totalDown, totalUp: totalUp)
        }
        interfaceMonitor.startMonitoring(interval: interval)
        isInterfaceMonitoring = true
    }
    
    // MARK: 发布流量统计事件
    private func publishTrafficStats(download: Double, upload: Double, totalDown: UInt64, totalUp: UInt64) {
        // 防止事件风暴（每秒更新一次，没必要重复发布）
        guard !isPublishingTraffic else { return }
        isPublishingTraffic = true
        defer { isPublishingTraffic = false }
        
        // 阈值过滤：变化小于 1KB/s 不发布（减少事件噪音）
        let threshold: Double = 1024
        let lastDown = self.downloadSpeed
        let lastUp = self.uploadSpeed
        let downDiff = abs(download - lastDown)
        let upDiff = abs(upload - lastUp)
        
        // 首次发布或变化超过阈值才发布
        if lastDown == 0 && lastUp == 0 && download == 0 && upload == 0 {
            return
        }
        
        if downDiff > threshold || upDiff > threshold || download == 0 || upload == 0 {
            DispatchQueue.main.async {
                EventBus.shared.publish(TrafficStatsUpdated(
                    downloadSpeed: download,
                    uploadSpeed: upload,
                    totalDownload: totalDown,
                    totalUpload: totalUp
                ))
            }
        }
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
    
    // MARK: 应用级流量统计
    func getAppTrafficStats() -> (download: Int64, upload: Int64) {
        let stats = requestService.getTrafficStats()
        return (stats.bytesIn, stats.bytesOut)
    }
    
    func getAppTrafficRecords() -> [TrafficRecord] {
        return requestService.getTrafficStats().records
    }
    
    func resetAppTrafficStats() {
        requestService.resetTrafficStats()
        appTotalDownload = 0
        appTotalUpload = 0
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
    
    // MARK: HTTP请求转发（✅ 强制在后台线程执行）
    func request(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        retries: Int? = nil,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        // ✅ 强制在后台线程执行网络请求
        networkQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            self.requestService.request(
                url: url,
                method: method,
                headers: headers,
                body: body,
                timeout: timeout,
                retries: retries
            ) { result in
                // ✅ 回调保持在后台线程（不切换主线程）
                completion(result)
            }
        }
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
        // ✅ 强制在后台线程执行网络请求
        networkQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            self.requestService.requestJSON(
                url: url,
                method: method,
                headers: headers,
                body: body,
                timeout: timeout,
                retries: retries
            ) { result in
                // ✅ 回调保持在后台线程
                completion(result)
            }
        }
    }
    
    func download(
        url: URL,
        destination: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, NetworkError>) -> Void
    ) {
        // ✅ 强制在后台线程执行下载
        networkQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            self.requestService.download(
                url: url,
                destination: destination,
                progress: progress,
                completion: completion
            )
        }
    }
    
    func upload(
        url: URL,
        file: URL,
        headers: [String: String] = [:],
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        // ✅ 强制在后台线程执行上传
        networkQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            self.requestService.upload(
                url: url,
                file: file,
                headers: headers,
                progress: progress,
                completion: completion
            )
        }
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
        // ✅ 强制在后台线程执行连接测试
        networkQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            self.tester.testConnection(
                url: url,
                port: port,
                username: username,
                password: password,
                protocolType: protocolType,
                useHTTPS: useHTTPS,
                allowSelfSigned: allowSelfSigned,
                timeout: timeout,
                completion: completion
            )
        }
    }
    
    // MARK: 任务管理（转发到 NetworkTaskManager）
    func pauseAllTasks() {
        NetworkTaskManager.shared.pauseAll()
    }
    
    func resumeAllTasks() {
        NetworkTaskManager.shared.resumeAll()
    }
    
    func cancelAllTasks(serverID: String? = nil) {
        NetworkTaskManager.shared.cancelAll(serverID: serverID)
    }
    
    func getTasks(for serverID: String) -> [NetworkTask] {
        return NetworkTaskManager.shared.getTasks(for: serverID)
    }
    
    func getActiveTasks(for serverID: String) -> [NetworkTask] {
        return NetworkTaskManager.shared.getActiveTasks(for: serverID)
    }
}
