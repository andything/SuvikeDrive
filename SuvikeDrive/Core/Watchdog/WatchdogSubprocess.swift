//
//  WatchdogSubprocess.swift
//  SuvikeDrive
//
//  功能: 看门狗子进程（独立运行，监控主应用）
//  优化: 使用 DispatchSourceTimer 替代 sleep，增加重启限流
//

import Foundation
import AppKit

// MARK: - 配置常量
private struct SubprocessConfig {
    static let checkInterval: TimeInterval = 3.0
    static let heartbeatTimeout: TimeInterval = 15.0
    static let maxMissCount = 3
    static let restartCooldown: TimeInterval = 10.0
    static let maxRestartAttempts = 5
    static let restartWindow: TimeInterval = 120.0
    static let heartbeatFile = "/tmp/com.suvikedrive.heartbeat"
    static let disableFile = "/tmp/com.suvikedrive.watchdog.disable"
}

class WatchdogSubprocess {
    static let shared = WatchdogSubprocess()
    
    // MARK: - 属性
    private var mainAppPid: pid_t = 0
    private var isRunning = true
    private var isRestarting = false
    
    private var missCount = 0
    private var restartCount = 0
    private var lastRestartTime: Date = .distantPast
    
    private var checkTimer: DispatchSourceTimer?
    private var signalSource: DispatchSourceSignal?
    private let signalQueue = DispatchQueue(label: "com.suvikedrive.watchdog.signal")
    
    private init() {}
    
