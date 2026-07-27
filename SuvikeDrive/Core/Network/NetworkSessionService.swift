//
//  NetworkSessionService.swift
//  SuvikeDrive
//
//  模块功能：URLSession实例管理服务
//  职责：统一管理全局URLSession、代理配置、超时参数、SSL证书策略
//        负责动态重建session，切换系统代理/自定义代理、自签证书开关
//  依赖：Foundation、SelfSignedCertificateDelegate.swift
//

import Foundation

final class NetworkSessionService {
    static let shared = NetworkSessionService()
    
    var session: URLSession
    private var customProxy: (host: String, port: Int)?
    private var useSystemProxy = true
    private var globalTimeout: TimeInterval = 30.0
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = globalTimeout
        configuration.timeoutIntervalForResource = globalTimeout * 2
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = true
        
        if useSystemProxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPSEnable: true
            ]
        }
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: SSL证书控制
    func trustSelfSignedCertificates(_ trust: Bool) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = globalTimeout
        configuration.connectionProxyDictionary = useSystemProxy ? [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPSEnable: true
        ] : nil
        
        if trust {
            let delegate = SelfSignedCertificateDelegate()
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: configuration)
        }
    }
    
    // MARK: 代理配置
    func setProxy(host: String, port: Int) {
        customProxy = (host, port)
        updateProxyConfiguration()
    }
    
    func clearProxy() {
        customProxy = nil
        updateProxyConfiguration()
    }
    
    func useSystemProxy(_ use: Bool) {
        useSystemProxy = use
        updateProxyConfiguration()
    }
    
    private func updateProxyConfiguration() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = globalTimeout
        
        if let proxy = customProxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPProxy: proxy.host,
                kCFNetworkProxiesHTTPPort: proxy.port,
                kCFNetworkProxiesHTTPSEnable: true,
                kCFNetworkProxiesHTTPSProxy: proxy.host,
                kCFNetworkProxiesHTTPSPort: proxy.port
            ]
        } else if useSystemProxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true,
                kCFNetworkProxiesHTTPSEnable: true
            ]
        } else {
            configuration.connectionProxyDictionary = [:]
        }
        
        self.session = URLSession(configuration: configuration)
        print("✅ 代理配置已更新")
    }
    
    // MARK: 全局超时设置
    func setTimeout(_ timeout: TimeInterval) {
        globalTimeout = timeout
        let configuration = session.configuration
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
    }
}
