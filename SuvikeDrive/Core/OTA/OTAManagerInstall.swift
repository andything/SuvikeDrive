//
//  OTAManagerInstall.swift
//  SuvikeDrive
//
//  功能: OTA 安装 + 挂载 + 回滚 + 重启 + 清理 + 历史
//

import AppKit
import Foundation

extension OTAManager {
    
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
        
        EventBus.shared.publish(OTAInstallStarted(version: updateInfo.version))
        
        let appPath = Bundle.main.bundlePath
        let backupPath = appPath + ".backup." + UUID().uuidString
        let tempAppPath = updateDirectory.appendingPathComponent("SuvikeDrive_New_\(UUID().uuidString).app")
        
        try? FileManager.default.removeItem(at: tempAppPath)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                if FileManager.default.fileExists(atPath: backupPath) {
                    try FileManager.default.removeItem(atPath: backupPath)
                }
                try FileManager.default.copyItem(atPath: appPath, toPath: backupPath)
                Logger.shared.info("应用备份完成: \(backupPath)")
                
                let mountResult = self.mountDMG(updatePackage)
                guard mountResult.success, let mountPoint = mountResult.mountPoint else {
                    try self.rollback(appPath: appPath, backupPath: backupPath)
                    self.isInstalling = false
                    DispatchQueue.main.async {
                        EventBus.shared.publish(OTAInstallFailed(
                            version: updateInfo.version,
                            error: "挂载更新包失败"
                        ))
                        completion(.failure(.mountFailed))
                    }
                    return
                }
                
                let sourceApp = "\(mountPoint)/SuvikeDrive.app"
                try FileManager.default.copyItem(atPath: sourceApp, toPath: tempAppPath.path)
                Logger.shared.info("新版本复制完成")
                
                self.unmountDMG(mountPoint)
                
                let isValid = self.verifyNewApp(at: tempAppPath)
                if !isValid {
                    try self.rollback(appPath: appPath, backupPath: backupPath)
                    self.isInstalling = false
                    DispatchQueue.main.async {
                        EventBus.shared.publish(OTAInstallFailed(
                            version: updateInfo.version,
                            error: "新应用验证失败"
                        ))
                        completion(.failure(.installationFailed(nil)))
                    }
                    return
                }
                
                let appURL = URL(fileURLWithPath: appPath)
                let tempAppURL = tempAppPath
                
                try FileManager.default.removeItem(at: appURL)
                Logger.shared.info("旧应用已删除")
                
                try FileManager.default.copyItem(at: tempAppURL, to: appURL)
                Logger.shared.info("新应用已安装")
                
                try? FileManager.default.removeItem(at: tempAppURL)
                try? FileManager.default.removeItem(at: updatePackage)
                try? FileManager.default.removeItem(atPath: backupPath)
                
                Logger.shared.info("更新安装成功")
                
                self.saveUpdateHistory()
                self.isInstalling = false
                
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                
                DispatchQueue.main.async {
                    EventBus.shared.publish(OTAInstallComplete(version: updateInfo.version))
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.restartApplication()
                }
                
            } catch {
                Logger.shared.error("安装更新失败: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    EventBus.shared.publish(OTAInstallFailed(
                        version: updateInfo.version,
                        error: error.localizedDescription
                    ))
                }
                
                if FileManager.default.fileExists(atPath: backupPath) {
                    do {
                        try self.rollback(appPath: appPath, backupPath: backupPath)
                        Logger.shared.info("已回滚到旧版本")
                    } catch {
                        Logger.shared.error("回滚失败: \(error.localizedDescription)")
                    }
                }
                
                self.isInstalling = false
                DispatchQueue.main.async {
                    completion(.failure(.installationFailed(error)))
                }
            }
        }
    }
    
    // MARK: - 清理维护
    internal func cleanOldUpdatePackages() {
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
        guard FileManager.default.fileExists(atPath: appPath) else {
            Logger.shared.error("应用不存在: \(appPath)")
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        Logger.shared.info("准备重启应用: \(appPath)")
        let script = "sleep 0.8 && open \"\(appPath)\""
        DispatchQueue.global().async {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "nohup \(script) > /dev/null 2>&1 &"]
            task.launch()
            Logger.shared.info("重启命令已执行")
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    // MARK: - 更新历史
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
    
    // MARK: - 静默检查
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
    
    // MARK: - 自动更新
    func performAutoUpdate(completion: @escaping (Result<Void, UpdateError>) -> Void) {
        checkForUpdates { [weak self] hasUpdate in
            guard let self = self, hasUpdate else {
                completion(.failure(.noUpdateAvailable))
                return
            }
            self.downloadUpdate(progressHandler: { _ in }) { result in
                switch result {
                case .success(let packageURL):
                    self.installUpdate(updatePackage: packageURL, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
