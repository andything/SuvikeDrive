//
//  Utils.swift
//  SuvikeDrive
//
//  功能: 通用工具方法
//

import AppKit
import CryptoKit
import Foundation

class Utils {
    static let shared = Utils()
    
    private init() {}
    
    // MARK: - 路径操作
    func joinPath(_ base: String, _ path: String) -> String {
        if base == "/" {
            return "/" + path
        }
        if base.hasSuffix("/") {
            return base + path
        }
        return base + "/" + path
    }
    
    func normalizePath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        if !path.hasPrefix("/") {
            return "/" + path
        }
        return path
    }
    
    // MARK: - Base64 编码
    func base64Encode(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else {
            return ""
        }
        return data.base64EncodedString()
    }
    
    func base64Decode(_ string: String) -> String? {
        guard let data = Data(base64Encoded: string) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - 文件大小格式化
    func formatFileSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - 日期格式化
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    // MARK: - JSON 操作
    func jsonToString(_ json: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func jsonToString(_ json: [[String: Any]]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func stringToJson(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    func stringToJsonArray(_ string: String) -> [[String: Any]]? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }
    
    // MARK: - 字符串处理
    func trimWhitespace(_ string: String) -> String {
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func isEmpty(_ string: String?) -> Bool {
        return string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
    
    // MARK: - 版本比较（从右边开始）
    func isVersionNewer(_ version1: String, _ version2: String) -> Bool {
        return compareVersion(version1, version2) == .orderedDescending
    }
    
    func compareVersion(_ version1: String, _ version2: String) -> ComparisonResult {
        // 清理版本号
        let v1 = version1.trimmingCharacters(in: .whitespacesAndNewlines)
        let v2 = version2.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果完全相同
        if v1 == v2 {
            return .orderedSame
        }
        
        // 分割版本号
        let parts1 = v1.split(separator: ".").map { String($0) }
        let parts2 = v2.split(separator: ".").map { String($0) }
        
        // 从右边开始比较
        let maxCount = max(parts1.count, parts2.count)
        
        for i in 0..<maxCount {
            let index = maxCount - 1 - i  // 从右边开始
            let part1 = index < parts1.count ? parts1[index] : "0"
            let part2 = index < parts2.count ? parts2[index] : "0"
            
            // 尝试转为数字比较
            if let num1 = Int(part1), let num2 = Int(part2) {
                if num1 > num2 {
                    return .orderedDescending
                } else if num1 < num2 {
                    return .orderedAscending
                }
            } else {
                // 字符串比较（处理 beta、alpha 等）
                let comparison = part1.compare(part2, options: .numeric)
                if comparison != .orderedSame {
                    return comparison
                }
            }
        }
        
        return .orderedSame
    }
    
    // MARK: - Build 号比较
    func isBuildNewer(_ build1: String, _ build2: String) -> Bool {
        let b1 = build1.trimmingCharacters(in: .whitespacesAndNewlines)
        let b2 = build2.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if b1 == b2 {
            return false
        }
        
        // 尝试转为数字比较
        if let num1 = Int(b1), let num2 = Int(b2) {
            return num1 > num2
        }
        
        // 字符串比较
        return b1.compare(b2, options: .numeric) == .orderedDescending
    }
    
    func compareBuild(_ build1: String, _ build2: String) -> ComparisonResult {
        let b1 = build1.trimmingCharacters(in: .whitespacesAndNewlines)
        let b2 = build2.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if b1 == b2 {
            return .orderedSame
        }
        
        // 尝试转为数字比较
        if let num1 = Int(b1), let num2 = Int(b2) {
            if num1 > num2 {
                return .orderedDescending
            } else if num1 < num2 {
                return .orderedAscending
            }
        }
        
        // 字符串比较
        return b1.compare(b2, options: .numeric)
    }
    
    // MARK: - 完整版本比较（版本 + Build）
    func isUpdateAvailable(serverVersion: String, currentVersion: String, serverBuild: String?, currentBuild: String?) -> Bool {
        // 先比较版本号
        let versionResult = compareVersion(serverVersion, currentVersion)
        
        if versionResult == .orderedDescending {
            return true  // 版本号更大
        }
        
        if versionResult == .orderedAscending {
            return false  // 版本号更小
        }
        
        // 版本号相同，比较 Build
        if let serverBuild = serverBuild, let currentBuild = currentBuild {
            return isBuildNewer(serverBuild, currentBuild)
        }
        
        // 服务器有 Build，当前没有 → 有更新
        if serverBuild != nil && currentBuild == nil {
            return true
        }
        
        return false
    }
    
    // MARK: - SHA256 哈希
    func sha256HashOfFile(atPath path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return ""
        }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    func sha256HashOfFile(atURL url: URL) -> String {
        return sha256HashOfFile(atPath: url.path)
    }
    
    func sha256HashOfData(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - 文件完整性校验
    func verifyFileIntegrity(filePath: String, expectedHash: String, algorithm: String = "sha256") -> Bool {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return false
        }
        
        let fileHash = sha256HashOfFile(atPath: filePath)
        return fileHash.lowercased() == expectedHash.lowercased()
    }
    
    func verifyFileIntegrity(url: URL, expectedHash: String, algorithm: String = "sha256") -> Bool {
        return verifyFileIntegrity(filePath: url.path, expectedHash: expectedHash, algorithm: algorithm)
    }
    
    func verifyFileIntegrity(atPath path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            return fileSize > 0
        } catch {
            return false
        }
    }
    
    func verifyFileIntegrity(atURL url: URL) -> Bool {
        return verifyFileIntegrity(atPath: url.path)
    }
    
    func verifyFileIntegrity(atPath path: String, expectedHash: String) -> Bool {
        return verifyFileIntegrity(filePath: path, expectedHash: expectedHash)
    }
    
    func verifyFileIntegrity(atURL url: URL, expectedHash: String) -> Bool {
        return verifyFileIntegrity(filePath: url.path, expectedHash: expectedHash)
    }
    
    // MARK: - URL 验证
    func validateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    func validateURLString(_ urlString: String) -> Bool {
        return validateURL(urlString)
    }
    
    // MARK: - 随机字符串
    func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
    
    func randomUUID() -> String {
        return UUID().uuidString
    }
    
    // MARK: - 沙盒路径
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func getCachesDirectory() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func getApplicationSupportDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func getTempDirectory() -> URL {
        return FileManager.default.temporaryDirectory
    }
    
    // MARK: - 文件操作
    func fileExists(atPath path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    func createDirectory(atPath path: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
    
    func deleteFile(atPath path: String) -> Bool {
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
    
    func copyFile(fromPath: String, toPath: String) -> Bool {
        do {
            try FileManager.default.copyItem(atPath: fromPath, toPath: toPath)
            return true
        } catch {
            return false
        }
    }
    
    func moveFile(fromPath: String, toPath: String) -> Bool {
        do {
            try FileManager.default.moveItem(atPath: fromPath, toPath: toPath)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - URL 编码
    func urlEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
    
    func urlDecode(_ string: String) -> String {
        return string.removingPercentEncoding ?? string
    }
    
    // MARK: - 获取应用信息
    func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    func getAppBuild() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    func getAppName() -> String {
        return Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "SuvikeDrive"
    }
    
    // MARK: - 延迟执行
    func delay(seconds: TimeInterval, closure: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            closure()
        }
    }
    
    // MARK: - 主线程执行
    func runOnMain(_ closure: @escaping () -> Void) {
        if Thread.isMainThread {
            closure()
        } else {
            DispatchQueue.main.async {
                closure()
            }
        }
    }
    
    func runOnBackground(_ closure: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async {
            closure()
        }
    }
}
