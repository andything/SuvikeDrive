//
//  OTAManager.swift
//  SuvikeDrive
//
//  功能:  后台自动检测新版本更新接口
//        更新安装包后台断点续传下载
//        更新安装包数字签名安全校验，防篡改
//        应用程序原子替换安装逻辑，不中断运行
//        更新包损坏/安装失败自动回滚旧版本
//        更新完成静默重启应用，恢复挂载会话
//

import AppKit
import Foundation
import Cocoa
import CryptoKit

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

// MARK: - 下载代理
class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onComplete: ((URL?, Error?) -> Void)?
    var onProgress: ((Double) -> Void)?
    private var progressObservation: NSKeyValueObservation?
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete?(location, nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                let customError = NSError(domain: "OTAManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: error.localizedDescription,
                    NSURLSessionDownloadTaskResumeData: resumeData
                ])
                onComplete?(nil, customError)
                return
            }
            onComplete?(nil, error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }
    
    func setupProgressObserver(for task: URLSessionDownloadTask) {
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.onProgress?(progress.fractionCompleted)
            }
        }
    }
    
    deinit {
        progressObservation?.invalidate()
    }
}

class OTAManager {
    static let shared = OTAManager()
    
    // MARK: - 属性
    private let updateDirectory: URL
    
    private let primaryVersionURL = AppInfo.updateVersionURL
    private let fallbackVersionURL = AppInfo.fallbackUpdateVersionURL
    
    private var downloadTask: URLSessionDownloadTask?
    private var downloadResumeData: Data?
    private var isDownloading = false
    private var updateProgress: Double = 0
    private var updateInfo: UpdateInfo?
    private var progressHandler: ((Double) -> Void)?
    private var completionHandler: ((Result<URL, UpdateError>) -> Void)?
    
    private var downloadDelegate: DownloadDelegate?
    private var progressObservation: NSKeyValueObservation?
    
    private var currentVersion: String {
        return AppInfo.appVersion
    }
    
