//
//  GeneralTab.swift
//  SuvikeDrive
//
//  功能: 通用标签页
//

import SwiftUI

struct GeneralTab: View {
    @Binding var startAtLogin: Bool
    @Binding var autoMount: Bool
    @Binding var showDesktop: Bool
    @Binding var shortName: Bool
    @Binding var mountDelay: Int
    @Binding var refreshInterval: Int
    
    // 加密设置
    @Binding var forceEncryptExport: Bool
    @Binding var exportPassword: String
    @Binding var confirmExportPassword: String
    @Binding var showingPasswordMismatch: Bool
    
    var body: some View {
        Group {
            Section {
                Toggle("系统登录时打开 SuvikeDrive", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { _, newValue in
                        PermissionManager.shared.toggleStartAtLogin(enabled: newValue)
                    }
                Toggle("应用启动时自动挂载所有连接", isOn: $autoMount)
                Toggle("在桌面显示已挂载的驱动器", isOn: $showDesktop)
                Toggle("在\"访达\"侧边栏中使用短设备名称", isOn: $shortName)
            }
            
            Section {
                HStack {
                    Text("延时挂载")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $mountDelay) {
                        Text("1 秒").tag(1)
                        Text("2 秒").tag(2)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                        Text("10 秒").tag(10)
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .disabled(!autoMount)
                    .opacity(autoMount ? 1 : 0.5)
                }
                
                HStack {
                    Text("刷新间隔")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text("不刷新").tag(0)
                        Text("1 分钟").tag(60)
                        Text("5 分钟").tag(300)
                        Text("10 分钟").tag(600)
                        Text("30 分钟").tag(1800)
                        Text("60 分钟").tag(3600)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }
            
            Section("数据管理") {
                HStack {
                    Text("导出加密")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $forceEncryptExport)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                HStack(spacing: 8) {
                    Text("设置密码")
                        .font(.body)
                        .frame(width: 70, alignment: .leading)
                    
                    SecureField("", text: $exportPassword)
                        .textFieldStyle(.plain)
                }
                
                HStack(spacing: 8) {
                    Text("确认密码")
                        .font(.body)
                        .frame(width: 70, alignment: .leading)
                    
                    SecureField("", text: $confirmExportPassword)
                        .textFieldStyle(.plain)
                }
                
                HStack {
                    Text("导出配置时将使用此密码加密，导入时需要输入相同密码解密")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    SettingsCapsuleActionButton(
                        title: "保存",
                        action: {
                            savePassword()
                        },
                        backgroundColor: (exportPassword.isEmpty || confirmExportPassword.isEmpty) ? Color.gray.opacity(0.3) : Color.accentColor,
                        foregroundColor: (exportPassword.isEmpty || confirmExportPassword.isEmpty) ? .gray : .white
                    )
                    .disabled(exportPassword.isEmpty || confirmExportPassword.isEmpty)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private func savePassword() {
        if exportPassword != confirmExportPassword {
            showingPasswordMismatch = true
            return
        }
        
        if exportPassword.isEmpty {
            let alert = NSAlert()
            alert.messageText = "密码不能为空"
            alert.informativeText = "请设置一个导出密码"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        _ = ConfigCrypto.savePassword(exportPassword, forKey: "export.password")
        ConfigurationManager.shared.set(key: "export.forceEncrypt", value: forceEncryptExport)
        
        let alert = NSAlert()
        alert.messageText = "密码已更新"
        alert.informativeText = "导出配置将使用新密码加密"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
        
        Logger.shared.info("导出密码已更新")
    }
}
