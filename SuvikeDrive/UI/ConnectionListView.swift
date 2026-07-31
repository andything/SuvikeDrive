//
//  ConnectionListView.swift
//  SuvikeDrive
//
//  功能: 连接管理/服务器列表管理（纯 UI，所有逻辑通过 EventBus 通信）
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 加密文档（用于导出）
struct EncryptedDocument: FileDocument {
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    static var readableContentTypes: [UTType] { [.data] }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 连接管理专用按钮样式
struct ConnectionCapsuleIconButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var color: Color = .secondary
    var help: String? = nil
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHovering ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 连接管理专用主色按钮
struct ConnectionCapsulePrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var help: String? = nil
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isHovering ? Color.accentColor.opacity(0.8) : Color.accentColor)
        )
        .foregroundColor(.white)
        .help(help ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 密码输入对话框
struct PasswordInputDialog: View {
    @Binding var password: String
    let title: String
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isPasswordFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            SecureField("请输入密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .foregroundColor(.primary)
                .focused($isPasswordFocused)
                .onSubmit {
                    if !password.isEmpty {
                        onConfirm()
                    }
                }
            
            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
                .buttonStyle(.plain)
                
                Button("确定") {
                    onConfirm()
                }
                .keyboardShortcut(.return)
                .disabled(password.isEmpty)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(password.isEmpty ? .gray : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(password.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                )
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPasswordFocused = true
            }
        }
    }
}

// MARK: - 服务器列表管理视图
struct ConnectionListView: View {
    @State private var servers: [ServerConfig] = []
    @State private var searchText = ""
    @State private var showingImportDialog = false
    @State private var showingExportDialog = false
    @State private var exportData: Data?
    @State private var mountedCount = 0
    @Environment(\.dismiss) var dismiss
    
    @State private var showingImportPassword = false
    @State private var importPassword = ""
    @State private var importFileURL: URL?
    @State private var isImportingEncrypted = false
    
    @State private var toastMessage: String = ""
    @State private var showToast: Bool = false
    @State private var toastColor: Color = .green
    
    @State private var eventTokens: [SubscriptionToken] = []
    
    var filteredServers: [ServerConfig] {
        if searchText.isEmpty {
            return servers
        }
        let searchLower = searchText.lowercased()
        let searchNormalized = searchLower.folding(options: .diacriticInsensitive, locale: nil)
        
        return servers.filter {
            let name = $0.name.lowercased()
            let url = $0.url.lowercased()
            let nameNormalized = name.folding(options: .diacriticInsensitive, locale: nil)
            let urlNormalized = url.folding(options: .diacriticInsensitive, locale: nil)
            return nameNormalized.contains(searchNormalized) || urlNormalized.contains(searchNormalized)
        }
    }
    
    // MARK: - 打开添加连接窗口（通过 EventBus）
    private func openAddServerWindow() {
        EventBus.shared.publish(
            ConfigurationChanged(
                key: "popover.openNewConnection",
                oldValue: nil,
                newValue: nil
            )
        )
    }
    
