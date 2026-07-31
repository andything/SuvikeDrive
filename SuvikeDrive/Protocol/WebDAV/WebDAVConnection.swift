//
//  WebDAVConnection.swift
//  SuvikeDrive
//
//  功能: WebDAV 连接实例
//  归属: Protocol/WebDAV
//

import Foundation

final class WebDAVConnection {
    let serverID: String
    let config: ServerConfig
    var isMounted: Bool = false
    var mountPath: String?
    private var session: URLSession?
    private var isDisconnected: Bool = false
    
    init(serverID: String, config: ServerConfig) {
        self.serverID = serverID
        self.config = config
        setupSession()
    }
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 获取会话
    func getSession() -> URLSession? {
        guard !isDisconnected else { return nil }
        return session
    }
    
    // MARK: - 取消所有任务
    func cancelAllTasks() {
        session?.getTasksWithCompletionHandler { [weak self] dataTasks, uploadTasks, downloadTasks in
            guard let self = self else { return }
            
            let totalTasks = dataTasks.count + uploadTasks.count + downloadTasks.count
            if totalTasks > 0 {
                Logger.shared.info("[\(self.serverID)] 取消 \(totalTasks) 个网络任务", module: "WebDAVConnection")
            }
            
            for task in dataTasks {
                task.cancel()
            }
            for task in uploadTasks {
                task.cancel()
            }
            for task in downloadTasks {
                task.cancel()
            }
        }
    }
    
    // MARK: - 使会话失效
    func invalidateSession() {
        session?.invalidateAndCancel()
        session = nil
        Logger.shared.info("[\(serverID)] 会话已失效", module: "WebDAVConnection")
    }
    
    // MARK: - 断开连接
    func disconnect() {
        guard !isDisconnected else { return }
        
        Logger.shared.info("[\(serverID)] 断开 WebDAV 连接...", module: "WebDAVConnection")
        
        // 1. 取消所有任务
        cancelAllTasks()
        
        // 2. 使会话失效
        invalidateSession()
        
        // 3. 重置状态
        isMounted = false
        mountPath = nil
        isDisconnected = true
        
        Logger.shared.info("[\(serverID)] WebDAV 连接已断开", module: "WebDAVConnection")
    }
    
    // MARK: - 重新连接
    func reconnect() {
        guard isDisconnected else { return }
        
        Logger.shared.info("[\(serverID)] 重新建立 WebDAV 连接...", module: "WebDAVConnection")
        
        setupSession()
        isDisconnected = false
        Logger.shared.info("[\(serverID)] WebDAV 连接已重新建立", module: "WebDAVConnection")
    }
    
    deinit {
        disconnect()
    }
}
