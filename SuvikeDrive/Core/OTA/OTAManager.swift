//
//  OTAManager.swift
//  SuvikeDrive
//
//  功能: OTA 更新管理器 - 主入口 + 检查更新 + 校验
//

import AppKit
import Foundation

class OTAManager {
    static let shared = OTAManager()
    
    // MARK: - 属性
    let updateDirectory: URL
    let primaryVersionURL = AppInfo.updateVersionURL
    let fallbackVersionURL = AppInfo.fallbackUpdateVersionURL
    
    var downloadTask: URLSessionDownloadTask?
    var downloadResumeData: Data?
    var isDownloading = false
    var updateProgress: Double = 0
    var updateInfo: UpdateInfo?
    var progressHandler: ((Double) -> Void)?
    var completionHandler: ((Result<URL, UpdateError>) -> Void)?
    var downloadDelegate: DownloadDelegate?
    var progressObservation: NSKeyValueObservation?
    
    var currentVersion: String { AppInfo.appVersion }
    var currentBuild: String { AppInfo.buildNumber }
    
    let checkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    let installLock = NSLock()
    var isInstalling = false
    
    // MARK: - 初始化
    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent(AppInfo.bundleID)
        updateDirectory = appDir.appendingPathComponent("Updates")
        
        if !FileManager.default.fileExists(atPath: updateDirectory.path) {
            try? FileManager.default.createDirectory(
                at: updateDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        // 异步清理旧包（实现在 OTAManagerInstall.swift 中）
        DispatchQueue.global().async {
            self.cleanOldUpdatePackages()
        }
        
        Logger.shared.info("OTA管理器初始化完成, 当前版本: \(currentVersion) (\(currentBuild))")
        Logger.shared.info("主更新地址: \(primaryVersionURL)")
        Logger.shared.info("备用更新地址: \(fallbackVersionURL)")
    }
    
    // MARK: - 检查更新
    func checkForUpdates(completion: @escaping (Bool) -> Void) {
        checkForUpdates(completion: completion, force: false)
    }
    
    func checkForUpdates(completion: @escaping (Bool) -> Void, force: Bool) {
        Logger.shared.debug("检查更新... (强制: \(force))")
        checkWithURL(primaryVersionURL, isFallback: false, completion: completion, force: force)
    }
    
    private func checkWithURL(_ urlString: String, isFallback: Bool, completion: @escaping (Bool) -> Void, force: Bool) {
        guard let url = URL(string: urlString) else {
            Logger.shared.error("无效的更新检查 URL: \(urlString)")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(currentVersion, forHTTPHeaderField: "X-APP-VERSION")
        request.setValue(currentBuild, forHTTPHeaderField: "X-APP-BUILD")
        request.setValue("macos", forHTTPHeaderField: "X-PLATFORM")
        request.setValue(ProcessInfo.processInfo.operatingSystemVersionString, forHTTPHeaderField: "X-OS-VERSION")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = checkSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                Logger.shared.error("\(isFallback ? "备用" : "主")服务器检查失败: \(error.localizedDescription)")
                if !isFallback {
                    Logger.shared.info("主地址不可用，切换到备用地址...")
                    self.checkWithURL(self.fallbackVersionURL, isFallback: true, completion: completion, force: force)
                } else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
                return
            }
            
            guard let data = data else {
                Logger.shared.error("检查更新: 没有收到数据")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.shared.debug("版本信息 JSON: \(jsonString)")
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                let version: String?
                var downloadURL: String?
                let checksum: String?
                let checksumAlgorithm: String?
                
                if let versionObj = json?["version"] as? [String: Any] {
                    version = versionObj["version"] as? String ?? versionObj["number"] as? String
                    downloadURL = versionObj["downloadUrl"] as? String ?? versionObj["downloadURL"] as? String
                    checksum = versionObj["checksum"] as? String
                    checksumAlgorithm = versionObj["checksumAlgorithm"] as? String ?? "sha256"
                } else {
                    version = json?["version"] as? String
                    downloadURL = json?["downloadURL"] as? String
                    checksum = json?["checksum"] as? String
                    checksumAlgorithm = json?["checksumAlgorithm"] as? String ?? "sha256"
                }
                
                guard let version = version,
                      let checksum = checksum else {
                    Logger.shared.error("解析更新信息失败: 缺少必要字段")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
                
                let standardURL = "https://github.com/andything/SuvikeDrive/releases/download/v\(version)/SuvikeDrive_v\(version).dmg"
                if downloadURL == nil || downloadURL?.isEmpty == true || downloadURL == "null" {
                    downloadURL = standardURL
                    Logger.shared.debug("使用标准下载 URL: \(standardURL)")
                }
                
                let hasUpdate = force || Utils.shared.isVersionNewer(version, self.currentVersion)
                
                if hasUpdate {
                    let build = (json?["build"] as? String) ?? (json?["version"] as? [String: Any])?["build"] as? String
                    let releaseNotes = (json?["releaseNotes"] as? String) ?? (json?["version"] as? [String: Any])?["releaseNotes"] as? String
                    let size = (json?["size"] as? Int64) ?? ((json?["version"] as? [String: Any])?["size"] as? Int64) ?? 0
                    let minOSVersion = (json?["minOSVersion"] as? String) ?? (json?["version"] as? [String: Any])?["minOSVersion"] as? String
                    let isMandatory = (json?["isMandatory"] as? Bool) ?? ((json?["version"] as? [String: Any])?["isMandatory"] as? Bool) ?? false
                    let releaseDate = (json?["releaseDate"] as? String) ?? (json?["version"] as? [String: Any])?["releaseDate"] as? String
                    
                    self.updateInfo = UpdateInfo(
                        version: version,
                        build: build,
                        downloadURL: downloadURL!,
                        checksum: checksum,
                        checksumAlgorithm: checksumAlgorithm ?? "sha256",
                        releaseNotes: releaseNotes,
                        size: size,
                        minOSVersion: minOSVersion,
                        isMandatory: isMandatory,
                        releaseDate: releaseDate
                    )
                    Logger.shared.info("\(isFallback ? "备用" : "主")服务器发现新版本: \(version) (当前: \(self.currentVersion))")
                    
                    let packagePath = self.getUpdatePackagePath(for: version)
                    var isPackageReady = false
                    
                    if FileManager.default.fileExists(atPath: packagePath.path) {
                        if let updateInfo = self.updateInfo {
                            isPackageReady = self.verifyUpdatePackage(at: packagePath, with: updateInfo)
                        }
                    }
                    
                    if isPackageReady {
                        EventBus.shared.publish(OTAPackageReady(
                            version: version,
                            packagePath: packagePath.path
                        ))
                        Logger.shared.info("本地已有完整安装包，直接就绪: \(version)")
                    } else {
                        EventBus.shared.publish(OTAUpdateAvailable(
                            version: version,
                            releaseNotes: releaseNotes,
                            size: size
                        ))
                        Logger.shared.info("需要下载安装包: \(version)")
                    }
                } else {
                    Logger.shared.debug("已是最新版本: \(self.currentVersion)")
                }
                
                DispatchQueue.main.async {
                    completion(hasUpdate)
                }
            } catch {
                Logger.shared.error("解析更新信息失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
        
        task.resume()
    }
    
    // MARK: - 验证更新包
    public func verifyUpdatePackage(at url: URL, with updateInfo: UpdateInfo) -> Bool {
        guard let algorithm = HashAlgorithm(rawValue: updateInfo.checksumAlgorithm) else {
            Logger.shared.warning("未知的校验算法: \(updateInfo.checksumAlgorithm)")
            return false
        }
        
        let isValid = Utils.shared.verifyFileIntegrity(
            filePath: url.path,
            expectedHash: updateInfo.checksum,
            algorithm: algorithm.rawValue
        )
        
        if !isValid {
            Logger.shared.error("更新包校验失败: \(url.path)")
        }
        
        return isValid
    }
    
    // MARK: - 工具方法
    func getUpdatePackagePath(for version: String) -> URL {
        return updateDirectory.appendingPathComponent("update_\(version).dmg")
    }
    
    func getUpdateInfo() -> UpdateInfo? {
        return updateInfo
    }
    
    func getUpdateStatus() -> UpdateStatus {
        if isDownloading {
            return .downloading(progress: updateProgress)
        }
        if let updateInfo = updateInfo {
            let updatePackage = getUpdatePackagePath(for: updateInfo.version)
            if FileManager.default.fileExists(atPath: updatePackage.path) {
                return .downloaded(version: updateInfo.version)
            }
        }
        return .idle
    }
}
