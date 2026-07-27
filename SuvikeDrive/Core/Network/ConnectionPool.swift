//
//  ConnectionPool.swift
//  SuvikeDrive
//
//  模块功能：TCP长连接池管理
//  职责：复用主机网络连接，限制单主机最大连接数量
//        Connection：单个连接实体，记录连接状态
//  使用场景：后续底层TCP通讯复用，和HTTP请求模块解耦
//  依赖：Foundation
//

import Foundation

// MARK: - 连接池
class ConnectionPool {
    private var connections: [String: Connection] = [:]
    private let maxConnectionsPerHost = 4
    private let queue = DispatchQueue(label: "com.suvikedrive.connectionpool")
    
    func getConnection(host: String, port: Int) -> Connection? {
        queue.sync {
            let key = "\(host):\(port)"
            if let connection = connections[key], connection.isConnected {
                return connection
            }
            
            let hostConnections = connections.values.filter { $0.host == host && $0.isConnected }
            if hostConnections.count >= maxConnectionsPerHost {
                return nil
            }
            
            let connection = Connection(host: host, port: port)
            connections[key] = connection
            return connection
        }
    }
    
    func returnConnection(_ connection: Connection) {
        queue.sync {
            let key = "\(connection.host):\(connection.port)"
            if let existing = connections[key], existing === connection {
                // 保持连接
            }
        }
    }
    
    func cleanup() {
        queue.sync {
            for (key, connection) in connections {
                if !connection.isConnected {
                    connections.removeValue(forKey: key)
                }
            }
        }
    }
}

// MARK: - 连接
class Connection {
    let host: String
    let port: Int
    var isConnected: Bool = false
    var lastUsed: Date = Date()
    private let queue = DispatchQueue(label: "com.suvikedrive.connection")
    
    init(host: String, port: Int) {
        self.host = host
        self.port = port
        connect()
    }
    
    private func connect() {
        queue.async {
            self.isConnected = true
            self.lastUsed = Date()
        }
    }
    
    func disconnect() {
        queue.async {
            self.isConnected = false
        }
    }
}
