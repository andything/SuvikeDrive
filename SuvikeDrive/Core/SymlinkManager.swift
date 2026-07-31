//
//  SymlinkManager.swift
//  SuvikeDrive
//
//  功能: 符号链接管理器
//  职责: 仅负责符号链接的创建、删除、查询，不依赖任何其他模块
//  归属: Core
//

import Foundation
import AppKit

class SymlinkManager {
    static let shared = SymlinkManager()
    private init() {}
    
    private let fileManager = FileManager.default
    
    // MARK: - 常量
    
    /// SuvikeDrive 目录名称
    private static let suvikeDriveFolderName = "SuvikeDrive"
    
    // MARK: - 目录管理
    
    /// 获取用户目录下的 SuvikeDrive 目录
    func getSuvikeDriveDirectory() -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let suvikeDir = home.appendingPathComponent(Self.suvikeDriveFolderName)
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: suvikeDir.path) {
            try? fileManager.createDirectory(at: suvikeDir, withIntermediateDirectories: true)
        }
        
        return suvikeDir
    }
    
    /// 获取 SuvikeDrive 目录路径
    func getSuvikeDrivePath() -> String {
        return getSuvikeDriveDirectory().path
    }
    
    // MARK: - 符号链接操作
    
    /// 创建符号链接
    /// - Parameters:
    ///   - linkName: 链接名称（显示在 SuvikeDrive 目录下的名称）
    ///   - targetPath: 目标路径（实际缓存目录）
    /// - Returns: 符号链接的完整路径
    @discardableResult
    func createSymlink(linkName: String, targetPath: String) throws -> String {
        let suvikeDrive = getSuvikeDriveDirectory()
        let symlinkPath = suvikeDrive.appendingPathComponent(linkName).path
        
        // 验证目标路径是否存在
        guard fileManager.fileExists(atPath: targetPath) else {
            throw SymlinkError.targetNotFound(targetPath)
        }
        
        // 如果符号链接已存在，删除
        if fileManager.fileExists(atPath: symlinkPath) {
            try fileManager.removeItem(atPath: symlinkPath)
        }
        
        // 创建符号链接
        try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)
        
        Logger.shared.info("🔗 符号链接创建成功: \(symlinkPath) → \(targetPath)", module: "SymlinkManager")
        
        return symlinkPath
    }
    
    /// 删除符号链接
    func removeSymlink(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else {
            throw SymlinkError.linkNotFound(path)
        }
        
        guard isSymlink(at: path) else {
            throw SymlinkError.notASymlink(path)
        }
        
        try fileManager.removeItem(atPath: path)
        Logger.shared.info("🗑️ 符号链接已删除: \(path)", module: "SymlinkManager")
    }
    
    /// 删除 SuvikeDrive 目录下的指定符号链接
    func removeSymlink(named linkName: String) throws {
        let symlinkPath = getSuvikeDriveDirectory().appendingPathComponent(linkName).path
        try removeSymlink(at: symlinkPath)
    }
    
    /// 获取符号链接的目标路径
    func getSymlinkTarget(at path: String) -> String? {
        guard isSymlink(at: path) else { return nil }
        return try? fileManager.destinationOfSymbolicLink(atPath: path)
    }
    
    /// 判断路径是否为符号链接
    func isSymlink(at path: String) -> Bool {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
    }
    
    // MARK: - 批量操作
    
    /// 获取 SuvikeDrive 目录下所有符号链接
    func getAllSymlinks() -> [(name: String, target: String)] {
        let suvikeDrive = getSuvikeDriveDirectory()
        
        guard let items = try? fileManager.contentsOfDirectory(at: suvikeDrive, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var result: [(name: String, target: String)] = []
        for item in items {
            let path = item.path
            if isSymlink(at: path) {
                if let target = getSymlinkTarget(at: path) {
                    result.append((name: item.lastPathComponent, target: target))
                }
            }
        }
        return result
    }
    
    /// 清理所有断开的符号链接
    func cleanBrokenSymlinks() -> Int {
        let symlinks = getAllSymlinks()
        var removedCount = 0
        
        for (name, target) in symlinks {
            if !fileManager.fileExists(atPath: target) {
                let linkPath = getSuvikeDriveDirectory().appendingPathComponent(name).path
                try? fileManager.removeItem(atPath: linkPath)
                removedCount += 1
                Logger.shared.warning("🔗 删除断开的符号链接: \(name) → \(target)", module: "SymlinkManager")
            }
        }
        
        return removedCount
    }
}

// MARK: - Errors

enum SymlinkError: LocalizedError {
    case targetNotFound(String)
    case linkNotFound(String)
    case notASymlink(String)
    case createFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .targetNotFound(let path):
            return "目标路径不存在: \(path)"
        case .linkNotFound(let path):
            return "符号链接不存在: \(path)"
        case .notASymlink(let path):
            return "路径不是符号链接: \(path)"
        case .createFailed(let reason):
            return "创建符号链接失败: \(reason)"
        }
    }
}
