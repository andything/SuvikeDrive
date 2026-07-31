//
//  WatchdogProcessManager.swift
//  SuvikeDrive
//
//  功能: 独立进程看门狗（不依赖 launchctl）
//        启动一个独立子进程监控主应用
//  优化: 增加重启限流、线程安全、超时检测
//

import Foundation
import AppKit

// ✅ WatchdogConfig 和 Notification.Name 扩展已移到 Utils.swift

class WatchdogProcessManager {
    static let shared = WatchdogProcessManager()
    
    // MARK: - 属性
    private let queue = DispatchQueue(label: "com.suvikedrive.watchdog.manager", qos: .utility)
    private var watchdogTask: Process?
    private var heartbeatTimer: Timer?
    private var timeoutTimer: Timer?
    
    // 状态（仅在 queue 内访问）
    private var _isWatchdogRunning = false
    private var _isStopping = false
    private var _restartCount = 0
    private var _lastRestartTime: Date = .distantPast
    private var _lastHeartbeatTime: Date = .distantPast
    
    // MARK: - 公开属性
    var isWatchdogRunning: Bool {
        return queue.sync { _isWatchdogRunning }
    }
    
    private init() {
        try? FileManager.default.removeItem(atPath: WatchdogConfig.heartbeatFile)
    }
    
