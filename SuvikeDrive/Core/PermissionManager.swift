//
//  PermissionManager.swift
//  SuvikeDrive
//
//  功能:  系统磁盘完全访问权限申请、状态校验
//        全局网络访问权限、防火墙权限管理
//        macOS开机自启权限注册、启用/关闭控制
//        全类型权限实时状态查询接口，弹窗引导授权
//

import AppKit
import Foundation
import Cocoa
import Darwin
import ServiceManagement
import UserNotifications

class PermissionManager {
    static let shared = PermissionManager()
    
    private var permissionCallbacks: [String: (Bool) -> Void] = [:]
    private let permissionQueue = DispatchQueue(label: "com.suvikedrive.permissions")
    
    private init() {}
    
    // MARK: - 权限类型
    enum PermissionType: String {
        case diskAccess = "disk_access"
        case networkAccess = "network_access"
        case startAtLogin = "start_at_login"
        case notifications = "notifications"
        case fullDiskAccess = "full_disk_access"
    }
    
    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
        case restricted
    }
    
    // MARK: - 请求所有权限
    func requestAllPermissions(completion: ((Bool) -> Void)? = nil) {
        Logger.shared.info("开始请求所有权限")
        
        let group = DispatchGroup()
        var allGranted = true
        
        group.enter()
        requestDiskAccess { granted in
            if !granted { allGranted = false }
            group.leave()
        }
        
        group.enter()
        requestNetworkAccess { granted in
            if !granted { allGranted = false }
            group.leave()
        }
        
        group.enter()
        requestNotifications { granted in
            if !granted { allGranted = false }
            group.leave()
        }
        
        group.notify(queue: .main) {
            Logger.shared.info("所有权限请求完成，全部授予: \(allGranted)")
            completion?(allGranted)
        }
    }
    
    // MARK: - 磁盘访问权限
    func requestDiskAccess(completion: @escaping (Bool) -> Void) {
        let status = checkDiskAccess()
        
        switch status {
        case .granted:
            Logger.shared.debug("磁盘访问权限已授予")
            completion(true)
        case .denied, .restricted:
            Logger.shared.warning("磁盘访问权限被拒绝")
            showPermissionAlert(type: .diskAccess)
            completion(false)
        case .notDetermined:
            Logger.shared.info("磁盘访问权限未确定，引导用户设置")
            showSystemSettingsGuide(for: .diskAccess)
            completion(false)
        }
    }
    
    func checkDiskAccess() -> PermissionStatus {
        let testPath = "/Users"
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: testPath)
            if !contents.isEmpty {
                return .granted
            }
        } catch {
            return .denied
        }
        
        return .notDetermined
    }
    
    // MARK: - 全盘访问权限
    func requestFullDiskAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 10.15, *) {
            let status = checkFullDiskAccess()
            
            if status == .granted {
                Logger.shared.debug("完全磁盘访问权限已授予")
                completion(true)
            } else {
                Logger.shared.warning("需要完全磁盘访问权限")
                showFullDiskAccessGuide(completion: completion)
            }
        } else {
            completion(checkDiskAccess() == .granted)
        }
    }
    
    func checkFullDiskAccess() -> PermissionStatus {
        let fileManager = FileManager.default
        
        let testPaths = [
            "/Library/Application Support/com.apple.TCC",
            "/Library/Preferences",
            "/Library/Logs"
        ]
        
        for path in testPaths {
            do {
                _ = try fileManager.contentsOfDirectory(atPath: path)
                return .granted
            } catch {
                continue
            }
        }
        
        let testDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .path
        
        let testFile = (testDir as NSString).appendingPathComponent(".suvikedrive_permission_test")
        
        do {
            try "test".write(toFile: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFile)
            return .granted
        } catch {
            return .denied
        }
    }
    
    func showFullDiskAccessGuide(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要完全磁盘访问权限"
            alert.informativeText = """
            SuvikeDrive 需要完全磁盘访问权限才能挂载和访问远程服务器文件。
            
            请按以下步骤操作：
            1. 点击「打开设置」按钮
            2. 在「隐私与安全性」→「完全磁盘访问」中
            3. 点击「+」添加 SuvikeDrive.app
            4. 重新启动 SuvikeDrive
            
            授权后应用将自动获得权限。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "稍后")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let settingsURLs = [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess"
                ]
                
                for urlString in settingsURLs {
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                        break
                    }
                }
                
                self.startMonitoringFullDiskAccess(completion: completion)
            } else {
                completion(false)
            }
        }
    }
    
    private func startMonitoringFullDiskAccess(completion: @escaping (Bool) -> Void) {
        var attempts = 0
        let maxAttempts = 30
        var lastKnownState: Bool? = nil
        
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            attempts += 1
            
            DispatchQueue.main.async {
                let isGranted = self.checkFullDiskAccess() == .granted
                
                // ✅ 检测到状态变化时，通过 EventBus 通知
                if let lastState = lastKnownState, lastState != isGranted {
                    Logger.shared.info("📋 [权限状态变化] 全盘访问: \(isGranted ? "已授权 ✅" : "未授权 ❌")")
                    // ✅ 发布 EventBus 事件
                    EventBus.shared.publish(PermissionStatusUpdated(
                        permissionType: "full_disk_access",
                        isGranted: isGranted
                    ))
                }
                lastKnownState = isGranted
                
                if isGranted {
                    timer.invalidate()
                    Logger.shared.info("完全磁盘访问权限已授予 ✅")
                    completion(true)
                    return
                }
                
                if attempts >= maxAttempts {
                    timer.invalidate()
                    Logger.shared.warning("完全磁盘访问权限授予超时 ⏰")
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - 网络访问权限
    func requestNetworkAccess(completion: @escaping (Bool) -> Void) {
        let status = checkNetworkAccess()
        
        switch status {
        case .granted:
            Logger.shared.debug("网络访问权限已授予")
            completion(true)
        case .denied, .restricted:
            Logger.shared.warning("网络访问权限被拒绝")
            showPermissionAlert(type: .networkAccess)
            completion(false)
        case .notDetermined:
            Logger.shared.info("网络访问权限未确定，尝试触发授权")
            triggerNetworkPermissionRequest { granted in
                completion(granted)
            }
        }
    }
    
    func checkNetworkAccess() -> PermissionStatus {
        let host = "apple.com"
        let port = 443
        
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        
        if let hostEntry = gethostbyname(host) {
            address.sin_addr = hostEntry.pointee.h_addr_list.pointee?.withMemoryRebound(
                to: in_addr.self,
                capacity: 1
            ) { $0.pointee } ?? in_addr()
        }
        
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        close(socket)
        return result == 0 ? .granted : .denied
    }
    
    private func triggerNetworkPermissionRequest(completion: @escaping (Bool) -> Void) {
        let url = URL(string: "https://apple.com")!
        let task = URLSession.shared.dataTask(with: url) { _, response, error in
            if error == nil {
                Logger.shared.debug("网络权限已授予")
                completion(true)
            } else {
                Logger.shared.warning("网络权限被拒绝")
                completion(false)
            }
        }
        task.resume()
    }
    
    // MARK: - 通知权限
    func requestNotifications(completion: @escaping (Bool) -> Void) {
        if #available(macOS 10.14, *) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        Logger.shared.error("请求通知权限失败: \(error.localizedDescription)")
                        completion(false)
                        return
                    }
                    completion(granted)
                }
            }
        } else {
            completion(false)
        }
    }

    func checkNotifications() -> Bool {
        if #available(macOS 10.14, *) {
            let semaphore = DispatchSemaphore(value: 0)
            var isGranted = false
            
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                isGranted = settings.authorizationStatus == .authorized
                semaphore.signal()
            }
            
            _ = semaphore.wait(timeout: .now() + 1.0)
            return isGranted
        }
        return false
    }
    
    // MARK: - 开机自启权限
    func requestStartAtLogin(completion: @escaping (Bool) -> Void) {
        let status = checkStartAtLogin()
        
        switch status {
        case .granted:
            Logger.shared.debug("开机自启权限已授予")
            completion(true)
        case .denied, .restricted:
            Logger.shared.warning("开机自启权限被拒绝")
            showPermissionAlert(type: .startAtLogin)
            completion(false)
        case .notDetermined:
            Logger.shared.info("尝试注册开机自启")
            enableStartAtLogin()
            completion(true)
        }
    }

    func checkStartAtLogin() -> PermissionStatus {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled ? .granted : .notDetermined
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.suvikedrive.drive"
            let isEnabled = SMLoginItemSetEnabled(bundleID as CFString, false)
            return isEnabled ? .granted : .notDetermined
        }
    }

    func enableStartAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                Logger.shared.info("开机自启已启用 (SMAppService)")
            } catch {
                Logger.shared.error("启用开机自启失败: \(error)")
            }
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.suvikedrive.drive"
            let success = SMLoginItemSetEnabled(bundleID as CFString, true)
            Logger.shared.info(success ? "开机自启已启用" : "启用开机自启失败")
        }
    }
    
    func disableStartAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                Logger.shared.info("开机自启已禁用 (SMAppService)")
            } catch {
                Logger.shared.error("禁用开机自启失败: \(error)")
            }
        } else {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.suvikedrive.drive"
            let success = SMLoginItemSetEnabled(bundleID as CFString, false)
            Logger.shared.info(success ? "开机自启已禁用" : "禁用开机自启失败")
        }
    }
    
    func toggleStartAtLogin(enabled: Bool) {
        if enabled {
            enableStartAtLogin()
        } else {
            disableStartAtLogin()
        }
    }
    
    // MARK: - 权限状态查询
    func getPermissionStatus(type: PermissionType) -> PermissionStatus {
        switch type {
        case .diskAccess:
            return checkDiskAccess()
        case .fullDiskAccess:
            return checkFullDiskAccess()
        case .networkAccess:
            return checkNetworkAccess()
        case .startAtLogin:
            return checkStartAtLogin()
        case .notifications:
            return checkNotifications() ? .granted : .denied
        }
    }
    
    func hasAllPermissions() -> Bool {
        let types: [PermissionType] = [.diskAccess, .networkAccess, .startAtLogin, .fullDiskAccess]
        
        for type in types {
            if getPermissionStatus(type: type) != .granted {
                return false
            }
        }
        return true
    }
    
    func hasFullDiskAccess() -> Bool {
        return checkFullDiskAccess() == .granted
    }
    
    // MARK: - UI引导
    func showSystemSettingsGuide(for type: PermissionType) {
        let alert = NSAlert()
        alert.messageText = "需要系统权限"
        
        let message: String
        let settingsPath: String
        
        switch type {
        case .diskAccess:
            message = "SuvikeDrive需要完全磁盘访问权限才能挂载远程磁盘。\n\n请在系统设置中允许访问。"
            settingsPath = "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess"
        case .fullDiskAccess:
            message = "SuvikeDrive需要完全磁盘访问权限才能挂载和访问远程服务器文件。"
            settingsPath = "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess"
        case .networkAccess:
            message = "SuvikeDrive需要网络访问权限才能连接远程服务器。"
            settingsPath = "x-apple.systempreferences:com.apple.preference.security?Privacy_Network"
        case .startAtLogin:
            message = "SuvikeDrive需要开机自启权限才能在系统启动时自动运行。"
            settingsPath = "x-apple.systempreferences:com.apple.preference.users?LoginItems"
        case .notifications:
            message = "SuvikeDrive需要通知权限才能发送挂载状态更新。"
            settingsPath = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            if let url = URL(string: settingsPath) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showPermissionAlert(type: PermissionType) {
        let alert = NSAlert()
        alert.messageText = "权限被拒绝"
        
        let message: String
        switch type {
        case .diskAccess:
            message = "SuvikeDrive没有足够的磁盘访问权限。请授予权限后重试。"
        case .networkAccess:
            message = "SuvikeDrive没有网络访问权限。请检查防火墙设置。"
        case .startAtLogin:
            message = "SuvikeDrive没有开机自启权限。请授予权限。"
        case .notifications:
            message = "SuvikeDrive没有通知权限。请授予权限。"
        case .fullDiskAccess:
            message = "SuvikeDrive没有完全磁盘访问权限。请授予权限。"
        }
        
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            showSystemSettingsGuide(for: type)
        }
    }
}
