//
//  MenuBarView.swift
//  SuvikeDrive
//
//  功能: 状态栏菜单 UI（纯 UI，所有逻辑通过 EventBus 通信）
//

import SwiftUI
import AppKit

// MARK: - 菜单栏行视图
struct MenuBarRowView: View {
    let server: ServerConfig
    let serverID: String
    let isMounted: Bool
    let isMounting: Bool
    let onToggleMount: () -> Void
    let onEdit: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        HStack {
            let iconName = protocolIconMap[server.protocolType.rawValue] ?? "folder"
            
            Image(systemName: iconName)
                .frame(width: 20)
                .foregroundColor(isMounted ? .accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(.body)
                    .lineLimit(1)
                Text(server.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            StatusBadge(isMounted: isMounted)
            
            if isMounting {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: isMounted ? "eject.circle" : "play.circle")
                    .foregroundColor(isMounted ? .orange : .green)
                    .font(.system(size: 18))
                    .onTapGesture {
                        onToggleMount()
                    }
                    .help(isMounted ? "卸载" : "挂载")
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .allowsHitTesting(false)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            onEdit()
        }
    }
    
    let protocolIconMap: [String: String] = [
        "webdav": "globe",
        "smb": "pc",
        "ftp": "arrow.up.doc",
        "sftp": "lock.shield",
        "nfs": "server.rack"
    ]
}

// MARK: - 菜单栏操作按钮
struct MenuBarActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var foregroundColor: Color = .primary
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 18)
                    .font(.body)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 状态徽章
struct StatusBadge: View {
    let isMounted: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isMounted ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(isMounted ? "已挂载" : "未挂载")
                .font(.caption2)
                .foregroundColor(isMounted ? .green : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isMounted ? Color.green.opacity(0.12) : Color.gray.opacity(0.08))
        )
    }
}

// MARK: - 空状态视图
struct EmptyStateView: View {
    @Binding var showingNewConnection: Bool
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(isHovering ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            Text("还没有连接")
                .font(.subheadline)
                .foregroundColor(isHovering ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
            Text("点击下方「新驱动器」添加")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            showingNewConnection = true
        }
    }
}

// MARK: - 主菜单视图（纯 UI）
struct MenuBarView: View {
    // MARK: - UI State
    @State private var servers: [ServerConfig] = []
    @State private var mountStates: [String: Bool] = [:]
    @State private var mountingStates: [String: Bool] = [:]
    
    // MARK: - 网络状态
    @ObservedObject private var networkManager = NetworkManager.shared
    
    // MARK: - OTA 管理器
    @StateObject private var otaViewModel = OTAManagerViewModel()
    
    // MARK: - 窗口控制
    @State private var showingNewConnection = false
    @State private var showingLogs = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var showingConnectionManagement = false
    
    @State private var editingServerID: String? = nil
    @State private var showingEditSheet = false
    
    // MARK: - EventBus 订阅
    @State private var eventTokens: [SubscriptionToken] = []
    
