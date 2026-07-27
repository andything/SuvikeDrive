//
//  AdvancedTab.swift
//  SuvikeDrive
//
//  功能: 高级标签页
//

import SwiftUI

struct AdvancedTab: View {
    @Binding var daemonEnabled: Bool
    @Binding var hasFullDiskAccess: Bool
    @Binding var isCheckingPermission: Bool
    @Binding var statusBarTrafficMonitor: Bool
    @Binding var timeout: Int
    @Binding var maxRetries: Int
    @Binding var enableLogging: Bool
    @Binding var logLevel: String
    @Binding var analytics: Bool
    
    let logLevels = ["调试", "信息", "警告", "错误", "崩溃"]
    
    var body: some View {
        Group {
            Section {
                // ✅ 守护进程
                HStack {
                    Text("守护进程")
                        .font(.body)
                    Spacer()
                    Text(daemonEnabled ? "已开启" : "已关闭")
                        .font(.caption)
                        .foregroundColor(daemonEnabled ? .green : .gray)
                    Toggle("", isOn: Binding(
                        get: { daemonEnabled },
                        set: { newValue in
                            daemonEnabled = newValue
                            ConfigurationManager.shared.set(key: "app.daemon.enabled", value: newValue)
                            if newValue {
                                WatchdogProcessManager.shared.startWatchdog()
                            } else {
                                WatchdogProcessManager.shared.stopWatchdog()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .frame(height: 32)
                
                // ✅ 全盘访问权限
                HStack {
                    Text("全盘访问权限")
                        .font(.body)
                    Spacer()
                    Text(hasFullDiskAccess ? "已授权" : "未授权")
                        .font(.caption)
                        .foregroundColor(hasFullDiskAccess ? .green : .orange)
                    Toggle("", isOn: Binding(
                        get: { hasFullDiskAccess },
                        set: { newValue in
                            if newValue {
                                if !hasFullDiskAccess {
                                    requestFullDiskAccess()
                                }
                            } else {
                                if hasFullDiskAccess {
                                    showFullDiskAccessGuide()
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .frame(height: 32)
                .onAppear {
                    checkFullDiskAccessStatus()
                }
            }
            
            // 状态栏流量监控
            Section {
                HStack {
                    Text("状态栏流量监控")
                        .font(.body)
                    Spacer()
                    Text(statusBarTrafficMonitor ? "已开启" : "已关闭")
                        .font(.caption)
                        .foregroundColor(statusBarTrafficMonitor ? .green : .gray)
                    Toggle("", isOn: $statusBarTrafficMonitor)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: statusBarTrafficMonitor) { _, newValue in
                            if newValue {
                                NetworkManager.shared.startInterfaceMonitoring()
                                Logger.shared.info("状态栏流量监控已开启")
                            } else {
                                NetworkManager.shared.stopInterfaceMonitoring()
                                Logger.shared.info("状态栏流量监控已关闭")
                            }
                        }
                }
                .frame(height: 32)
            }
            
            Section {
                HStack {
                    Text("请求超时 (秒)")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $timeout) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("15").tag(15)
                        Text("30").tag(30)
                        Text("60").tag(60)
                        Text("120").tag(120)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .frame(height: 32)
                
                HStack {
                    Text("最大重试次数")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $maxRetries) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("5").tag(5)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .frame(height: 32)
            }
            
            Section {
                Toggle("启用日志记录", isOn: $enableLogging)
                    .onChange(of: enableLogging) { _, newValue in
                        if !newValue {
                            Logger.shared.setLogLevel(.off)
                        } else {
                            applyLogLevel()
                        }
                    }
                
                HStack {
                    Text("日志级别")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $logLevel) {
                        ForEach(logLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .disabled(!enableLogging)
                    .opacity(enableLogging ? 1 : 0.5)
                    .onChange(of: logLevel) { _, _ in
                        if enableLogging {
                            applyLogLevel()
                        }
                    }
                }
                .frame(height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("调试 → 最详细  |  信息 → 常规  |  警告 → 潜在问题  |  错误 → 功能异常  |  崩溃 → 严重崩溃")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.top, 2)
                
                Toggle("发送匿名统计信息", isOn: $analytics)
            }
        }
    }
    
    private func checkFullDiskAccessStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = PermissionManager.shared.checkFullDiskAccess()
            let isGranted: Bool
            switch status {
            case .granted:
                isGranted = true
            case .denied, .notDetermined, .restricted:
                isGranted = false
            }
            DispatchQueue.main.async {
                self.hasFullDiskAccess = isGranted
                self.isCheckingPermission = false
                EventBus.shared.publish(PermissionStatusUpdated(
                    permissionType: "full_disk_access",
                    isGranted: isGranted
                ))
            }
        }
    }
    
    private func requestFullDiskAccess() {
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        
        let status = PermissionManager.shared.checkFullDiskAccess()
        let isGranted: Bool
        switch status {
        case .granted:
            isGranted = true
        case .denied, .notDetermined, .restricted:
            isGranted = false
        }
        
        if isGranted {
            DispatchQueue.main.async {
                self.hasFullDiskAccess = true
                self.isCheckingPermission = false
                EventBus.shared.publish(PermissionStatusUpdated(
                    permissionType: "full_disk_access",
                    isGranted: true
                ))
            }
            return
        }
        
        DispatchQueue.main.async {
            PermissionManager.shared.showFullDiskAccessGuide { granted in
                DispatchQueue.main.async {
                    self.checkFullDiskAccessStatus()
                }
            }
        }
    }
    
    private func showFullDiskAccessGuide() {
        let alert = NSAlert()
        alert.messageText = "全盘访问权限"
        alert.informativeText = """
        如需关闭全盘访问权限，请按以下步骤操作：
        
        1. 点击「打开设置」按钮
        2. 在「隐私与安全性」→「全盘访问」中
        3. 找到 \(AppInfo.appName)
        4. 取消勾选即可关闭权限
        
        注意：关闭权限后，应用将无法挂载远程磁盘。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "确定")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func applyLogLevel() {
        if !enableLogging {
            Logger.shared.setLogLevel(.off)
            return
        }
        
        let levelMap: [String: LogLevel] = [
            "调试": .debug,
            "信息": .info,
            "警告": .warning,
            "错误": .error,
            "崩溃": .crash
        ]
        
        if let level = levelMap[logLevel] {
            Logger.shared.setLogLevel(level)
        }
    }
}
