//
//  NetworkReachabilityService.swift
//  SuvikeDrive
//
//  模块功能：网络连通性监控服务
//  职责：基于NWPathMonitor监听系统网络切换、在线/离线状态
//        通过@Published对外推送网络状态，供UI响应网络变化
//  依赖：Foundation、Network、Combine、NetworkTypes.swift
//

import Foundation
import Network
import Combine

final class NetworkReachabilityService: ObservableObject {
    static let shared = NetworkReachabilityService()
    
    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var isReachable: Bool = false
    
    private var reachabilityMonitor: NWPathMonitor?
    private var isMonitoring = false
    
    private init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        reachabilityMonitor = NWPathMonitor()
        reachabilityMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isReachable = path.status == .satisfied
                self?.networkStatus = path.status == .satisfied ? .connected : .disconnected
                
                if path.status == .satisfied {
                    Logger.shared.debug("网络已连接")
                } else {
                    Logger.shared.warning("网络已断开")
                }
            }
        }
        reachabilityMonitor?.start(queue: .global())
        isMonitoring = true
    }
    
    func stopMonitoring() {
        reachabilityMonitor?.cancel()
        reachabilityMonitor = nil
        isMonitoring = false
    }
}
