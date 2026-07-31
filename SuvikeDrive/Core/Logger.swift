//
//  Logger.swift
//  SuvikeDrive
//
//  功能: 日志核心管理（纯逻辑，无 UI）
//       分级日志输出、文件管理、敏感信息脱敏
//  通信: 通过 EventBus 接收配置变更通知
//

import AppKit
import Foundation

// MARK: - 启动时间工具 (macOS 兼容版)
extension Logger {
    private static let processStartTime: Date = {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        
        if sysctl(&mib, 4, &proc, &size, nil, 0) == -1 {
            return Date() // 如果获取失败，兜底返回当前时间
        }
        return Date(timeIntervalSince1970: TimeInterval(proc.kp_proc.p_starttime.tv_sec))
    }()
}

class Logger {
    static let shared = Logger()
    
    private let logQueue = DispatchQueue(label: "com.suvikedrive.logger")
    private let logDirectory: URL
    private var currentLogFile: URL?
    private var logLevel: LogLevel = .info
    private var currentFileSize: UInt64 = 0
    private let maxFileSize: UInt64
    private let maxKeepDays: Int
    private let dateFormatter: DateFormatter
    private let fileDateFormatter: DateFormatter
    
    // MARK: - EventBus 订阅 Token
    private var eventToken: SubscriptionToken?
    
    // MARK: - 日志文件更新回调（用于 UI 刷新）
    var onLogFileUpdated: (() -> Void)?
    
