//
//  GeneralTab.swift
//  SuvikeDrive
//
//  功能: 通用标签页
//

import SwiftUI
import Combine

struct GeneralTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    private let menuWidth: CGFloat = 100
    private let mountDelayOptions: [Int] = [1, 2, 3, 5, 10, 15, 30, 60]
    private let refreshIntervalOptions: [Int] = [0, 60, 300, 600, 1800, 3600]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ========== 通用设置 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleView(label: "系统登录时打开 SuvikeDrive", isOn: $viewModel.startAtLogin) {
                        PermissionManager.shared.toggleStartAtLogin(enabled: $0)
                    }
                    
                    Divider()
                    
                    ToggleView(label: "应用启动时自动挂载所有连接", isOn: $viewModel.autoMount)
                    
                    Divider()
                    
                    ToggleView(label: "在桌面显示已挂载的驱动器", isOn: $viewModel.showDesktop)
                    
                    Divider()
                    
                    ToggleView(label: "在\"访达\"侧边栏中使用短设备名称", isOn: $viewModel.shortName)
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "gear", title: "通用设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // ========== 定时任务 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsMenuPicker(
                        label: "延时挂载",
                        selection: $viewModel.mountDelay,
                        options: mountDelayOptions,
                        formatter: { "\($0) 秒" },
                        width: menuWidth,
                        disabled: !viewModel.autoMount
                    )
                    
                    Divider()
                    
                    SettingsMenuPicker(
                        label: "刷新间隔",
                        selection: $viewModel.refreshInterval,
                        options: refreshIntervalOptions,
                        formatter: { value in
                            switch value {
                            case 0: return "不刷新"
                            case 60: return "1 分钟"
                            case 300: return "5 分钟"
                            case 600: return "10 分钟"
                            case 1800: return "30 分钟"
                            case 3600: return "60 分钟"
                            default: return "\(value) 秒"
                            }
                        },
                        width: menuWidth
                    )
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "clock", title: "定时任务")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 数据管理 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleView(label: "导出加密", isOn: $viewModel.forceEncryptExport)
                    
                    Divider()
                    
                    HStack(spacing: 8) {
                        Text("设置密码")
                            .font(.system(size: 13))
                            .frame(width: 70, alignment: .leading)
                            .padding(.leading, 4)
                        SecureField("", text: $viewModel.exportPassword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack(spacing: 8) {
                        Text("确认密码")
                            .font(.system(size: 13))
                            .frame(width: 70, alignment: .leading)
                            .padding(.leading, 4)
                        SecureField("", text: $viewModel.confirmExportPassword)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("导出配置时将使用此密码加密，导入时需要输入相同密码解密")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        Spacer()
                        SettingsCapsuleActionButton(
                            title: "保存",
                            action: {
                                viewModel.savePassword()
                            },
                            backgroundColor: (viewModel.exportPassword.isEmpty || viewModel.confirmExportPassword.isEmpty) ? Color.gray.opacity(0.3) : Color.accentColor,
                            foregroundColor: (viewModel.exportPassword.isEmpty || viewModel.confirmExportPassword.isEmpty) ? .gray : .white
                        )
                        .disabled(viewModel.exportPassword.isEmpty || viewModel.confirmExportPassword.isEmpty)
                        .padding(.trailing, 4)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "lock", title: "数据管理")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
