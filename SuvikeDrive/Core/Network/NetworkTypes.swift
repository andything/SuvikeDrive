//
//  NetworkTypes.swift
//  SuvikeDrive
//
//  模块功能：网络层公共类型定义仓库
//  职责：存放所有网络相关枚举、结构体、错误模型
//  说明：所有网络业务模块统一引用本文件，消除类型重复定义
//        包含：HTTP请求方法、网络状态、网络错误、连接测试结果模型
//

import Foundation

// MARK: - NetworkTestResult
struct NetworkTestResult {
    let success: Bool
    let message: String
    let details: [String: String]
    let timestamp: Date
    
    init(success: Bool, message: String, details: [String: String], timestamp: Date = Date()) {
        self.success = success
        self.message = message
        self.details = details
        self.timestamp = timestamp
    }
}

// MARK: - NetworkStatus
enum NetworkStatus {
    case connected
    case disconnected
    case unknown
}

// MARK: - HTTP方法
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
    case patch = "PATCH"
}

// MARK: - 网络错误
enum NetworkError: Error {
    case timeout
    case connectionFailed
    case connectionLost
    case noInternetConnection
    case sslError
    case untrustedCertificate
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case requestFailed(Error)
    case invalidRequestBody
    case decodingError(Error)
    case downloadFailed(Error?)
    case uploadFailed(Error?)
    case fileOperationFailed(Error)
    
    var localizedDescription: String {
        switch self {
        case .timeout:
            return "请求超时"
        case .connectionFailed:
            return "连接失败"
        case .connectionLost:
            return "连接丢失"
        case .noInternetConnection:
            return "无网络连接"
        case .sslError:
            return "SSL错误"
        case .untrustedCertificate:
            return "证书不受信任"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code, let message):
            return "HTTP错误 \(code): \(message)"
        case .requestFailed(let error):
            return "请求失败: \(error.localizedDescription)"
        case .invalidRequestBody:
            return "无效的请求体"
        case .decodingError(let error):
            return "解码错误: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "下载失败: \(error?.localizedDescription ?? "未知错误")"
        case .uploadFailed(let error):
            return "上传失败: \(error?.localizedDescription ?? "未知错误")"
        case .fileOperationFailed(let error):
            return "文件操作失败: \(error.localizedDescription)"
        }
    }
}

