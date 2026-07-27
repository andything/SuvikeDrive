//
//  MountManager.swift
//  SuvikeDrive
//
//  功能: 挂载管理器（配合 ProtocolModuleManager）
//

import AppKit
import Foundation
import Combine

class MountManager: ObservableObject {
    static let shared = MountManager()
    
    @Published private(set) var mountedServers: Set<String> = []
    @Published private(set) var mountErrors: [String: String] = [:]
    
    // MARK: - 挂载任务管理
    private var mountingTasks: [String: Bool] = [:]
    private let mountQueue = DispatchQueue(label: "com.suvikedrive.mountmanager", attributes: .concurrent)
    
    private init() {}
    
    // MARK: - 挂载
    func mount(serverID: String, config: ServerConfig, completion: @escaping (Result<String, Error>) -> Void) {
        mountQueue.async(flags: .barrier) {
            // 检查是否正在挂载
            if self.mountingTasks[serverID] == true {
                DispatchQueue.main.async {
                    completion(.failure(ProtocolError.connectionFailed("正在挂载中")))
                }
                return
            }
            
            // 检查是否已挂载
            if self.mountedServers.contains(serverID) {
                DispatchQueue.main.async {
                    completion(.failure(ProtocolError.connectionFailed("已挂载")))
                }
                return
            }
            
            self.mountingTasks[serverID] = true
            
            do {
                // 通过 ProtocolModuleManager 统一操作
                try ProtocolModuleManager.shared.connect(serverID: serverID, config: config)
                
                let mountPath = config.getMountPath()
                try ProtocolModuleManager.shared.mount(serverID: serverID, mountPath: mountPath)
                
                // 更新状态
                DispatchQueue.main.async {
                    self.mountedServers.insert(serverID)
                    self.mountErrors[serverID] = nil
                    self.mountingTasks[serverID] = false
                    NotificationCenter.default.post(name: .MountStatusChanged, object: nil)
                    completion(.success(mountPath))
                }
                
            } catch {
                // 清理失败的挂载
                ProtocolModuleManager.shared.removeInstance(serverID: serverID)
                
                DispatchQueue.main.async {
                    self.mountingTasks[serverID] = false
                    self.mountErrors[serverID] = error.localizedDescription
                    NotificationCenter.default.post(name: .MountStatusChanged, object: nil)
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 卸载
    func unmount(serverID: String, force: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        mountQueue.async(flags: .barrier) {
            guard self.mountedServers.contains(serverID) else {
                DispatchQueue.main.async {
                    completion(.failure(ProtocolError.connectionFailed("未挂载")))
                }
                return
            }
            
            do {
                // 通过 ProtocolModuleManager 统一操作
                try ProtocolModuleManager.shared.unmount(serverID: serverID)
                try ProtocolModuleManager.shared.disconnect(serverID: serverID)
                ProtocolModuleManager.shared.removeInstance(serverID: serverID)
                
                DispatchQueue.main.async {
                    self.mountedServers.remove(serverID)
                    self.mountErrors[serverID] = nil
                    NotificationCenter.default.post(name: .MountStatusChanged, object: nil)
                    completion(.success(()))
                }
                
            } catch {
                if force {
                    // 强制卸载
                    let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID)
                    if let mountPath = config?.getMountPath() {
                        let result = DiskAPI.shared.forceUnmount(mountPath: mountPath)
                        if result {
                            ProtocolModuleManager.shared.removeInstance(serverID: serverID)
                            DispatchQueue.main.async {
                                self.mountedServers.remove(serverID)
                                self.mountErrors[serverID] = nil
                                NotificationCenter.default.post(name: .MountStatusChanged, object: nil)
                                completion(.success(()))
                            }
                            return
                        }
                    }
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    // MARK: - 状态查询
    func getMountedServers() -> Set<String> {
        return mountedServers
    }
    
    func getMountCount() -> Int {
        return mountedServers.count
    }
    
    func getMountError(serverID: String) -> String? {
        return mountErrors[serverID]
    }
    
    // MARK: - 实例查询（委托给 ProtocolModuleManager）
    // MountManager.swift
    // 第 148 行附近

    func getMountInstance(serverID: String) -> MountInstance? {
        guard let module = ProtocolModuleManager.shared.getInstance(serverID: serverID),
              let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
            return nil
        }
        
        let mountPath = config.getMountPath()
        let _ = mountedServers.contains(serverID)
        let status = ProtocolModuleManager.shared.getConnectionStatus(serverID: serverID)
        
        let instance = MountInstance(
            serverID: serverID,
            config: config,
            module: module
        )
        instance.mountPath = mountPath
        instance.state = status
        
        return instance
    }
    
    func getAllMountInstances() -> [MountInstance] {
        let allInstances = ProtocolModuleManager.shared.getAllInstances()
        return allInstances.compactMap { serverID, module in
            guard let config = ProtocolModuleManager.shared.getInstanceConfig(serverID: serverID) else {
                return nil
            }
            let instance = MountInstance(serverID: serverID, config: config, module: module)
            instance.mountPath = config.getMountPath()
            instance.state = ProtocolModuleManager.shared.getConnectionStatus(serverID: serverID)
            return instance
        }
    }
    
    // MARK: - 事件处理
    func handleConnectionStateChange(serverID: String, state: ConnectionState, error: String?) {
        ProtocolModuleManager.shared.updateConnectionStatus(serverID: serverID, status: state)
        
        EventBus.shared.publish(
            ConnectionStateChanged(
                serverID: serverID,
                state: state,
                error: error
            )
        )
    }
}

// MARK: - 挂载实例
class MountInstance {
    let serverID: String
    let config: ServerConfig
    let module: ProtocolModule
    var mountPath: String = ""
    var state: ConnectionState = .idle
    var retryCount: Int = 0
    
    init(serverID: String, config: ServerConfig, module: ProtocolModule) {
        self.serverID = serverID
        self.config = config
        self.module = module
    }
    
    func updateState(_ state: ConnectionState, error: String? = nil) {
        self.state = state
    }
}
