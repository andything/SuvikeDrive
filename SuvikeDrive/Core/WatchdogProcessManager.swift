//
//  WatchdogProcessManager.swift
//  SuvikeDrive
//
//  功能: 独立进程看门狗（不依赖 launchctl）
//        启动一个独立子进程监控主应用
//

import Foundation
import AppKit

class WatchdogProcessManager {
    static let shared = WatchdogProcessManager()
    
    // 子进程标识
    private let heartbeatFilePath = "/tmp/com.suvikedrive.heartbeat"
    private let watchdogPidFile = "/tmp/com.suvikedrive.watchdog.pid"
    private let disableFile = "/tmp/com.suvikedrive.watchdog.disable"
    
    // 子进程监控状态
    private var isWatchdogRunning = false
    private var watchdogTask: Process?
    private var monitorTimer: Timer?
    private var isStopping = false
    
    private init() {
        // 清理旧心跳文件
        try? FileManager.default.removeItem(atPath: heartbeatFilePath)
    }
    
    // MARK: - 启动看门狗子进程
    func startWatchdog() {
        guard !isWatchdogRunning else { return }
        guard !isStopping else { return }
        
        // 检查是否已有看门狗子进程在运行
        if let existingPid = getWatchdogPid(), isProcessRunning(pid: existingPid) {
            print("⚠️ 看门狗子进程已在运行 (PID: \(existingPid))")
            isWatchdogRunning = true
            return
        }
        
        // 清除禁用标志
        try? FileManager.default.removeItem(atPath: disableFile)
        
        let task = Process()
        task.executableURL = Bundle.main.executableURL
        
        // ✅ 传入主进程 PID
        let mainPid = ProcessInfo.processInfo.processIdentifier
        task.arguments = ["--watchdog-mode", "--main-pid", "\(mainPid)"]
        task.qualityOfService = .utility
        
        // ✅ 重定向输出，防止控制台干扰
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        // ✅ 子进程退出时自动重启（但要检查是否正在停止）
        task.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            if self.isStopping {
                print("📢 看门狗正在停止，不重启")
                return
            }
            if FileManager.default.fileExists(atPath: self.disableFile) {
                print("🔒 看门狗已被禁用，不重启")
                return
            }
            print("⚠️ 看门狗子进程异常退出，正在重启...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.startWatchdog()
            }
        }
        
        do {
            try task.run()
            watchdogTask = task
            isWatchdogRunning = true
            isStopping = false
            
            // 保存子进程 PID
            saveWatchdogPid(pid: task.processIdentifier)
            
            // 启动心跳监控
            startHeartbeatMonitor()
            
            print("✅ 看门狗子进程已启动 (PID: \(task.processIdentifier))")
        } catch {
            print("❌ 启动看门狗子进程失败: \(error)")
        }
    }
    
    // MARK: - 停止看门狗子进程
    func stopWatchdog() {
        guard isWatchdogRunning else { return }
        guard !isStopping else { return }
        
        isStopping = true
        
        // ✅ 先创建禁用标志，防止子进程重启
        try? "disabled".write(toFile: disableFile, atomically: true, encoding: .utf8)
        
        // ✅ 停止心跳监控
        monitorTimer?.invalidate()
        monitorTimer = nil
        
        // ✅ 终止子进程
        if let task = watchdogTask {
            task.terminationHandler = nil
            task.terminate()
            watchdogTask = nil
        }
        
        // 清理 PID 文件
        try? FileManager.default.removeItem(atPath: watchdogPidFile)
        try? FileManager.default.removeItem(atPath: heartbeatFilePath)
        
        isWatchdogRunning = false
        
        // ✅ 延迟重置停止标志
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isStopping = false
        }
        
        print("✅ 看门狗子进程已停止")
    }
    
    // MARK: - 心跳监控
    private func startHeartbeatMonitor() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.updateHeartbeat()
        }
        RunLoop.current.add(monitorTimer!, forMode: .common)
    }
    
    private func updateHeartbeat() {
        let timestamp = Date().timeIntervalSince1970
        let pid = ProcessInfo.processInfo.processIdentifier
        let heartbeatData = "\(timestamp)\n\(pid)\n".data(using: .utf8)
        try? heartbeatData?.write(to: URL(fileURLWithPath: heartbeatFilePath))
    }
    
    // MARK: - 状态查询
    func isWatchdogActive() -> Bool {
        return isWatchdogRunning || isSubprocessRunning()
    }
    
    private func isSubprocessRunning() -> Bool {
        guard let pid = getWatchdogPid() else { return false }
        return isProcessRunning(pid: pid)
    }
    
    private func getWatchdogPid() -> pid_t? {
        guard let content = try? String(contentsOfFile: watchdogPidFile, encoding: .utf8) else {
            return nil
        }
        return pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func saveWatchdogPid(pid: pid_t) {
        try? "\(pid)".write(toFile: watchdogPidFile, atomically: true, encoding: .utf8)
    }
    
    private func isProcessRunning(pid: pid_t) -> Bool {
        return kill(pid, 0) == 0
    }
    
    // MARK: - 清理
    func cleanup() {
        stopWatchdog()
    }
}