    // MARK: - 启动看门狗子进程
    func startWatchdog() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self._startWatchdog()
        }
    }
    
    private func _startWatchdog() {
        guard !_isWatchdogRunning else { return }
        guard !_isStopping else { return }
        
        // 检查是否已有看门狗子进程在运行
        if let existingPid = self.getWatchdogPid(), self.isProcessRunning(pid: existingPid) {
            print("⚠️ 看门狗子进程已在运行 (PID: \(existingPid))")
            _isWatchdogRunning = true
            return
        }
        
        // ✅ 检查重启限流
        if self.isRestartThrottled() {
            print("🚫 看门狗重启过于频繁 (\(_restartCount)次/60秒)，暂停启动")
            return
        }
        
        // 清除禁用标志
        try? FileManager.default.removeItem(atPath: WatchdogConfig.disableFile)
        
        let task = Process()
        task.executableURL = Bundle.main.executableURL
        let mainPid = ProcessInfo.processInfo.processIdentifier
        task.arguments = ["--watchdog-mode", "--main-pid", "\(mainPid)"]
        task.qualityOfService = .utility
        
        // 重定向输出，防止控制台干扰
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        // ✅ 子进程退出时自动重启（改进：不直接递归调用）
        task.terminationHandler = { [weak self] process in
            self?.handleSubprocessTermination(process)
        }
        
        do {
            try task.run()
            watchdogTask = task
            _isWatchdogRunning = true
            _isStopping = false
            _restartCount += 1
            _lastRestartTime = Date()
            
            // 保存子进程 PID
            self.saveWatchdogPid(pid: task.processIdentifier)
            
            // 启动心跳监控
            self.startHeartbeatMonitoring()
            
            print("✅ 看门狗子进程已启动 (PID: \(task.processIdentifier)) [重启次数: \(_restartCount)]")
        } catch {
            print("❌ 启动看门狗子进程失败: \(error)")
            _isWatchdogRunning = false
            // ✅ 调度延迟重试（非递归）
            self.scheduleRestart()
        }
    }
    
    // MARK: - 子进程终止处理（避免递归）
    private func handleSubprocessTermination(_ process: Process) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if self._isStopping {
                print("📢 看门狗正在停止，不重启")
                return
            }
            
            if FileManager.default.fileExists(atPath: WatchdogConfig.disableFile) {
                print("🔒 看门狗已被禁用，不重启")
                return
            }
            
            // ✅ 正常退出不重启
            if process.terminationReason == .exit && process.terminationStatus == 0 {
                print("ℹ️ 看门狗子进程正常退出，不重启")
                self._isWatchdogRunning = false
                return
            }
            
            // ✅ 检查重启限流
            if self.isRestartThrottled() {
                print("🚫 重启限流触发 (\(self._restartCount)次/60秒)，停止自动重启")
                self._isWatchdogRunning = false
                return
            }
            
            print("⚠️ 看门狗子进程异常退出 (reason: \(process.terminationReason), status: \(process.terminationStatus))")
            self._isWatchdogRunning = false
            self.watchdogTask = nil
            
            // ✅ 调度延迟重启（非递归）
            self.scheduleRestart()
        }
    }
    
    // MARK: - 调度重启（非递归）
    private func scheduleRestart() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + WatchdogConfig.restartDelay) { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                // 再次检查状态
                if self._isStopping {
                    return
                }
                if FileManager.default.fileExists(atPath: WatchdogConfig.disableFile) {
                    return
                }
                if self.isRestartThrottled() {
                    print("🚫 重启限流触发，放弃重启")
                    return
                }
                if !self._isWatchdogRunning {
                    self._startWatchdog()
                }
            }
        }
    }
    
    // MARK: - 重启限流检查
    private func isRestartThrottled() -> Bool {
        let now = Date()
        if now.timeIntervalSince(_lastRestartTime) < WatchdogConfig.restartWindow {
            return _restartCount >= WatchdogConfig.maxRestartCount
        } else {
            // 窗口过期，重置计数
            _restartCount = 0
            return false
        }
    }
    
    // MARK: - 停止看门狗子进程
    func stopWatchdog() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self._isWatchdogRunning else { return }
            guard !self._isStopping else { return }
            
            self._isStopping = true
            
            // 创建禁用标志，防止子进程重启
            try? "disabled".write(toFile: WatchdogConfig.disableFile, atomically: true, encoding: .utf8)
            
            // 停止心跳监控
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = nil
            
            // 终止子进程
            if let task = self.watchdogTask {
                task.terminationHandler = nil  // ✅ 防止触发重启
                task.terminate()
                // ✅ 等待进程退出（最多 3 秒）
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline && self.isProcessRunning(pid: task.processIdentifier) {
                    usleep(100_000)
                }
                if self.isProcessRunning(pid: task.processIdentifier) {
                    kill(task.processIdentifier, SIGKILL)
                }
                self.watchdogTask = nil
            }
            
            // 清理文件
            try? FileManager.default.removeItem(atPath: WatchdogConfig.pidFile)
            try? FileManager.default.removeItem(atPath: WatchdogConfig.heartbeatFile)
            
            self._isWatchdogRunning = false
            
            // 延迟重置停止标志
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.queue.async {
                    self?._isStopping = false
                }
            }
            
            print("✅ 看门狗子进程已停止")
        }
    }
    
    // MARK: - 心跳监控（改进版）
    private func startHeartbeatMonitoring() {
        // 取消旧定时器
        heartbeatTimer?.invalidate()
        timeoutTimer?.invalidate()
        
        // ✅ 心跳定时器
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: WatchdogConfig.heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateHeartbeat()
        }
        RunLoop.current.add(heartbeatTimer!, forMode: .common)
        
        // ✅ 超时检测定时器
        timeoutTimer = Timer.scheduledTimer(
            withTimeInterval: WatchdogConfig.heartbeatTimeout,
            repeats: true
        ) { [weak self] _ in
            self?.checkHeartbeatTimeout()
        }
        RunLoop.current.add(timeoutTimer!, forMode: .common)
        
        _lastHeartbeatTime = Date()
    }
    
    private func updateHeartbeat() {
        let timestamp = Date().timeIntervalSince1970
        let pid = ProcessInfo.processInfo.processIdentifier
        let heartbeatData = "\(timestamp)\n\(pid)\n".data(using: .utf8)
        
        // ✅ 原子写入（先写临时文件再移动）
        let tempPath = WatchdogConfig.heartbeatFile + ".tmp"
        let tempURL = URL(fileURLWithPath: tempPath)
        let targetURL = URL(fileURLWithPath: WatchdogConfig.heartbeatFile)
        
        do {
            try heartbeatData?.write(to: tempURL, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(targetURL, withItemAt: tempURL)
            _lastHeartbeatTime = Date()
        } catch {
            // 静默失败，避免日志风暴
        }
    }
    
    // ✅ 新增：超时检测
    private func checkHeartbeatTimeout() {
        queue.async { [weak self] in
            guard let self = self, self._isWatchdogRunning else { return }
            
            let elapsed = Date().timeIntervalSince(self._lastHeartbeatTime)
            if elapsed > WatchdogConfig.heartbeatTimeout + 5.0 {
                print("🚨 心跳超时！主进程可能挂起 (\(Int(elapsed))秒无响应)")
                
                // 发送通知，让 UI 层处理
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .watchdogDidDetectHang,
                        object: nil,
                        userInfo: ["elapsed": elapsed]
                    )
                }
                
                // 重置检测时间，避免重复告警
                self._lastHeartbeatTime = Date()
            }
        }
    }
    
    // MARK: - PID 文件管理
    private func getWatchdogPid() -> pid_t? {
        guard let content = try? String(contentsOfFile: WatchdogConfig.pidFile, encoding: .utf8) else {
            return nil
        }
        return pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func saveWatchdogPid(pid: pid_t) {
        try? "\(pid)".write(toFile: WatchdogConfig.pidFile, atomically: true, encoding: .utf8)
    }
    
    // MARK: - 进程状态检查
    private func isProcessRunning(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
    
    // MARK: - 状态查询
    func isWatchdogActive() -> Bool {
        return queue.sync { _isWatchdogRunning || isSubprocessRunning() }
    }
    
    private func isSubprocessRunning() -> Bool {
        guard let pid = getWatchdogPid() else { return false }
        return isProcessRunning(pid: pid)
    }
    
    // MARK: - 清理
    func cleanup() {
        stopWatchdog()
        try? FileManager.default.removeItem(atPath: WatchdogConfig.heartbeatFile + ".tmp")
    }
}