    // MARK: - 删除连接
    private func deleteConnection(serverID: String) {
        print("📋 [ConnectionListView] 删除连接: \(serverID)")
        
        let alert = NSAlert()
        alert.messageText = "删除连接"
        alert.informativeText = "确定要删除此连接吗？\n\n这将卸载卷并删除挂载文件夹。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.window.level = .statusBar
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            EventBus.shared.publish(
                ConfigurationChanged(
                    key: "server.delete",
                    oldValue: nil,
                    newValue: serverID
                )
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Spacer()
                
                HStack(spacing: 12) {
                    if !searchText.isEmpty {
                        Text("已筛选: \(filteredServers.count) 个")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ConnectionCapsuleIconButton(
                        icon: "square.and.arrow.down",
                        title: "导入",
                        action: { showingImportDialog = true },
                        help: "导入配置"
                    )
                    
                    ConnectionCapsuleIconButton(
                        icon: "square.and.arrow.up",
                        title: "导出",
                        action: prepareExport,
                        help: "导出配置"
                    )
                    .disabled(servers.isEmpty)
                    .opacity(servers.isEmpty ? 0.5 : 1)
                    
                    ConnectionCapsulePrimaryButton(
                        title: "添加",
                        icon: "plus",
                        action: openAddServerWindow,
                        help: "添加新服务器"
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(height: 52)
            
            Divider()
                .foregroundColor(Color(NSColor.separatorColor))
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("筛选服务器...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(height: 56)
            
            Divider()
                .foregroundColor(Color(NSColor.separatorColor))
            
            // 内容区域
            if filteredServers.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filteredServers, id: \.id) { server in
                            ConnectionRowView(
                                server: server,
                                serverID: server.id,
                                onDelete: { serverID in
                                    deleteConnection(serverID: serverID)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            Divider()
                .foregroundColor(Color(NSColor.separatorColor))
            
            // 底部状态
            HStack {
                if searchText.isEmpty {
                    Text("共 \(servers.count) 个服务器")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("共 \(servers.count) 个服务器 (筛选: \(filteredServers.count) 个)")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                Spacer()
                Text("\(mountedCount) 个已挂载")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("•")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("缓存: \(CacheManager.shared.getCacheSizeFormatted())")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                if showToast {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: toastColor == .green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(toastColor)
                        Text(toastMessage)
                            .font(.system(size: 12))
                            .foregroundColor(toastColor == .green ? .green : .red)
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showToast)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(height: 32)
        }
        .frame(width: 700, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importFileURL = url
                    if isEncryptedFile(at: url) {
                        isImportingEncrypted = true
                        showingImportPassword = true
                    } else {
                        importPlainConfig(from: url)
                    }
                }
            case .failure(let error):
                showErrorAlert(title: "导入失败", message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showingImportPassword) {
            PasswordInputDialog(
                password: $importPassword,
                title: "输入解密密码",
                message: "此配置文件已加密，请输入密码解密",
                onConfirm: {
                    if !importPassword.isEmpty {
                        importEncryptedConfig(password: importPassword)
                        importPassword = ""
                        showingImportPassword = false
                    }
                },
                onCancel: {
                    importPassword = ""
                    showingImportPassword = false
                }
            )
        }
        .fileExporter(
            isPresented: $showingExportDialog,
            document: exportData.map { EncryptedDocument(data: $0) },
            contentType: .data,
            defaultFilename: getDefaultFilename()
        ) { result in
            switch result {
            case .success(let url):
                showToastMessage(message: "已导出：\(url.lastPathComponent)", isSuccess: true)
            case .failure(let error):
                showErrorAlert(title: "导出失败", message: error.localizedDescription)
            }
        }
        .onAppear {
            loadServers()
            updateMountStatus()
            setupEventBusListeners()
            EventBus.shared.publish(LoadServerListRequest())
        }
        .onDisappear {
            eventTokens.forEach { $0.unsubscribe() }
            eventTokens.removeAll()
        }
    }
    
    var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            Text(searchText.isEmpty ? "还没有服务器" : "没有匹配的服务器")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if searchText.isEmpty {
                Text("点击「添加」创建第一个连接")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - EventBus 事件监听
    private func setupEventBusListeners() {
        let listToken = EventBus.shared.subscribe(
            to: ServerListLoaded.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                self.servers = event.servers
                self.updateMountStatus()
            }
        }
        eventTokens.append(listToken)
        
        let saveToken = EventBus.shared.subscribe(
            to: ServerConfigSaved.self,
            priority: .medium
        ) { event in
            if event.success {
                DispatchQueue.main.async {
                    self.loadServers()
                }
            }
        }
        eventTokens.append(saveToken)
        
        let deleteToken = EventBus.shared.subscribe(
            to: ServerConfigDeleted.self,
            priority: .medium
        ) { event in
            if event.success {
                DispatchQueue.main.async {
                    self.loadServers()
                    self.showToastMessage(message: "已删除", isSuccess: true)
                }
            }
        }
        eventTokens.append(deleteToken)
        
        let configToken = EventBus.shared.subscribe(
            to: ConfigurationChanged.self,
            priority: .low
        ) { _ in
            DispatchQueue.main.async {
                self.loadServers()
                self.updateMountStatus()
            }
        }
        eventTokens.append(configToken)
        
        let mountToken = EventBus.shared.subscribe(
            to: MountCompleted.self,
            priority: .low
        ) { _ in
            DispatchQueue.main.async {
                self.updateMountStatus()
            }
        }
        eventTokens.append(mountToken)
        
        let mountFailToken = EventBus.shared.subscribe(
            to: MountFailed.self,
            priority: .low
        ) { _ in
            DispatchQueue.main.async {
                self.updateMountStatus()
            }
        }
        eventTokens.append(mountFailToken)
        
        let unmountToken = EventBus.shared.subscribe(
            to: UnmountCompleted.self,
            priority: .low
        ) { _ in
            DispatchQueue.main.async {
                self.updateMountStatus()
            }
        }
        eventTokens.append(unmountToken)
        
        let unmountFailToken = EventBus.shared.subscribe(
            to: UnmountFailed.self,
            priority: .low
        ) { _ in
            DispatchQueue.main.async {
                self.updateMountStatus()
            }
        }
        eventTokens.append(unmountFailToken)
    }
    
    // MARK: - Toast 提示
    func showToastMessage(message: String, isSuccess: Bool = true) {
        withAnimation(.easeInOut(duration: 0.3)) {
            toastMessage = message
            toastColor = isSuccess ? .green : .red
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
    
    // MARK: - 错误弹窗
    func showErrorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.window.level = .statusBar
            alert.runModal()
        }
    }
    
    func loadServers() {
        servers = ConfigurationManager.shared.getServers()
    }
    
    func updateMountStatus() {
        mountedCount = MountManager.shared.getMountCount()
    }
    
    func getDefaultFilename() -> String {
        let forceEncrypt = ConfigurationManager.shared.get(key: "export.forceEncrypt", defaultValue: true)
        let savedPassword = ConfigurationManager.shared.get(key: "export.password", defaultValue: "")
        
        if forceEncrypt && !savedPassword.isEmpty {
            return "SuvikeDrive_Config.suvike"
        } else {
            return "\(AppInfo.appName)_Config.json"
        }
    }
    
    func isEncryptedFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        if data.count > 60 {
            let firstByte = data.first ?? 0
            if firstByte != 0x7B && firstByte != 0x5B {
                return true
            }
        }
        return false
    }
    
    func prepareExport() {
        let servers = ConfigurationManager.shared.getServers()
        guard !servers.isEmpty else {
            showErrorAlert(title: "导出失败", message: "没有可导出的配置")
            return
        }
        
        let forceEncrypt = ConfigurationManager.shared.get(key: "export.forceEncrypt", defaultValue: true)
        let savedPassword = ConfigurationManager.shared.get(key: "export.password", defaultValue: "")
        
        if forceEncrypt && savedPassword.isEmpty {
            showErrorAlert(title: "导出失败", message: "请在「偏好设置 → 通用 → 数据管理」中设置导出密码")
            return
        }
        
        do {
            let serversData = servers.map { $0.toDictionary() }
            let exportDataDict: [String: Any] = [
                "version": forceEncrypt ? "2.0" : "1.0",
                "encrypted": forceEncrypt,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "servers": serversData
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: exportDataDict, options: .prettyPrinted)
            
            if forceEncrypt {
                guard let encryptedData = ConfigCrypto.encrypt(data: jsonData, password: savedPassword) else {
                    showErrorAlert(title: "导出失败", message: "加密失败，请重试")
                    return
                }
                self.exportData = encryptedData
            } else {
                self.exportData = jsonData
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showingExportDialog = true
            }
        } catch {
            showErrorAlert(title: "导出失败", message: error.localizedDescription)
        }
    }
    
    func importPlainConfig(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                importServers(json)
                return
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["servers"] as? [[String: Any]] {
                importServers(servers)
                return
            }
            
            showErrorAlert(title: "导入失败", message: "配置格式无效")
        } catch {
            showErrorAlert(title: "导入失败", message: error.localizedDescription)
        }
    }
    
    func importEncryptedConfig(password: String) {
        guard let url = importFileURL else { return }
        
        do {
            let encryptedData = try Data(contentsOf: url)
            
            guard let decryptedData = ConfigCrypto.decrypt(data: encryptedData, password: password) else {
                showErrorAlert(title: "导入失败", message: "解密失败，请检查密码是否正确")
                return
            }
            
            guard let json = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
                  let servers = json["servers"] as? [[String: Any]] else {
                showErrorAlert(title: "导入失败", message: "配置格式无效")
                return
            }
            
            importServers(servers)
        } catch {
            showErrorAlert(title: "导入失败", message: error.localizedDescription)
        }
    }
    
    func importServers(_ serversToImport: [[String: Any]]) {
        let existingServers = ConfigurationManager.shared.getServers()
        
        for server in existingServers {
            ConfigurationManager.shared.removeServer(id: server.id)
        }
        
        for serverDict in serversToImport {
            let server = ServerConfig.fromDictionary(serverDict)
            ConfigurationManager.shared.addServer(server)
        }
        
        showToastMessage(message: "已导入 \(serversToImport.count) 个配置", isSuccess: true)
        
        EventBus.shared.publish(
            ConfigurationChanged(
                key: "servers",
                oldValue: nil,
                newValue: serversToImport
            )
        )
        loadServers()
        updateMountStatus()
    }
}

// MARK: - 连接窗口控制器
class ConnectionWindowController: NSWindowController {
    static let shared = ConnectionWindowController()
    
    private override init(window: NSWindow?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "连接管理"
        window.contentView = NSHostingView(rootView: ConnectionListView())
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeWindow() {
        window?.close()
    }
}
