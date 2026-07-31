//
//  OTAModels.swift
//  SuvikeDrive
//
//  功能: OTA 数据模型 + 枚举
//

import Foundation

// MARK: - 哈希算法枚举
enum HashAlgorithm: String, CaseIterable {
    case sha256 = "sha256"
    case sha512 = "sha512"
    case md5 = "md5"
    
    var displayName: String {
        switch self {
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        case .md5: return "MD5"
        }
    }
}

// MARK: - 数据模型
struct UpdateInfo {
    let version: String
    let build: String?
    let downloadURL: String
    let checksum: String
    let checksumAlgorithm: String
    let releaseNotes: String?
    let size: Int64
    let minOSVersion: String?
    let isMandatory: Bool
    let releaseDate: String?
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - 更新状态
enum UpdateStatus {
    case idle
    case checking
    case downloading(progress: Double)
    case downloaded(version: String)
    case installing(progress: Double)
    case installed(version: String)
    case error(String)
}

// MARK: - 更新错误
enum UpdateError: Error {
    case noUpdateAvailable
    case alreadyDownloading
    case downloadFailed(Error?)
    case checksumMismatch
    case saveFailed(Error)
    case mountFailed
    case installationFailed(Error?)
    case incompatibleOS
    
    var localizedDescription: String {
        switch self {
        case .noUpdateAvailable:
            return "没有可用更新"
        case .alreadyDownloading:
            return "正在下载中"
        case .downloadFailed(let error):
            return "下载失败: \(error?.localizedDescription ?? "未知错误")"
        case .checksumMismatch:
            return "更新包校验失败，可能已损坏"
        case .saveFailed(let error):
            return "保存更新包失败: \(error.localizedDescription)"
        case .mountFailed:
            return "挂载更新包失败"
        case .installationFailed(let error):
            return "安装失败: \(error?.localizedDescription ?? "未知错误")"
        case .incompatibleOS:
            return "当前系统版本不兼容"
        }
    }
}