    // MARK: - 运行子进程监控循环
    func run() {
        setupProcessName()
        
        print("🔍 看门狗子进程启动 (PID: \(ProcessInfo.processInfo.processIdentifier))")
        
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: false)
        }
        
        mainAppPid = getMainAppPID()
        guard mainAppPid > 0 else {
            print("❌ 无法获取主进程 PID，退出")
            exit(1)
        }
        print("📌 监控主进程 PID: \(mainAppPid)")
        
        setupSignalHandlers()
        startMonitoring()
        
        RunLoop.current.run()
    }
    
    // MARK: - 安全设置进程名
    private func setupProcessName() {
        // 使用 Foundation API（最安全）
        ProcessInfo.processInfo.processName = "SuvikeDriveDaemon"
        
        #if DEBUG
        // ✅ 修复：正确处理可选类型
        let argv = CommandLine.unsafeArgv
        // argv 是非可选类型 UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>
        // 所以直接使用 argv[0] 获取第一个参数
        let arg0 = argv[0]  // 类型为 UnsafeMutablePointer<Int8>?
        if let arg0 = arg0 {  // ✅ 解包可选值
            let name = "SuvikeDriveDaemon"
            if let cString = (name as NSString).utf8String {
                let size = min(strlen(arg0), strlen(cString))
                memcpy(arg0, cString, size)
                arg0[size] = 0
            }
        }
        #endif
    }
    
    // MARK: - 信号处理
    private func setupSignalHandlers() {
        let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP]
        
        for sig in signals {
            signal(sig, SIG_IGN)
            
            let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
            source.setEventHandler { [weak self] in
                print("📢 看门狗子进程收到信号 \(sig)，正在退出...")
                self?.shutdown()
            }
            source.resume()
            self.signalSource = source
        }
    }
    
    // MARK: - 启动监控
    private func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + SubprocessConfig.checkInterval,
                      repeating: SubprocessConfig.checkInterval)
        timer.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }
        timer.resume()
        self.checkTimer = timer
    }
    
    // MARK: - 健康检查
    private func performHealthCheck() {
        autoreleasepool {
            guard isRunning else { return }
            
            if FileManager.default.fileExists(atPath: SubprocessConfig.disableFile) {
                print("🔒 看门狗已被禁用，退出")
                shutdown()
                return
            }
            
            if !isProcessRunning(pid: mainAppPid) {
                print("🔄 主进程 (PID: \(mainAppPid)) 已不存在")
                handleProcessFailure()
                return
            }
            
            checkHeartbeat()
        }
    }
    
    // MARK: - 心跳检查
    private func checkHeartbeat() {
        guard let content = try? String(contentsOfFile: SubprocessConfig.heartbeatFile, encoding: .utf8) else {
            missCount += 1
            print("⚠️ 心跳文件不存在 (\(missCount)/\(SubprocessConfig.maxMissCount))")
            if missCount >= SubprocessConfig.maxMissCount {
                handleProcessFailure()
            }
            return
        }
        
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        if lines.count >= 2 {
            guard let timestamp = Double(lines[0]),
                  let pid = pid_t(lines[1]),
                  pid == mainAppPid else {
                missCount += 1
                print("⚠️ 心跳无效 (\(missCount)/\(SubprocessConfig.maxMissCount))")
                if missCount >= SubprocessConfig.maxMissCount {
                    handleProcessFailure()
                }
                return
            }
            
            let elapsed = Date().timeIntervalSince1970 - timestamp
            if elapsed < SubprocessConfig.heartbeatTimeout {
                if missCount > 0 {
                    print("✅ 心跳恢复")
                }
                missCount = 0
            } else {
                missCount += 1
                print("⚠️ 心跳超时: \(Int(elapsed))秒 (\(missCount)/\(SubprocessConfig.maxMissCount))")
                if missCount >= SubprocessConfig.maxMissCount {
                    handleProcessFailure()
                }
            }
        } else {
            missCount += 1
            print("⚠️ 心跳格式无效 (\(missCount)/\(SubprocessConfig.maxMissCount))")
            if missCount >= SubprocessConfig.maxMissCount {
                handleProcessFailure()
            }
        }
    }
    
    // MARK: - 处理进程故障
    private func handleProcessFailure() {
        guard !isRestarting else { return }
        guard isRunning else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastRestartTime) < SubprocessConfig.restartWindow {
            if restartCount >= SubprocessConfig.maxRestartAttempts {
                print("🚫 重启次数过多 (\(restartCount)次/\(Int(SubprocessConfig.restartWindow))秒)，停止监控")
                shutdown()
                return
            }
        } else {
            restartCount = 0
        }
        
        isRestarting = true
        restartCount += 1
        lastRestartTime = now
        
        print("🔄 触发重启 (第 \(restartCount) 次)")
        
        restartMainApp()
        waitForMainProcess()
        
        missCount = 0
        isRestarting = false
        
        print("✅ 重启完成")
    }
    
    // MARK: - 等待主进程启动
    private func waitForMainProcess() {
        let maxWaitTime: TimeInterval = 30.0
        let checkInterval: TimeInterval = 1.0
        var waited: TimeInterval = 0
        
        while waited < maxWaitTime && isRunning {
            if FileManager.default.fileExists(atPath: SubprocessConfig.disableFile) {
                print("🔒 看门狗已被禁用，退出")
                shutdown()
                return
            }
            
            if isProcessRunning(pid: mainAppPid) {
                if let content = try? String(contentsOfFile: SubprocessConfig.heartbeatFile, encoding: .utf8),
                   let timestamp = Double(content.components(separatedBy: .newlines).first ?? "") {
                    let elapsed = Date().timeIntervalSince1970 - timestamp
                    if elapsed < SubprocessConfig.heartbeatTimeout {
                        print("✅ 主进程已恢复 (PID: \(mainAppPid))")
                        return
                    }
                }
            }
            
            let newPid = getMainAppPID()
            if newPid > 0 && newPid != mainAppPid && isProcessRunning(pid: newPid) {
                mainAppPid = newPid
                print("📌 主进程 PID 更新为: \(mainAppPid)")
                Thread.sleep(forTimeInterval: 1.0)
                if let content = try? String(contentsOfFile: SubprocessConfig.heartbeatFile, encoding: .utf8),
                   let timestamp = Double(content.components(separatedBy: .newlines).first ?? "") {
                    let elapsed = Date().timeIntervalSince1970 - timestamp
                    if elapsed < SubprocessConfig.heartbeatTimeout {
                        print("✅ 新主进程已就绪 (PID: \(mainAppPid))")
                        return
                    }
                }
            }
            
            Thread.sleep(forTimeInterval: checkInterval)
            waited += checkInterval
        }
        
        print("⚠️ 等待主进程启动超时 (\(Int(maxWaitTime))秒)")
        
        if isRunning && !FileManager.default.fileExists(atPath: SubprocessConfig.disableFile) {
            print("🔄 尝试再次重启主进程...")
            restartMainApp()
            Thread.sleep(forTimeInterval: 5.0)
        }
    }
    
    // MARK: - 获取主进程 PID
    private func getMainAppPID() -> pid_t {
        let args = ProcessInfo.processInfo.arguments
        if let pidIndex = args.firstIndex(of: "--main-pid"),
           pidIndex + 1 < args.count,
           let pid = pid_t(args[pidIndex + 1]) {
            return pid
        }
        
        let parentPid = getppid()
        if parentPid > 1 && isProcessRunning(pid: parentPid) {
            return parentPid
        }
        
        if let content = try? String(contentsOfFile: SubprocessConfig.heartbeatFile, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if lines.count >= 2, let pid = pid_t(lines[1]) {
                return pid
            }
        }
        
        return 0
    }
    
    // MARK: - 进程状态检查
    private func isProcessRunning(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
    
    // MARK: - 重启主应用
    private func restartMainApp() {
        let appPath = Bundle.main.bundlePath
        
        print("🔄 正在重启主应用...")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", appPath]
        task.qualityOfService = .userInitiated
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                print("✅ 主应用重启命令已发送（后台模式）")
                return
            }
        } catch {
            print("⚠️ open 命令失败: \(error)")
        }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: appPath),
            configuration: config
        ) { _, error in
            if let error = error {
                print("❌ 重启主应用失败: \(error)")
            } else {
                print("✅ 主应用已重启（后台模式）")
            }
        }
    }
    
    // MARK: - 关闭清理
    private func shutdown() {
        guard isRunning else { return }
        isRunning = false
        
        checkTimer?.cancel()
        checkTimer = nil
        
        print("📢 看门狗子进程退出")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
}