    // MARK: - 敏感信息脱敏规则
    private let sensitivePatterns: [(pattern: String, replacement: String)] = [
        (pattern: "(\"password\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "('password'\\s*:\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
        (pattern: "(password\\s*=\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(password\\s*=\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
        (pattern: "(\\bpass\\s*[:=]\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\\bpass\\s*[:=]\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"token\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"api_key\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"apikey\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(Bearer\\s+)([a-zA-Z0-9_\\-\\.]+)", replacement: "$1[REDACTED]"),
        (pattern: "(token\\s*=\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"Authorization\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "('Authorization'\\s*:\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
        (pattern: "(Authorization:\\s*)([a-zA-Z0-9_\\-\\.]+)", replacement: "$1[REDACTED]"),
        (pattern: "(Basic\\s+)([a-zA-Z0-9\\+/=]+)", replacement: "$1[REDACTED]"),
        (pattern: "(https?://)([^:]+):([^@]+)@", replacement: "$1$2:[REDACTED]@"),
        (pattern: "(\"cookie\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"session\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"secret\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(\"private_key\"\\s*:\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(webdav.*password\\s*[:=]\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(webdav.*password\\s*[:=]\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
        (pattern: "(smb.*password\\s*[:=]\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(smb.*password\\s*[:=]\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
        (pattern: "(ftp.*password\\s*[:=]\\s*\")([^\"]*)(\")", replacement: "$1[REDACTED]$3"),
        (pattern: "(ftp.*password\\s*[:=]\\s*')([^']*)(')", replacement: "$1[REDACTED]$3"),
    ]
    
    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let appDir = appSupport.appendingPathComponent("com.suvikedrive.drive")
        let logsDir = appDir.appendingPathComponent("Logs")
        
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(
                at: logsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        logDirectory = logsDir
        maxFileSize = UInt64(ConfigurationManager.shared.get(key: "log.maxFileSize", defaultValue: 10485760))
        maxKeepDays = ConfigurationManager.shared.get(key: "log.keepDays", defaultValue: 30)
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        
        setupLogFile()
        cleanupOldLogs()
        
        // ✅ 通过 EventBus 监听配置变更
        setupEventBusListener()
    }
    
    deinit {
        eventToken?.unsubscribe()
    }
    
    // MARK: - EventBus 事件监听
    private func setupEventBusListener() {
        eventToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .low
        ) { [weak self] event in
            guard let self = self else { return }
            
            // 只处理日志相关配置变更
            if event.key == "log.level" {
                if let newLevel = event.newValue as? String {
                    self.updateLogLevel(from: newLevel)
                }
            }
        }
    }
    
    private func updateLogLevel(from value: String) {
        switch value.lowercased() {
        case "debug": logLevel = .debug
        case "info": logLevel = .info
        case "warning": logLevel = .warning
        case "error": logLevel = .error
        default: logLevel = .info
        }
        info("日志级别已更新为: \(logLevel.rawValue.uppercased())")
    }
    
    func initialize() {
        info("日志系统初始化完成")
        info("日志目录: \(logDirectory.path)")
        info("日志级别: \(logLevel.rawValue.uppercased())")
        info("敏感信息脱敏: 已启用")
    }
    
    // MARK: - 日志记录
    func debug(_ message: String, module: String = "General") {
        log(level: .debug, message: message, module: module)
    }
    
    func info(_ message: String, module: String = "General") {
        log(level: .info, message: message, module: module)
    }
    
    func warning(_ message: String, module: String = "General") {
        log(level: .warning, message: message, module: module)
    }
    
    func error(_ message: String, module: String = "General") {
        log(level: .error, message: message, module: module)
    }
    
    func crash(_ message: String, module: String = "General") {
        log(level: .crash, message: message, module: module)
        _ = saveCrashLog(message)
    }
    
    // MARK: - 敏感信息脱敏
    func redactSensitiveInfo(_ message: String) -> String {
        var redacted = message
        for pattern in sensitivePatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern.pattern, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: (redacted as NSString).length)
                redacted = regex.stringByReplacingMatches(
                    in: redacted,
                    options: [],
                    range: range,
                    withTemplate: pattern.replacement
                )
            } catch {
                continue
            }
        }
        return redacted
    }
    
    func redactPassword(_ password: String) -> String {
        guard !password.isEmpty else { return "" }
        return "********"
    }
    
    func redactToken(_ token: String) -> String {
        guard token.count > 8 else { return "********" }
        let prefix = token.prefix(4)
        let suffix = token.suffix(4)
        return "\(prefix)****\(suffix)"
    }
    
    func redactAuthHeader(_ header: String) -> String {
        if header.hasPrefix("Basic ") {
            return "Basic [REDACTED]"
        } else if header.hasPrefix("Bearer ") {
            let token = header.replacingOccurrences(of: "Bearer ", with: "")
            return "Bearer \(redactToken(token))"
        }
        return header
    }
    
    // MARK: - 核心日志方法
    func log(level: LogLevel, message: String, module: String = "General", file: String = #file, line: Int = #line) {
        guard level.priority >= logLevel.priority else { return }
        
        // ✅ 终极杀手锏：如果是包含“死信”的日志，永远拦截！
        if message.contains("事件移入死信队列") {
            return
        }
        
        // ✅ 启动期静音：如果 App 启动还没过 5 秒，直接拦截，不让它产生日志！
        let startupCutoff = Date().timeIntervalSince(Self.processStartTime)
        if startupCutoff < 5.0 {
            return // 启动 5 秒内，任何日志都不写入、不推送！
        }
        
        let redactedMessage = redactSensitiveInfo(message)
        
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let fileName = (file as NSString).lastPathComponent
            let logMessage = "[\(timestamp)] [\(level.displayName)] [\(module)] [\(fileName):\(line)] \(redactedMessage)\n"
            
            self.writeToFile(logMessage)
            print(logMessage, terminator: "")
        }
    }
    
    func logSensitive(key: String, value: String, module: String = "General") {
        let redactedValue = redactSensitiveInfo(value)
        info("\(key): \(redactedValue)", module: module)
    }
    
    func logSensitiveData(key: String, data: Data, module: String = "General") {
        let redacted = data.map { _ in "*" }.joined()
        info("\(key): \(redacted) (长度: \(data.count) bytes)", module: module)
    }
    
    // MARK: - 文件操作
    private func writeToFile(_ message: String) {
        guard let logFile = currentLogFile else { return }
        
        if currentFileSize >= maxFileSize {
            rotateLogFile()
        }
        
        if let data = message.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
            
            currentFileSize += UInt64(data.count)
        }
        
        // ✅ 核心改动：写入日志后，立刻通过 EventBus 推送到 UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 读取当前日志内容
            let content = self.getLogFileContent() ?? "暂无日志内容"
            // 发送给 LogView 更新
            EventBus.shared.publish(LogContentUpdated(content: content))
            
            // 保留原有的回调通知，兼顾旧代码
            self.onLogFileUpdated?()
        }
    }
    
    private func setupLogFile() {
        let dateString = fileDateFormatter.string(from: Date())
        let logFileName = "\(AppInfo.appName.lowercased())_\(dateString).log"
        currentLogFile = logDirectory.appendingPathComponent(logFileName)
        
        if let file = currentLogFile,
           FileManager.default.fileExists(atPath: file.path) {
            currentFileSize = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
        } else {
            currentFileSize = 0
        }
    }
    
    private func rotateLogFile() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        guard let oldFile = currentLogFile else { return }
        let archiveName = "\(AppInfo.appName.lowercased())_archive_\(timestamp).log"
        let archiveFile = logDirectory.appendingPathComponent(archiveName)
        
