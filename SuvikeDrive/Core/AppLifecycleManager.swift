//
//  AppLifecycleManager.swift
//  SuvikeDrive
//
//  功能: 应用生命周期管理
//

import Foundation
import Cocoa
import AppKit

class AppLifecycleManager {
    static let shared = AppLifecycleManager()
    
    private var isRunning = false
    private var heartbeatTimer: Timer?
    private var lastHeartbeat: Date = Date()
    private let heartbeatInterval: TimeInterval = 5.0  // ✅ 每5秒更新心跳
    
    private let heartbeatFilePath: String
    private let lockFilePath: String
    private var lockFileHandle: FileHandle?
    
    // MARK: - 静态信号处理
    private static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        let crashFile = "/tmp/\(AppInfo.bundleID)_crash.log"
        let message = """
        ============================================================
        \(AppInfo.appName) 信号崩溃报告
        ============================================================
        信号: \(signal)
        时间: \(Date())
        进程ID: \(ProcessInfo.processInfo.processIdentifier)
        ============================================================
        """
        try? message.write(toFile: crashFile, atomically: true, encoding: .utf8)
    }
    
    private init() {
        let tempDir = NSTemporaryDirectory()
        heartbeatFilePath = tempDir + "com.suvikedrive.heartbeat"
        lockFilePath = tempDir + "com.suvikedrive.lock"
    }
    
    // MARK: - 生命周期
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // 单例检测
        guard ensureSingleInstance() else {
            Logger.shared.warning("检测到已有实例运行，当前实例退出")
            NSApplication.shared.terminate(nil)
            return
        }
        
        setupCrashHandler()
        startHeartbeat()
        registerLifecycleNotifications()
        
        Logger.shared.info("应用生命周期管理器启动成功")
        Logger.shared.info("进程ID: \(ProcessInfo.processInfo.processIdentifier)")
        Logger.shared.info("版本: \(AppInfo.appVersion)")
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        // 删除心跳文件
        try? FileManager.default.removeItem(atPath: heartbeatFilePath)
        releaseFileLock()
        
        Logger.shared.info("应用生命周期管理器已停止")
    }
    
    // MARK: - 单例检测
    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? AppInfo.bundleID
        let runningInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        )
        
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = runningInstances.filter {
            $0.processIdentifier != currentPID
        }
        
        if !otherInstances.isEmpty {
            if let existingApp = otherInstances.first {
                existingApp.activate()
            }
            return false
        }
        
        return acquireFileLock()
    }
    
    private func acquireFileLock() -> Bool {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: lockFilePath) {
            fileManager.createFile(atPath: lockFilePath, contents: nil, attributes: nil)
        }
        
        guard let fileHandle = try? FileHandle(forUpdating: URL(fileURLWithPath: lockFilePath)) else {
            return false
        }
        
        let result = flock(fileHandle.fileDescriptor, Int32(LOCK_EX | LOCK_NB))
        if result == 0 {
            lockFileHandle = fileHandle
            return true
        } else {
            try? fileHandle.close()
            return false
        }
    }
    
    private func releaseFileLock() {
        lockFileHandle?.closeFile()
        lockFileHandle = nil
    }
    
    // MARK: - 崩溃处理
    private func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let crashInfo = AppLifecycleManager.shared.buildCrashReport(exception: exception)
            Logger.shared.crash(crashInfo)
            if let path = Logger.shared.saveCrashLog(crashInfo) {
                print("崩溃日志已保存: \(path)")
            }
        }
        
        signal(SIGABRT, AppLifecycleManager.signalHandler)
        signal(SIGILL, AppLifecycleManager.signalHandler)
        signal(SIGSEGV, AppLifecycleManager.signalHandler)
        signal(SIGFPE, AppLifecycleManager.signalHandler)
        signal(SIGBUS, AppLifecycleManager.signalHandler)
        signal(SIGPIPE, AppLifecycleManager.signalHandler)
    }
    
    private func buildCrashReport(exception: NSException) -> String {
        return """
        ============================================================
                        \(AppInfo.appName) 崩溃报告
        ============================================================
        
        崩溃时间: \(Date())
        应用版本: \(AppInfo.appVersion)
        系统版本: \(ProcessInfo.processInfo.operatingSystemVersionString)
        
        ------------------------------------------------------------
        异常名称: \(exception.name.rawValue)
        异常原因: \(exception.reason ?? "未知原因")
        
        堆栈信息:
        \(exception.callStackSymbols.joined(separator: "\n"))
        
        ============================================================
        """
    }
    
    // MARK: - ✅ 心跳（只写心跳文件，不负责重启）
    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateHeartbeat()
        }
        RunLoop.current.add(heartbeatTimer!, forMode: .common)
        Logger.shared.debug("心跳已启动，间隔: \(heartbeatInterval)秒")
    }
    
    private func updateHeartbeat() {
        let timestamp = Date().timeIntervalSince1970
        let pid = ProcessInfo.processInfo.processIdentifier
        let heartbeatData = "\(timestamp)\n\(pid)\n".data(using: .utf8)
        try? heartbeatData?.write(to: URL(fileURLWithPath: heartbeatFilePath))
        lastHeartbeat = Date()
        // ✅ 只输出一次，减少日志
        // print("💓 心跳: \(Date())")
    }
    
    // MARK: - 生命周期通知
    private func registerLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func applicationWillTerminate() {
        Logger.shared.info("应用即将退出")
        stop()
    }
}