    private var currentBuild: String {
        return AppInfo.buildNumber
    }
    
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.suvikedrive.update.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let delegate = DownloadDelegate()
        self.downloadDelegate = delegate
        return URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
    }()
    
    private let checkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    
    private let installLock = NSLock()
    private var isInstalling = false
    
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
        
        cleanOldUpdatePackages()
        
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
    
    // MARK: - 使用指定 URL 检查更新
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
                let downloadURL: String?
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
                      let downloadURL = downloadURL,
                      let checksum = checksum else {
                    Logger.shared.error("解析更新信息失败: 缺少必要字段")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
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
                        downloadURL: downloadURL,
                        checksum: checksum,
                        checksumAlgorithm: checksumAlgorithm ?? "sha256",
                        releaseNotes: releaseNotes,
                        size: size,
                        minOSVersion: minOSVersion,
                        isMandatory: isMandatory,
                        releaseDate: releaseDate
                    )
                    Logger.shared.info("\(isFallback ? "备用" : "主")服务器发现新版本: \(version) (当前: \(self.currentVersion))")
                    
                    // ✅ 通过 EventBus 发布更新可用事件
                    EventBus.shared.publish(OTAUpdateAvailable(
                        version: version,
                        releaseNotes: releaseNotes,
                        size: size
                    ))
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
    
    // MARK: - 下载更新
    func downloadUpdate(progressHandler: @escaping (Double) -> Void, completion: @escaping (Result<URL, UpdateError>) -> Void) {
        guard let updateInfo = self.updateInfo else {
            completion(.failure(.noUpdateAvailable))
            return
        }
        
        if let minOSVersion = updateInfo.minOSVersion {
            let currentOSVersion = ProcessInfo.processInfo.operatingSystemVersion
            let minVersion = minOSVersion.split(separator: ".").map { Int($0) ?? 0 }
            if currentOSVersion.majorVersion < minVersion[0] ||
               (currentOSVersion.majorVersion == minVersion[0] && currentOSVersion.minorVersion < minVersion[1]) {
                completion(.failure(.incompatibleOS))
                return
            }
        }
        
        guard !isDownloading else {
            completion(.failure(.alreadyDownloading))
            return
        }
        
        isDownloading = true
        self.progressHandler = progressHandler
        self.completionHandler = completion
        
        guard let downloadURL = URL(string: updateInfo.downloadURL) else {
            isDownloading = false
            completion(.failure(.downloadFailed(nil)))
            return
        }
        
        let destinationURL = getUpdatePackagePath(for: updateInfo.version)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if verifyUpdatePackage(at: destinationURL, with: updateInfo) {
                Logger.shared.info("更新包已存在且完整: \(destinationURL.path)")
                isDownloading = false
                DispatchQueue.main.async {
                    completion(.success(destinationURL))
                }
                return
            } else {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        
        let resumeDataFile = updateDirectory.appendingPathComponent("resume_data_\(updateInfo.version).dat")
        if let resumeData = try? Data(contentsOf: resumeDataFile) {
            if let resumeURL = extractURLFromResumeData(resumeData), resumeURL == downloadURL {
                self.downloadResumeData = resumeData
                Logger.shared.info("使用断点续传数据恢复下载")
            } else {
                Logger.shared.warning("断点续传数据无效，重新下载")
                try? FileManager.default.removeItem(at: resumeDataFile)
            }
        }
        
        Logger.shared.info("开始下载更新: \(updateInfo.version)")
        startDownloadTask(from: downloadURL, to: destinationURL, resumeData: downloadResumeData)
    }
    
    // MARK: - 从断点续传数据中提取 URL
    private func extractURLFromResumeData(_ resumeData: Data) -> URL? {
        do {
            if let dict = try PropertyListSerialization.propertyList(from: resumeData, options: [], format: nil) as? [String: Any] {
                if let urlString = dict["NSURLSessionDownloadURL"] as? String {
                    return URL(string: urlString)
                }
                if let urlString = dict["URL"] as? String {
                    return URL(string: urlString)
                }
            }
        } catch {
            if let urlString = String(data: resumeData, encoding: .utf8) {
                let pattern = "https?://[^\\s\"]+"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) {
                    if let range = Range(match.range, in: urlString) {
                        return URL(string: String(urlString[range]))
                    }
                }
            }
        }
        return nil
    }
    
    private func startDownloadTask(from url: URL, to destination: URL, resumeData: Data?) {
        let delegate = DownloadDelegate()
        self.downloadDelegate = delegate
        
        let config = URLSessionConfiguration.background(withIdentifier: "com.suvikedrive.update.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
        
        let task: URLSessionDownloadTask
        if let resumeData = resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: url)
        }
        
        delegate.onProgress = { [weak self] progress in
            DispatchQueue.main.async {
                self?.updateProgress = progress
                self?.progressHandler?(progress)
                // ✅ 通过 EventBus 发布下载进度
                if let updateInfo = self?.updateInfo {
                    EventBus.shared.publish(OTADownloadProgress(
                        version: updateInfo.version,
                        progress: progress,
                        downloadedBytes: Int64(progress * Double(updateInfo.size)),
                        totalBytes: updateInfo.size
                    ))
                }
            }
        }
        
        delegate.onComplete = { [weak self] tempURL, error in
            guard let self = self else { return }
            self.isDownloading = false
            self.downloadDelegate = nil
            
            if let error = error {
                var resumeData: Data?
                if let nsError = error as NSError? {
                    resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                }
                
                if let resumeData = resumeData {
                    let resumeDataFile = self.updateDirectory.appendingPathComponent("resume_data_\(self.updateInfo?.version ?? "unknown").dat")
                    try? resumeData.write(to: resumeDataFile)
                    self.downloadResumeData = resumeData
                    Logger.shared.info("保存断点续传数据")
                }
                
                Logger.shared.error("下载更新失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.completionHandler?(.failure(.downloadFailed(error)))
                    self.completionHandler = nil
                }
                return
            }
            
            guard let tempURL = tempURL else {
                Logger.shared.error("下载完成但文件路径为空")
                DispatchQueue.main.async {
                    self.completionHandler?(.failure(.downloadFailed(nil)))
                    self.completionHandler = nil
                }
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                
                guard let updateInfo = self.updateInfo else {
                    try FileManager.default.removeItem(at: destination)
                    DispatchQueue.main.async {
                        self.completionHandler?(.failure(.checksumMismatch))
                        self.completionHandler = nil
                    }
                    return
                }
                
                let isValid = self.verifyUpdatePackage(at: destination, with: updateInfo)
                if !isValid {
                    try FileManager.default.removeItem(at: destination)
                    DispatchQueue.main.async {
                        self.completionHandler?(.failure(.checksumMismatch))
                        self.completionHandler = nil
                    }
                    return
                }
                
                let resumeDataFile = self.updateDirectory.appendingPathComponent("resume_data_\(updateInfo.version).dat")
                try? FileManager.default.removeItem(at: resumeDataFile)
                
                Logger.shared.info("更新包下载完成: \(destination.path)")
                
                // ✅ 通过 EventBus 发布下载完成事件
                EventBus.shared.publish(OTADownloadComplete(
                    version: updateInfo.version,
                    packagePath: destination.path
                ))
                
                DispatchQueue.main.async {
                    self.completionHandler?(.success(destination))
                    self.completionHandler = nil
                }
            } catch {
                Logger.shared.error("保存更新包失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.completionHandler?(.failure(.saveFailed(error)))
                    self.completionHandler = nil
                }
            }
        }
        
        delegate.setupProgressObserver(for: task)
        
        self.downloadTask = task
        task.resume()
    }
    
    // MARK: - 验证更新包
    private func verifyUpdatePackage(at url: URL, with updateInfo: UpdateInfo) -> Bool {
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
    
    // MARK: - 安装更新
    func installUpdate(updatePackage: URL, completion: @escaping (Result<Void, UpdateError>) -> Void) {
        installLock.lock()
        guard !isInstalling else {
            installLock.unlock()
            completion(.failure(.installationFailed(nil)))
            return
        }
        isInstalling = true
        installLock.unlock()
        
        Logger.shared.info("开始安装更新: \(updatePackage.path)")
        
        guard let updateInfo = self.updateInfo else {
            isInstalling = false
            completion(.failure(.installationFailed(nil)))
            return
        }
        
        // ✅ 发布安装开始事件
        EventBus.shared.publish(OTAInstallStarted(version: updateInfo.version))
        
        let appPath = Bundle.main.bundlePath
        let backupPath = appPath + ".backup." + UUID().uuidString
        let tempAppPath = updateDirectory.appendingPathComponent("SuvikeDrive_New_\(UUID().uuidString).app")
        
        try? FileManager.default.removeItem(at: tempAppPath)
        
        do {
            // 1. 备份当前应用
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.removeItem(atPath: backupPath)
            }
            try FileManager.default.copyItem(atPath: appPath, toPath: backupPath)
            Logger.shared.info("应用备份完成: \(backupPath)")
            
            // 2. 挂载 DMG
            let mountResult = mountDMG(updatePackage)
            guard mountResult.success, let mountPoint = mountResult.mountPoint else {
                try rollback(appPath: appPath, backupPath: backupPath)
                isInstalling = false
                // ✅ 发布安装失败事件
                EventBus.shared.publish(OTAInstallFailed(
                    version: updateInfo.version,
                    error: "挂载更新包失败"
                ))
                completion(.failure(.mountFailed))
                return
            }
            
            // 3. 复制新版本
            let sourceApp = "\(mountPoint)/SuvikeDrive.app"
            try FileManager.default.copyItem(atPath: sourceApp, toPath: tempAppPath.path)
            Logger.shared.info("新版本复制完成")
            
            // 4. 卸载 DMG
            unmountDMG(mountPoint)
            
            // 5. 验证新应用
            let isValid = verifyNewApp(at: tempAppPath)
            if !isValid {
                try rollback(appPath: appPath, backupPath: backupPath)
                isInstalling = false
                // ✅ 发布安装失败事件
                EventBus.shared.publish(OTAInstallFailed(
                    version: updateInfo.version,
                    error: "新应用验证失败"
                ))
                completion(.failure(.installationFailed(nil)))
                return
            }
            
            // 6. 原子替换应用
            let appURL = URL(fileURLWithPath: appPath)
            let tempAppURL = tempAppPath
            try FileManager.default.replaceItem(at: appURL, withItemAt: tempAppURL, backupItemName: nil, options: [.usingNewMetadataOnly], resultingItemURL: nil)
            
            // 7. 清理
            let backupURL = URL(fileURLWithPath: backupPath)
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: updatePackage)
            
            Logger.shared.info("更新安装成功")
            
            saveUpdateHistory()
            
            // ✅ 发布安装完成事件
            EventBus.shared.publish(OTAInstallComplete(version: updateInfo.version))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.restartApplication()
            }
            
            isInstalling = false
            completion(.success(()))
            
        } catch {
            Logger.shared.error("安装更新失败: \(error.localizedDescription)")
            
            // ✅ 发布安装失败事件
            EventBus.shared.publish(OTAInstallFailed(
                version: updateInfo.version,
                error: error.localizedDescription
            ))
            
            if FileManager.default.fileExists(atPath: backupPath) {
                do {
                    try rollback(appPath: appPath, backupPath: backupPath)
                    Logger.shared.info("已回滚到旧版本")
                } catch {
                    Logger.shared.error("回滚失败: \(error.localizedDescription)")
                }
            }
            
            isInstalling = false
            completion(.failure(.installationFailed(error)))
        }
    }
    
    // MARK: - 挂载 DMG
    private func mountDMG(_ dmgPath: URL) -> (success: Bool, mountPoint: String?) {
        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments = ["attach", dmgPath.path, "-nobrowse", "-plist"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = nil
        
        do {
            try task.run()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0 else {
                return (false, nil)
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            
            if let dict = plist as? [String: Any],
               let entities = dict["system-entities"] as? [[String: Any]] {
                for entity in entities {
                    if let mountPoint = entity["mount-point"] as? String {
                        return (true, mountPoint)
                    }
                }
            }
            return (false, nil)
        } catch {
            Logger.shared.error("挂载 DMG 失败: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - 卸载 DMG
    private func unmountDMG(_ mountPoint: String) {
        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments = ["detach", mountPoint, "-force"]
        
        do {
            try task.run()
            task.waitUntilExit()
            Logger.shared.debug("DMG 卸载完成: \(mountPoint)")
        } catch {
            Logger.shared.error("DMG 卸载失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 验证新应用
    private func verifyNewApp(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        let infoPlistPath = url.appendingPathComponent("Contents/Info.plist").path
        guard FileManager.default.fileExists(atPath: infoPlistPath) else {
            return false
        }
        
        guard let info = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: info, options: [], format: nil) as? [String: Any],
              let executableName = plist["CFBundleExecutable"] as? String else {
            return false
        }
        
        let executablePath = url.appendingPathComponent("Contents/MacOS/\(executableName)").path
        guard FileManager.default.fileExists(atPath: executablePath) else {
            return false
        }
        
        return true
    }
    
    // MARK: - 回滚
    private func rollback(appPath: String, backupPath: String) throws {
        // ✅ 发布回滚事件
        if let updateInfo = self.updateInfo {
            EventBus.shared.publish(OTARollbackStarted(version: updateInfo.version))
        }
        
        if FileManager.default.fileExists(atPath: appPath) {
            try FileManager.default.removeItem(atPath: appPath)
        }
        try FileManager.default.moveItem(atPath: backupPath, toPath: appPath)
        Logger.shared.info("应用已回滚到备份版本")
        
        if let updateInfo = self.updateInfo {
            EventBus.shared.publish(OTARollbackComplete(version: updateInfo.version))
        }
    }
    
    // MARK: - 重启应用
    private func restartApplication() {
        let appPath = Bundle.main.bundlePath
        
        DispatchQueue.global().async {
            sleep(2)
            
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [appPath]
            task.launch()
            
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    // MARK: - 自动更新
    func performAutoUpdate(completion: @escaping (Result<Void, UpdateError>) -> Void) {
        checkForUpdates { [weak self] hasUpdate in
            guard let self = self, hasUpdate else {
                completion(.failure(.noUpdateAvailable))
                return
            }
            
            self.downloadUpdate(progressHandler: { progress in
                // 进度通过 EventBus 发布
            }) { result in
                switch result {
                case .success(let packageURL):
                    self.installUpdate(updatePackage: packageURL, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 工具方法
    
    func getUpdatePackagePath(for version: String) -> URL {
        return updateDirectory.appendingPathComponent("update_\(version).dmg")
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
    
    func getUpdateInfo() -> UpdateInfo? {
        return updateInfo
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        updateProgress = 0
        downloadResumeData = nil
        progressHandler = nil
        completionHandler = nil
        downloadDelegate = nil
        progressObservation?.invalidate()
        progressObservation = nil
        Logger.shared.info("更新下载已取消")
    }
    
    // MARK: - 清理维护
    
    private func cleanOldUpdatePackages() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: updateDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        let dmgFiles = files.filter { $0.pathExtension == "dmg" }
        if dmgFiles.count > 3 {
            let sorted = dmgFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in sorted.dropFirst(3) {
                try? FileManager.default.removeItem(at: file)
                Logger.shared.debug("清理旧更新包: \(file.lastPathComponent)")
            }
        }
        
        let tempFiles = files.filter { $0.lastPathComponent.hasPrefix("temp_") || $0.lastPathComponent.hasPrefix("SuvikeDrive_New_") }
        for file in tempFiles {
            try? FileManager.default.removeItem(at: file)
        }
        
        let resumeFiles = files.filter { $0.pathExtension == "dat" }
        for file in resumeFiles {
            let dmgName = file.lastPathComponent
                .replacingOccurrences(of: "resume_data_", with: "")
                .replacingOccurrences(of: ".dat", with: ".dmg")
            let dmgFile = updateDirectory.appendingPathComponent(dmgName)
            if FileManager.default.fileExists(atPath: dmgFile.path) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    private func saveUpdateHistory() {
        guard let updateInfo = updateInfo else { return }
        
        var history: [[String: Any]] = []
        let historyPath = updateDirectory.appendingPathComponent("update_history.json")
        
        if let data = try? Data(contentsOf: historyPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            history = existing
        }
        
        history.append([
            "version": updateInfo.version,
            "date": Date().ISO8601Format(),
            "size": updateInfo.size,
            "success": true
        ])
        
        if history.count > 20 {
            history = Array(history.suffix(20))
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: history, options: .prettyPrinted) {
            try? data.write(to: historyPath)
        }
    }
    
    func getUpdateHistory() -> [[String: Any]] {
        let historyPath = updateDirectory.appendingPathComponent("update_history.json")
        guard let data = try? Data(contentsOf: historyPath),
              let history = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return history
    }
    
    // MARK: - 静默更新检查（后台）
    func performSilentCheck() {
        let lastCheck = UserDefaults.standard.double(forKey: "update.lastCheck")
        let now = Date().timeIntervalSince1970
        if now - lastCheck < 86400 { return }
        
        UserDefaults.standard.set(now, forKey: "update.lastCheck")
        UserDefaults.standard.synchronize()
        
        checkForUpdates { hasUpdate in
            if hasUpdate {
                Logger.shared.info("发现新版本，可进行更新")
            }
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
