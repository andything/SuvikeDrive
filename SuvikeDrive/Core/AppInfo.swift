//
//  AppInfo.swift
//  SuvikeDrive
//
//  功能: 应用全局信息统一管理
//
//

import Foundation

struct AppInfo {
    // MARK: - 应用信息
    static let appName = "SuvikeDrive"
    static let appDescription = "远程磁盘同步助手"
    
    // MARK: - 版本信息
    static var appVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    static var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    static var fullVersion: String {
        return "版本 \(appVersion) (Build \(buildNumber))"
    }
    
    // MARK: - 作者信息
    static let author = "andything"
    static let email = "andything@yiqipro.com"
    static let website = "www.yiqipro.com"
    static let websiteURL = "https://www.yiqipro.com"
    static let helpURL = "https://yiqipro.com/help"
    static let feedbackEmail = "mailto:andything@yiqipro.com"
    
    // MARK: - 版权信息
    static let copyrightYear = "2026"
    static let copyrightOwner = "Suvike"
    static var copyright: String {
        return "© \(copyrightYear) \(copyrightOwner). All rights reserved."
    }
    
    // MARK: - 系统信息
    static var systemVersion: String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    static var processorCount: Int {
        return ProcessInfo.processInfo.processorCount
    }
    
    static var processorInfo: String {
        return "\(processorCount) 核"
    }
    
    static var memorySize: String {
        let memory = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return "\(memory) GB"
    }
    
    // MARK: - Bundle ID
    static var bundleID: String {
        return Bundle.main.bundleIdentifier ?? "com.suvikedrive.drive"
    }
    
    // MARK: - 更新相关 URL
    /// 版本检查地址（GitHub raw）
    static let updateVersionURL = "https://raw.githubusercontent.com/andything/SuvikeDrive/main/version.json"
    
    /// 备用版本检查地址（如果 GitHub 无法访问）
    static let fallbackUpdateVersionURL = "https://api.suvikedrive.com/version"
}