        try? FileManager.default.moveItem(at: oldFile, to: archiveFile)
        setupLogFile()
        currentFileSize = 0
        cleanupOldArchives()
    }
    
    private func cleanupOldLogs() {
        let cutoffDate = Date().addingTimeInterval(-Double(maxKeepDays * 24 * 3600))
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        for file in files {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let creationDate = attributes[.creationDate] as? Date,
                  creationDate < cutoffDate else { continue }
            
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    private func cleanupOldArchives() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        let archiveFiles = files.filter { $0.lastPathComponent.hasPrefix("\(AppInfo.appName.lowercased())_archive_") }
        
        if archiveFiles.count > 20 {
            let sortedFiles = archiveFiles.sorted { file1, file2 in
                let attr1 = try? FileManager.default.attributesOfItem(atPath: file1.path)
                let attr2 = try? FileManager.default.attributesOfItem(atPath: file2.path)
                return (attr1?[.creationDate] as? Date ?? Date()) < (attr2?[.creationDate] as? Date ?? Date())
            }
            
            let filesToDelete = sortedFiles.dropFirst(20)
            for file in filesToDelete {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - 崩溃日志
    func saveCrashLog(_ crashInfo: String) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let crashFileName = "crash_\(timestamp).log"
        let crashFile = logDirectory.appendingPathComponent(crashFileName)
        
        let redactedInfo = redactSensitiveInfo(crashInfo)
        
        let fullCrashInfo = """
        ============================================================
        \(AppInfo.appName) Crash Report
        ============================================================
        应用版本: \(AppInfo.appVersion)
        系统版本: \(ProcessInfo.processInfo.operatingSystemVersionString)
        崩溃时间: \(Date())
        ============================================================
        \(redactedInfo)
        ============================================================
        """
        
        do {
            try fullCrashInfo.write(to: crashFile, atomically: true, encoding: .utf8)
            return crashFile.path
        } catch {
            print("保存崩溃日志失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 日志导出
    func exportLogs() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let exportFileName = "\(AppInfo.appName)_Logs_\(timestamp)"
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName)
        let exportZip = FileManager.default.temporaryDirectory.appendingPathComponent("\(exportFileName).zip")
        
        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            
            let files = try FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)
            for file in files {
                let destination = exportDir.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: destination)
            }
            
            let systemInfo = """
            ============================================================
            \(AppInfo.appName) System Information
            ============================================================
            应用版本: \(AppInfo.appVersion)
            构建版本: \(AppInfo.buildNumber)
            系统版本: \(ProcessInfo.processInfo.operatingSystemVersionString)
            主机名: \(ProcessInfo.processInfo.hostName)
            处理器核心: \(ProcessInfo.processInfo.processorCount)
            物理内存: \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB
            导出时间: \(Date())
            ============================================================
            注意: 日志中敏感信息已自动脱敏处理
            ============================================================
            """
            
            let systemInfoFile = exportDir.appendingPathComponent("system_info.txt")
            try systemInfo.write(to: systemInfoFile, atomically: true, encoding: .utf8)
            
            let task = Process()
            task.launchPath = "/usr/bin/zip"
            task.arguments = ["-r", exportZip.path, "."]
            task.currentDirectoryPath = exportDir.path
            task.launch()
            task.waitUntilExit()
            
            try FileManager.default.removeItem(at: exportDir)
            
            Logger.shared.info("日志导出成功: \(exportZip.path)")
            return exportZip
        } catch {
            Logger.shared.error("日志导出失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - 日志级别控制
    func setLogLevel(_ level: LogLevel) {
        logLevel = level
        info("日志级别已设置为: \(level.rawValue.uppercased())")
    }
    
    func getLogLevel() -> LogLevel {
        return logLevel
    }
    
    // MARK: - 获取日志文件
    func getLogFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return files
    }
    
    func getCurrentLogFile() -> URL? {
        return currentLogFile
    }
    
    func getLogDirectory() -> URL {
        return logDirectory
    }
    
    // ✅ 新增：获取当前日志文件的内容（用于推送更新到 UI）
    func getLogFileContent() -> String? {
        guard let logFile = currentLogFile,
              FileManager.default.fileExists(atPath: logFile.path) else {
            return nil
        }
        do {
            return try String(contentsOf: logFile, encoding: .utf8)
        } catch {
            return "读取日志失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 清除所有日志
    func clearAllLogs() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        setupLogFile()
        currentFileSize = 0
        info("所有日志已清除")
        // ✅ 通知 UI 日志已清空
        DispatchQueue.main.async { [weak self] in
            self?.onLogFileUpdated?()
        }
    }
}

// MARK: - 日志级别
enum LogLevel: String {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case crash = "crash"
    case off = "off"
    
    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .crash: return 4
        case .off: return 5
        }
    }
    
    // ✅ 新增：将英文枚举映射为中文显示
    var displayName: String {
        switch self {
        case .debug: return "调试"
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        case .crash: return "崩溃"
        case .off: return "关闭"
        }
    }
}

extension LogLevel: Comparable {
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.priority < rhs.priority
    }
}
