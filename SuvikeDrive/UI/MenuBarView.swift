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
                        EventBus.shared.publish(MenuBarMountToggleRequested(serverID: serverID))
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
            EventBus.shared.publish(MenuBarEditServerRequested(serverID: serverID))
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
    let foregroundColor: Color
    let action: () -> Void
    
    init(title: String, icon: String, foregroundColor: Color = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.foregroundColor = foregroundColor
        self.action = action
    }
    
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
            EventBus.shared.publish(MenuBarOpenNewConnectionRequested())
        }
    }
}

// MARK: - 主菜单视图（纯 UI，所有逻辑通过 EventBus 通信）
struct MenuBarView: View {
    // MARK: - UI State
    @State private var servers: [ServerConfig] = []
    @State private var mountStates: [String: Bool] = [:]
    @State private var mountingStates: [String: Bool] = [:]
    
    // MARK: - 网络流量状态（通过 EventBus 更新）
    @State private var downloadSpeed: Double = 0
    @State private var uploadSpeed: Double = 0
    @State private var mountedCount: Int = 0
    
    // MARK: - EventBus 订阅 Token
    @State private var eventTokens: [SubscriptionToken] = []
    
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
                        EmptyStateView()
                    } else {
                        ForEach(servers.indices, id: \.self) { index in
                            let server = servers[index]
                            MenuBarRowView(
                                server: server,
                                serverID: server.id,
                                isMounted: mountStates[server.id] ?? false,
                                isMounting: mountingStates[server.id] ?? false
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
                    title: "添加连接",
                    icon: "plus"
                ) {
                    EventBus.shared.publish(MenuBarOpenNewConnectionRequested())
                }
                
                MenuBarActionButton(
                    title: "连接管理",
                    icon: "list.bullet"
                ) {
                    EventBus.shared.publish(MenuBarOpenConnectionManagerRequested())
                }
                
                MenuBarActionButton(
                    title: "文件管理",
                    icon: "folder"
                ) {
                    let firstID = servers.first?.id
                    EventBus.shared.publish(MenuBarOpenFileBrowserRequested(serverID: firstID))
                }
                
                MenuBarActionButton(
                    title: "偏好设置",
                    icon: "gear"
                ) {
                    EventBus.shared.publish(MenuBarOpenSettingsRequested())
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                MenuBarActionButton(
                    title: "运行日志",
                    icon: "doc.text"
                ) {
                    EventBus.shared.publish(MenuBarOpenLogsRequested())
                }
                
                MenuBarActionButton(
                    title: "检查更新",
                    icon: "arrow.triangle.2.circlepath"
                ) {
                    EventBus.shared.publish(MenuBarOpenOTARequested())
                }
                
                MenuBarActionButton(
                    title: "关于 \(AppInfo.appName)",
                    icon: "info.circle"
                ) {
                    EventBus.shared.publish(MenuBarOpenAboutRequested())
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    MenuBarActionButton(
                        title: "退出",
                        icon: "power",
                        foregroundColor: .red
                    ) {
                        EventBus.shared.publish(MenuBarAppQuitRequested())
                    }
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
        .onAppear {
            setupEventBusListeners()
            
            EventBus.shared.publish(LoadServerListRequest())
            updateMountStates()
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
        
        let mountToken = EventBus.shared.subscribe(
            to: MountCompleted.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.mountStates[event.serverID] = true
                self.mountingStates[event.serverID] = false
                self.updateMountedCount()
            }
        }
        eventTokens.append(mountToken)
        
        let mountFailToken = EventBus.shared.subscribe(
            to: MountFailed.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.mountStates[event.serverID] = false
                self.mountingStates[event.serverID] = false
                self.updateMountedCount()
                Logger.shared.error("挂载失败: \(event.serverID) - \(event.error)")
            }
        }
        eventTokens.append(mountFailToken)
        
        let unmountToken = EventBus.shared.subscribe(
            to: UnmountCompleted.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.mountStates[event.serverID] = false
                self.mountingStates[event.serverID] = false
                self.updateMountedCount()
            }
        }
        eventTokens.append(unmountToken)
        
        let unmountFailToken = EventBus.shared.subscribe(
            to: UnmountFailed.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.mountStates[event.serverID] = false
                self.mountingStates[event.serverID] = false
                self.updateMountedCount()
                Logger.shared.error("卸载失败: \(event.serverID) - \(event.error)")
            }
        }
        eventTokens.append(unmountFailToken)
        
        let mountStartToken = EventBus.shared.subscribe(
            to: MountStarted.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.mountingStates[event.serverID] = true
            }
        }
        eventTokens.append(mountStartToken)
        
        let unmountStartToken = EventBus.shared.subscribe(
            to: UnmountStarted.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.mountingStates[event.serverID] = true
            }
        }
        eventTokens.append(unmountStartToken)
        
        let trafficToken = EventBus.shared.subscribe(
            to: TrafficStatsUpdated.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                self.downloadSpeed = event.downloadSpeed
                self.uploadSpeed = event.uploadSpeed
            }
        }
        eventTokens.append(trafficToken)
    }
    
    // MARK: - 更新挂载状态
    private func updateMountStates() {
        let mountedServers = MountManager.shared.getMountedServers()
        for server in servers {
            mountStates[server.id] = mountedServers.contains(server.id)
        }
        updateMountedCount()
    }
    
    private func updateMountedCount() {
        mountedCount = mountStates.values.filter { $0 }.count
    }
    
    // MARK: - 网络状态视图
    private var networkStatusView: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.blue)
                Text(formatSpeedCompact(downloadSpeed))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 52, alignment: .leading)
            
            HStack(spacing: 1) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                Text(formatSpeedCompact(uploadSpeed))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 52, alignment: .leading)
            
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 10)
            
            HStack(spacing: 2) {
                Circle()
                    .fill(mountedCount > 0 ? Color.green : Color.gray)
                    .frame(width: 4, height: 4)
                Text("\(mountedCount)")
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
