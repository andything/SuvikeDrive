//
//  SyncTab.swift
//  SuvikeDrive
//
//  功能: 同步设置标签页
//

import SwiftUI
import Combine
import AppKit

struct SyncTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ========== 同步设置 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleView(label: "启用自动同步", isOn: $viewModel.autoSyncEnabled) { newValue in
                        ConfigurationManager.shared.set(key: "sync.autoSync", value: newValue)
                        EventBus.shared.publish(ConfigurationChanged(key: "sync.autoSync", oldValue: nil, newValue: newValue))
                    }
                    
                    Divider()
                    
                    ToggleView(label: "启动时自动同步", isOn: $viewModel.syncOnLaunch) { newValue in
                        ConfigurationManager.shared.set(key: "sync.onLaunch", value: newValue)
                        EventBus.shared.publish(ConfigurationChanged(key: "sync.onLaunch", oldValue: nil, newValue: newValue))
                    }
                    
                    Divider()
                    
                    ToggleView(label: "后台实时同步", isOn: $viewModel.syncRealtime) { newValue in
                        ConfigurationManager.shared.set(key: "sync.realtime", value: newValue)
                        EventBus.shared.publish(ConfigurationChanged(key: "sync.realtime", oldValue: nil, newValue: newValue))
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "arrow.triangle.2.circlepath", title: "同步设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // ========== 同步方向 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("同步方向")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Menu {
                            ForEach(["双向同步", "仅上传", "仅下载"], id: \.self) { direction in
                                Button(action: {
                                    viewModel.syncDirection = direction
                                    ConfigurationManager.shared.set(key: "sync.direction", value: direction)
                                    EventBus.shared.publish(ConfigurationChanged(key: "sync.direction", oldValue: nil, newValue: direction))
                                }) {
                                    HStack {
                                        Text(direction)
                                        if viewModel.syncDirection == direction {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(viewModel.syncDirection)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .frame(width: 120, alignment: .trailing)
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
                LabelView(icon: "arrow.left.arrow.right", title: "同步方向")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 冲突处理 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("冲突处理")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Menu {
                            ForEach(["保留最新", "保留本地", "保留远程", "手动处理"], id: \.self) { strategy in
                                Button(action: {
                                    viewModel.conflictStrategy = strategy
                                    ConfigurationManager.shared.set(key: "sync.conflictStrategy", value: strategy)
                                    EventBus.shared.publish(ConfigurationChanged(key: "sync.conflictStrategy", oldValue: nil, newValue: strategy))
                                }) {
                                    HStack {
                                        Text(strategy)
                                        if viewModel.conflictStrategy == strategy {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(viewModel.conflictStrategy)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .frame(width: 120, alignment: .trailing)
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
                LabelView(icon: "exclamationmark.triangle", title: "冲突处理")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 同步路径 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        Text(viewModel.syncLocalPath)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        SettingsCapsuleActionButton(
                            title: "选择",
                            action: {
                                // ✅ 直接在闭包中实现路径选择
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.title = "选择本地同步目录"
                                panel.prompt = "选择"
                                panel.level = .floating
                                panel.center()
                                panel.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                                
                                if !viewModel.syncLocalPath.isEmpty && FileManager.default.fileExists(atPath: viewModel.syncLocalPath) {
                                    panel.directoryURL = URL(fileURLWithPath: viewModel.syncLocalPath)
                                }
                                
                                panel.begin { response in
                                    if response == .OK, let url = panel.url {
                                        viewModel.syncLocalPath = url.path
                                        ConfigurationManager.shared.set(key: "sync.localPath", value: url.path)
                                        Logger.shared.info("同步本地路径已更新: \(url.path)")
                                    }
                                }
                            }
                        )
                    }
                    
                    Divider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        Text(viewModel.syncRemotePath)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        SettingsCapsuleActionButton(
                            title: "选择",
                            action: {
                                // ✅ 直接在闭包中实现功能提示
                                let alert = NSAlert()
                                alert.messageText = "功能开发中"
                                alert.informativeText = "远程路径选择功能即将推出"
                                alert.alertStyle = .informational
                                alert.addButton(withTitle: "确定")
                                alert.runModal()
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "arrow.left.arrow.right", title: "同步路径")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 同步选项 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleView(label: "包含子目录", isOn: $viewModel.syncIncludeSubdirs) { newValue in
                        ConfigurationManager.shared.set(key: "sync.includeSubdirs", value: newValue)
                        EventBus.shared.publish(ConfigurationChanged(key: "sync.includeSubdirs", oldValue: nil, newValue: newValue))
                    }
                    
                    Divider()
                    
                    ToggleView(label: "同步隐藏文件", isOn: $viewModel.syncHiddenFiles) { newValue in
                        ConfigurationManager.shared.set(key: "sync.hiddenFiles", value: newValue)
                        EventBus.shared.publish(ConfigurationChanged(key: "sync.hiddenFiles", oldValue: nil, newValue: newValue))
                    }
                    
                    Divider()
                    
                    ToggleView(label: "删除远程多余文件", isOn: $viewModel.syncDeleteRemote) { newValue in
                        ConfigurationManager.shared.set(key: "sync.deleteRemote", value: newValue)
                        EventBus.shared.publish(ConfigurationChanged(key: "sync.deleteRemote", oldValue: nil, newValue: newValue))
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "list.bullet", title: "同步选项")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 同步服务器 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    let servers = viewModel.mountedServers
                    if servers.isEmpty {
                        HStack {
                            Text("暂无挂载的服务器")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(servers, id: \.self) { serverName in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { viewModel.isSyncEnabled(for: serverName) },
                                    set: { newValue in
                                        viewModel.setSyncEnabled(for: serverName, enabled: newValue)
                                    }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                
                                Text(serverName)
                                    .font(.system(size: 13))
                                    .padding(.leading, 4)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(viewModel.getSyncStatus(for: serverName))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            if serverName != servers.last {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "server.rack", title: "同步服务器")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