    // MARK: - 打开 Sheet 前关闭 Popover
    private func openSheet(_ action: @escaping () -> Void) {
        NotificationCenter.default.post(name: NSNotification.Name("OpenSheetFromPopover"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            action()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 标题栏
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 15))
                
                Text(AppInfo.appName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                networkStatusView
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // MARK: - 服务器列表
            ScrollView {
                VStack(spacing: 4) {
                    if servers.isEmpty {
                        EmptyStateView(showingNewConnection: $showingNewConnection)
                    } else {
                        ForEach(servers.indices, id: \.self) { index in
                            let server = servers[index]
                            MenuBarRowView(
                                server: server,
                                serverID: server.id,
                                isMounted: mountStates[server.id] ?? false,
                                isMounting: mountingStates[server.id] ?? false,
                                onToggleMount: {
                                    toggleMount(serverID: server.id)
                                },
                                onEdit: {
                                    editingServerID = server.id
                                    showingEditSheet = true
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 280)
            .scrollIndicators(.never)
            
            Divider()
            
            // MARK: - 底部功能菜单
            VStack(spacing: 2) {
                MenuBarActionButton(
                    title: "新驱动器",
                    icon: "plus",
                    action: {
                        openSheet { showingNewConnection = true }
                    }
                )
                
                MenuBarActionButton(
                    title: "连接管理",
                    icon: "list.bullet",
                    action: {
                        openSheet { showingConnectionManagement = true }
                    }
                )
                
                MenuBarActionButton(
                    title: "偏好设置",
                    icon: "gear",
                    action: {
                        openSheet { showingSettings = true }
                    }
                )
                
                Divider()
                    .padding(.vertical, 4)
                
                MenuBarActionButton(
                    title: "运行日志",
                    icon: "doc.text",
                    action: {
                        openSheet { showingLogs = true }
                    }
                )
                
                // ✅ 检查更新 - 使用 otaViewModel
                MenuBarActionButton(
                    title: "检查更新",
                    icon: "arrow.triangle.2.circlepath",
                    action: {
                        openSheet {
                            otaViewModel.checkForUpdate()
                        }
                    }
                )
                
                MenuBarActionButton(
                    title: "关于 \(AppInfo.appName)",
                    icon: "info.circle",
                    action: {
                        openSheet { showingAbout = true }
                    }
                )
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    MenuBarActionButton(
                        title: "退出",
                        icon: "power",
                        action: {
                            NSApplication.shared.terminate(nil)
                        },
                        foregroundColor: .red
                    )
                    .padding(.leading, -12)
                    
                    Spacer()
                    
                    Text("v\(AppInfo.appVersion)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)
        }
        .frame(width: 320)
        .onTapGesture {
            NotificationCenter.default.post(name: NSNotification.Name("CloseMainPopover"), object: nil)
        }
        .sheet(isPresented: $showingNewConnection) {
            AddServerView()
        }
        .sheet(isPresented: $showingEditSheet) {
            if let serverID = editingServerID {
                AddServerView(serverID: serverID, isEditing: true)
                    .onDisappear {
                        editingServerID = nil
                    }
            }
        }
        .sheet(isPresented: $showingLogs) {
            LogView(
                onLoadLogs: {
                    guard let logFile = Logger.shared.getCurrentLogFile() else {
                        return nil
                    }
                    guard FileManager.default.fileExists(atPath: logFile.path) else {
                        return nil
                    }
                    return try? String(contentsOf: logFile, encoding: .utf8)
                },
                onClearLogs: {
                    Logger.shared.clearAllLogs()
                },
                onExportLogs: {
                    return Logger.shared.exportLogs() != nil
                },
                onGetLogPath: {
                    return Logger.shared.getLogDirectory().path
                }
            )
            .frame(width: 700, height: 500)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingConnectionManagement) {
            ConnectionListView()
                .frame(width: 700, height: 500)
        }
        // ✅ OTA 管理器视图（用于显示 sheet）
        .overlay(
            OTAManagerView(viewModel: otaViewModel)
        )
        .onReceive(NotificationCenter.default.publisher(for: .MountStatusChanged)) { _ in
            updateMountStates()
        }
        .onAppear {
            setupEventBusListeners()
            EventBus.shared.publish(LoadServerListRequest())
        }
        .onDisappear {
            eventTokens.forEach { $0.unsubscribe() }
            eventTokens.removeAll()
        }
    }
    
    // MARK: - EventBus 事件监听
    private func setupEventBusListeners() {
        let listToken = EventBus.shared.subscribe(
            to: ServerListLoaded.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                self.servers = event.servers
                self.updateMountStates()
            }
        }
        eventTokens.append(listToken)
    }
    
    // MARK: - 更新挂载状态
    private func updateMountStates() {
        let mountedServers = MountManager.shared.getMountedServers()
        for server in servers {
            mountStates[server.id] = mountedServers.contains(server.id)
        }
    }
    
    // MARK: - 挂载/卸载
    private func toggleMount(serverID: String) {
        guard mountingStates[serverID] != true else { return }
        mountingStates[serverID] = true
        
        let isCurrentlyMounted = mountStates[serverID] ?? false
        guard let server = servers.first(where: { $0.id == serverID }) else {
            mountingStates[serverID] = false
            return
        }
        
        if isCurrentlyMounted {
            MountManager.shared.unmount(serverID: serverID, force: false) { _ in
                DispatchQueue.main.async {
                    mountingStates[serverID] = false
                    mountStates[serverID] = false
                    NotificationCenter.default.post(name: .MountStatusChanged, object: nil)
                }
            }
        } else {
            MountManager.shared.mount(serverID: serverID, config: server) { result in
                DispatchQueue.main.async {
                    mountingStates[serverID] = false
                    switch result {
                    case .success:
                        mountStates[serverID] = true
                    case .failure(let error):
                        print("挂载失败: \(error)")
                    }
                    NotificationCenter.default.post(name: .MountStatusChanged, object: nil)
                }
            }
        }
    }
    
    // MARK: - 网络状态视图
    private var networkStatusView: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.blue)
                Text(formatSpeedCompact(networkManager.downloadSpeed))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 52, alignment: .leading)
            
            HStack(spacing: 1) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                Text(formatSpeedCompact(networkManager.uploadSpeed))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 52, alignment: .leading)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 10)
            
            HStack(spacing: 2) {
                Circle()
                    .fill(MountManager.shared.getMountedServers().count > 0 ? Color.green : Color.gray)
                    .frame(width: 4, height: 4)
                Text("\(MountManager.shared.getMountedServers().count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                Image(systemName: "network")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .frame(width: 28, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(height: 20)
    }
    
    // MARK: - 速度格式化
    private func formatSpeedCompact(_ speed: Double) -> String {
        if speed >= 1024 * 1024 {
            return String(format: "%.1fM", speed / 1024 / 1024)
        } else if speed >= 1024 {
            return String(format: "%.1fK", speed / 1024)
        } else if speed > 0 {
            return String(format: "%.0fB", speed)
        } else {
            return "0B"
        }
    }
}

#Preview {
    MenuBarView()
}
