//
//  WatchdogSubprocess.swift
//  SuvikeDrive
//
//  功能: 看门狗子进程（独立运行，监控主应用）
//

import Foundation
import AppKit

class WatchdogSubprocess {
    static let shared = WatchdogSubprocess()
    
    private let heartbeatFilePath = "/tmp/com.suvikedrive.heartbeat"
    private let disableFile = "/tmp/com.suvikedrive.watchdog.disable"
    private let maxMissCount = 3
    private var missCount = 0
    private var mainAppPid: pid_t = 0
    
    private init() {}
    
    // MARK: - 运行子进程监控循环
    func run() {
        // ✅ 设置进程名称
        let processName = "SuvikeDriveDaemon"
        if let cString = (processName as NSString).utf8String {
            let argv = CommandLine.unsafeArgv  // ✅ 改为 let
            if let arg0 = argv[0] {
                let size = min(strlen(arg0), strlen(cString))
                memcpy(arg0, cString, size)
                arg0[size] = 0
            }
        }
        
        print("🔍 看门狗子进程启动 (PID: \(ProcessInfo.processInfo.processIdentifier))")
        
        // ✅ 确保不激活任何窗口
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: false)
        }
        
        // 获取主进程 PID
        mainAppPid = getMainAppPID()
        print("📌 监控主进程 PID: \(mainAppPid)")
        
        // 信号处理：被主进程终止时退出
        signal(SIGTERM) { _ in
            print("📢 看门狗子进程收到终止信号，退出")
            exit(0)
        }
        signal(SIGINT) { _ in
            print("📢 看门狗子进程收到中断信号，退出")
            exit(0)
        }
        
        // 主循环
        while true {
            autoreleasepool {
                // 检查是否被禁用
                if FileManager.default.fileExists(atPath: disableFile) {
                    print("🔒 看门狗已被禁用，退出")
                    exit(0)
                }
                
                // ✅ 使用 kill 检查进程存活（不触发窗口聚焦）
                if !isProcessRunning(pid: mainAppPid) {
                    print("🔄 主进程 (PID: \(mainAppPid)) 已不存在，立即重启")
                    restartMainApp()
                    missCount = 0
                    Thread.sleep(forTimeInterval: 5)
                    return
                }
                
                // 检查心跳
                if let content = try? String(contentsOfFile: heartbeatFilePath, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    if lines.count >= 2, let timestamp = Double(lines[0]) {
                        let elapsed = Date().timeIntervalSince1970 - timestamp
                        if elapsed < 15.0 {
                            missCount = 0
                        } else {
                            missCount += 1
                            print("⚠️ 心跳超时: \(elapsed)秒 (\(missCount)/\(maxMissCount))")
                            if missCount >= maxMissCount {
                                restartMainApp()
                                missCount = 0
                                Thread.sleep(forTimeInterval: 5)
                            }
                        }
                    } else {
                        missCount += 1
                    }
                } else {
                    missCount += 1
                    print("⚠️ 心跳文件不存在 (\(missCount)/\(maxMissCount))")
                    if missCount >= maxMissCount {
                        restartMainApp()
                        missCount = 0
                        Thread.sleep(forTimeInterval: 5)
                    }
                }
            }
            
            // 等待 3 秒
            Thread.sleep(forTimeInterval: 3)
        }
    }
    
    // MARK: - 获取主进程 PID
    private func getMainAppPID() -> pid_t {
        // 方法1：从命令行参数获取（优先）
        let args = ProcessInfo.processInfo.arguments
        if let pidIndex = args.firstIndex(of: "--main-pid"),
           pidIndex + 1 < args.count,
           let pid = pid_t(args[pidIndex + 1]) {
            return pid
        }
        
        // 方法2：从心跳文件获取
        if let content = try? String(contentsOfFile: heartbeatFilePath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if lines.count >= 2, let pid = pid_t(lines[1]) {
                return pid
            }
        }
        
        // ✅ 方法3：通过父进程 PID（最可靠，不触发窗口聚焦）
        let parentPid = getppid()
        if parentPid > 1 {
            return parentPid
        }
        
        return 0
    }
    
    // ✅ 使用 kill 检查进程是否存活（不会触发窗口聚焦）
    private func isProcessRunning(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
    
    // MARK: - 重启主应用（不激活窗口）
    private func restartMainApp() {
        let appPath = Bundle.main.bundlePath
        
        print("🔄 正在重启主应用...")
        
        // ✅ 使用 Process 启动，-g 参数表示不激活前台
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", appPath]
        
        do {
            try task.run()
            print("✅ 主应用重启命令已发送（后台模式）")
        } catch {
            print("❌ 重启主应用失败: \(error)")
            
            // ✅ 备用方法：使用 NSWorkspace 但不激活
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
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
    }
}
