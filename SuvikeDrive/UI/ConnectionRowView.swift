//
//  ConnectionRowView.swift
//  SuvikeDrive
//
//  功能: 连接行视图
//  状态: 通过 EventBus 同步，带超时保护
//

import SwiftUI

struct ConnectionRowView: View {
    let server: ServerConfig
    let serverID: String
    let onDelete: (String) -> Void
    
    @State private var isMounted = false
    @State private var isMounting = false
    @State private var mountError: String?
    @State private var isHovering = false
    @State private var showingDeleteAlert = false
    @State private var timeoutWorkItem: DispatchWorkItem?
    
    @State private var eventTokens: [SubscriptionToken] = []
    
    // MARK: - 打开编辑连接窗口（通过 EventBus）
    private func openEditServerWindow() {
        EventBus.shared.publish(
            ConfigurationChanged(
                key: "popover.openEditConnection",
                oldValue: nil,
                newValue: serverID
            )
        )
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isMounted ? Color.green : (isMounting ? Color.orange : Color.gray))
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.3), value: isMounted || isMounting)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text(server.url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let error = mountError {
                Text("⚠️")
                    .font(.system(size: 11))
                    .help(error)
            }
            
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(statusColor)
                .padding(.trailing, 4)
            
            HStack(spacing: 6) {
                Button(action: toggleMount) {
                    Text(isMounted ? "卸载" : "挂载")
                        .font(.system(size: 11))
                        .foregroundColor(isMounted ? .orange : .green)
                }
                .buttonStyle(.plain)
                .disabled(isMounting)
                .opacity(isMounting ? 0.5 : 1.0)
                
                Button(action: openEditServerWindow) {
                    Text("编辑")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Button(action: { showingDeleteAlert = true }) {
                    Text("✕")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.gray.opacity(0.12) : Color.gray.opacity(0.04))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            openEditServerWindow()
        }
        .onAppear {
            updateMountStatus()
            setupEventBusListeners()
        }
        .onDisappear {
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            eventTokens.forEach { $0.unsubscribe() }
            eventTokens.removeAll()
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                onDelete(serverID)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除「\(server.name)」吗？\n\n这将卸载卷并删除挂载文件夹。")
        }
    }
    
    // MARK: - 计算属性
    private var statusText: String {
        if isMounting {
            return "挂载中..."
        } else if isMounted {
            return "已挂载"
        } else {
            return "未挂载"
        }
    }
    
    private var statusColor: Color {
        if isMounting {
            return .orange
        } else if isMounted {
            return .green
        } else {
            return .secondary
        }
    }
    
    // MARK: - EventBus 事件监听
    private func setupEventBusListeners() {
        let mountToken = EventBus.shared.subscribe(
            to: MountCompleted.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID {
                DispatchQueue.main.async {
                    self.timeoutWorkItem?.cancel()
                    self.timeoutWorkItem = nil
                    self.isMounted = true
                    self.isMounting = false
                    self.mountError = nil
                }
            }
        }
        eventTokens.append(mountToken)
        
        let mountFailToken = EventBus.shared.subscribe(
            to: MountFailed.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID {
                DispatchQueue.main.async {
                    self.timeoutWorkItem?.cancel()
                    self.timeoutWorkItem = nil
                    self.isMounted = false
                    self.isMounting = false
                    self.mountError = event.error
                }
            }
        }
        eventTokens.append(mountFailToken)
        
        let unmountToken = EventBus.shared.subscribe(
            to: UnmountCompleted.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID {
                DispatchQueue.main.async {
                    self.timeoutWorkItem?.cancel()
                    self.timeoutWorkItem = nil
                    self.isMounted = false
                    self.isMounting = false
                    self.mountError = nil
                }
            }
        }
        eventTokens.append(unmountToken)
        
        let unmountFailToken = EventBus.shared.subscribe(
            to: UnmountFailed.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID {
                DispatchQueue.main.async {
                    self.timeoutWorkItem?.cancel()
                    self.timeoutWorkItem = nil
                    self.isMounted = false
                    self.isMounting = false
                    self.mountError = event.error
                }
            }
        }
        eventTokens.append(unmountFailToken)
        
        let mountStartToken = EventBus.shared.subscribe(
            to: MountStarted.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID {
                DispatchQueue.main.async {
                    self.isMounting = true
                    self.mountError = nil
                }
            }
        }
        eventTokens.append(mountStartToken)
        
        let unmountStartToken = EventBus.shared.subscribe(
            to: UnmountStarted.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID {
                DispatchQueue.main.async {
                    self.isMounting = true
                    self.mountError = nil
                }
            }
        }
        eventTokens.append(unmountStartToken)
        
        // ✅ 监听删除成功事件
        let deleteToken = EventBus.shared.subscribe(
            to: ServerConfigDeleted.self,
            priority: .high
        ) { event in
            if event.serverID == self.serverID && event.success {
                DispatchQueue.main.async {
                    self.isMounted = false
                    self.isMounting = false
                    self.mountError = nil
                }
            }
        }
        eventTokens.append(deleteToken)
    }
    
    func updateMountStatus() {
        let config = ConfigurationManager.shared.getServer(id: serverID)
        if let config = config {
            let path = config.getMountPath()
            if FileManager.default.fileExists(atPath: path) {
                isMounted = MountManager.shared.isMounted(serverID: serverID)
            } else {
                isMounted = false
            }
        } else {
            isMounted = false
        }
        mountError = nil
    }
    
    func toggleMount() {
        guard !isMounting else { return }
        
        isMounting = true
        mountError = nil
        
        // ✅ 超时保护（30秒后自动重置）
        let workItem = DispatchWorkItem {
            if self.isMounting {
                print("⚠️ [ConnectionRowView] 操作超时: \(self.serverID)")
                self.isMounting = false
                self.mountError = "操作超时，请重试"
                self.updateMountStatus()
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
        
        if isMounted {
            print("📋 [ConnectionRowView] 开始卸载: \(serverID)")
            MountManager.shared.unmount(serverID: serverID, force: false) { _ in }
        } else {
            print("📋 [ConnectionRowView] 开始挂载: \(serverID)")
            guard let config = ConfigurationManager.shared.getServer(id: serverID) else {
                isMounting = false
                mountError = "配置不存在"
                return
            }
            MountManager.shared.mount(serverID: serverID, config: config) { _ in }
        }
    }
}
