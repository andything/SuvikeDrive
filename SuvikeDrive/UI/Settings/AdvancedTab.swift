//
//  AdvancedTab.swift
//  SuvikeDrive
//
//  功能: 高级标签页
//

import SwiftUI
import Combine

struct AdvancedTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    private let menuWidth: CGFloat = 100
    private let timeoutOptions: [Int] = [5, 10, 15, 30, 60, 120]
    private let retryOptions: [Int] = [1, 2, 3, 5]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ========== 系统权限 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("守护进程")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Text(viewModel.daemonEnabled ? "已开启" : "已关闭")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.daemonEnabled ? .green : .gray)
                        Toggle("", isOn: Binding(
                            get: { viewModel.daemonEnabled },
                            set: { newValue in
                                viewModel.daemonEnabled = newValue
                                // ✅ 移除直接管理，只负责存储配置并通知 AppDelegate 接管
                                ConfigurationManager.shared.set(key: "app.daemon.enabled", value: newValue)
                                EventBus.shared.publish(ConfigurationChanged(key: "app.daemon.enabled", oldValue: !newValue, newValue: newValue))
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("全盘访问权限")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Text(viewModel.hasFullDiskAccess ? "已授权" : "未授权")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.hasFullDiskAccess ? .green : .orange)
                        Toggle("", isOn: Binding(
                            get: { viewModel.hasFullDiskAccess },
                            set: { newValue in
                                if newValue {
                                    if !viewModel.hasFullDiskAccess {
                                        viewModel.requestFullDiskAccess()
                                    }
                                } else {
                                    if viewModel.hasFullDiskAccess {
                                        viewModel.showFullDiskAccessGuide()
                                    }
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    }
                    .onAppear {
                        viewModel.checkFullDiskAccessStatus()
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "shield", title: "系统权限")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // ========== 状态栏 ==========
            GroupBox {
                HStack {
                    Text("状态栏流量监控")
                        .font(.system(size: 13))
                        .padding(.leading, 4)
                    Spacer()
                    Text(viewModel.statusBarTrafficMonitor ? "已开启" : "已关闭")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.statusBarTrafficMonitor ? .green : .gray)
                    Toggle("", isOn: $viewModel.statusBarTrafficMonitor)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                        .onChange(of: viewModel.statusBarTrafficMonitor) { _, newValue in
                            if newValue {
                                NetworkManager.shared.startInterfaceMonitoring()
                                Logger.shared.info("状态栏流量监控已开启")
                            } else {
                                NetworkManager.shared.stopInterfaceMonitoring()
                                Logger.shared.info("状态栏流量监控已关闭")
                            }
                        }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "macwindow", title: "状态栏")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 网络设置 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("请求超时 (秒)")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Menu {
                            ForEach(timeoutOptions, id: \.self) { option in
                                Button(action: {
                                    viewModel.timeout = option
                                    ConfigurationManager.shared.set(key: "network.timeout", value: option)
                                    EventBus.shared.publish(ConfigurationChanged(key: "network.timeout", oldValue: nil, newValue: option))
                                }) {
                                    HStack {
                                        Text("\(option)")
                                        if viewModel.timeout == option {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("\(viewModel.timeout)")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .frame(width: menuWidth, alignment: .trailing)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("最大重试次数")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Menu {
                            ForEach(retryOptions, id: \.self) { option in
                                Button(action: {
                                    viewModel.maxRetries = option
                                    ConfigurationManager.shared.set(key: "network.maxRetries", value: option)
                                    EventBus.shared.publish(ConfigurationChanged(key: "network.maxRetries", oldValue: nil, newValue: option))
                                }) {
                                    HStack {
                                        Text("\(option)")
                                        if viewModel.maxRetries == option {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("\(viewModel.maxRetries)")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .frame(width: menuWidth, alignment: .trailing)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(.trailing, 4)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "network", title: "网络设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 日志 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleView(label: "启用日志记录", isOn: $viewModel.enableLogging) { newValue in
                        if !newValue {
                            Logger.shared.setLogLevel(.off)
                        } else {
                            viewModel.applyLogLevel()
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("日志级别")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Menu {
                            ForEach(viewModel.logLevels, id: \.self) { level in
                                Button(action: {
                                    viewModel.logLevel = level
                                    ConfigurationManager.shared.set(key: "log.level", value: level)
                                    viewModel.applyLogLevel()
                                    EventBus.shared.publish(ConfigurationChanged(key: "log.level", oldValue: nil, newValue: level))
                                }) {
                                    HStack {
                                        Text(level)
                                        if viewModel.logLevel == level {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(viewModel.logLevel)
                                .font(.system(size: 12))
                                .foregroundColor(viewModel.enableLogging ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .frame(width: menuWidth, alignment: .trailing)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(viewModel.enableLogging ? 0.1 : 0.05))
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(!viewModel.enableLogging)
                        .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    Text("调试 → 最详细  |  信息 → 常规  |  警告 → 潜在问题  |  错误 → 功能异常  |  崩溃 → 严重崩溃")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.leading, 4)
                    
                    Divider()
                    
                    ToggleView(label: "发送匿名统计信息", isOn: $viewModel.analytics)
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "doc.text", title: "日志")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
