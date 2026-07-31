//
//  SettingsView.swift
//  SuvikeDrive
//
//  功能: 偏好设置主视图
//

import SwiftUI
import AppKit
import Combine

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @StateObject private var viewModel = SettingsViewModel()
    @Namespace private var tabAnimation
    
    // 标签列表
    private let tabs = ["同步", "通用", "缓存", "高级"]
    
    var body: some View {
        VStack(spacing: 0) {
            // ========== 标题栏 + 胶囊标签（居中）+ 完成按钮（右上） ==========
            ZStack {
                // 左侧占位（保持平衡）
                HStack {
                    Spacer()
                        .frame(width: 80)
                    Spacer()
                }
                
                // 胶囊标签（居中 + 动画）
                HStack(spacing: 4) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedTab = index
                            }
                        }) {
                            Text(tabs[index])
                                .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                                .foregroundColor(selectedTab == index ? .white : .secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 6)
                                .background(
                                    ZStack {
                                        if selectedTab == index {
                                            Capsule()
                                                .fill(Color.accentColor)
                                                .matchedGeometryEffect(id: "tab", in: tabAnimation)
                                        }
                                    }
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                
                // 完成按钮（右上角）
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.saveAllSettings()
                        dismiss()
                    }) {
                        Text("完成")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(height: 52)
            
            Divider()
            
            // ========== 标签页内容 ==========
            ScrollView {
                switch selectedTab {
                case 0:
                    SyncTab(viewModel: viewModel)
                        .padding(.horizontal, 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                case 1:
                    GeneralTab(viewModel: viewModel)
                        .padding(.horizontal, 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                case 2:
                    CacheTab(viewModel: viewModel)
                        .padding(.horizontal, 0)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        ))
                case 3:
                    AdvancedTab(viewModel: viewModel)
                        .padding(.horizontal, 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                default:
                    EmptyView()
                }
            }
            .scrollIndicators(.never)
            .background(Color(NSColor.controlBackgroundColor))
            .id(selectedTab)
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
            
            Divider()
            
            // ========== 底部栏 ==========
            // 缓存标签页底栏
            if selectedTab == 2 {
                HStack {
                    Text("缓存: \(viewModel.getCacheSize())  |  可用空间: \(viewModel.getFreeSpace())")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        viewModel.clearCache()
                    }) {
                        Text("清除缓存")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        viewModel.restoreCacheDefaults()
                    }) {
                        Text("恢复默认")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(height: 48)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            
            // 同步标签页底栏
            if selectedTab == 0 {
                HStack {
                    // 左侧：同步状态信息
                    HStack(spacing: 12) {
                        Circle()
                            .fill(viewModel.isSyncRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(viewModel.isSyncRunning ? "同步中..." : "同步就绪")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("|")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.3))
                        
                        Text("上次同步: \(viewModel.lastSyncTime)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 右侧：操作按钮
                    HStack(spacing: 8) {
                        Button(action: {
                            viewModel.syncAllServers()
                        }) {
                            Text("立即同步")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(viewModel.isSyncRunning ? Color.gray : Color.accentColor)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSyncRunning)
                        
                        Button(action: {
                            viewModel.stopSync()
                        }) {
                            Text("暂停同步")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.isSyncRunning)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(height: 48)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
        }
        .frame(minWidth: 660, minHeight: 460)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // 隐藏窗口标题栏文字
            if let window = NSApp.windows.first(where: { $0.title == "偏好设置" }) {
                window.title = "偏好设置"
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
            
            viewModel.setupEventBusListeners()
            viewModel.loadAllSettings()
            viewModel.loadCachePath()
            viewModel.checkFullDiskAccessStatus()
            viewModel.refreshDaemonStatus()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .alert("密码不匹配", isPresented: $viewModel.showingPasswordMismatch) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("两次输入的密码不一致，请重新输入")
        }
    }
}
