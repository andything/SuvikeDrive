//
//  AddServerView.swift
//  SuvikeDrive
//
//  功能: 添加/编辑服务器 UI
//

import SwiftUI
import AppKit

// MARK: - 左对齐文本框
struct LeftAlignedTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .left
        textField.font = .systemFont(ofSize: 13)
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LeftAlignedTextField
        private var isUpdating = false
        
        init(_ parent: LeftAlignedTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard !isUpdating else { return }
            isUpdating = true
            defer { isUpdating = false }
            
            if let textField = obj.object as? NSTextField {
                DispatchQueue.main.async {
                    self.parent.text = textField.stringValue
                }
            }
        }
    }
}

// MARK: - 安全文本框（修复版 - 实时绑定）
struct LeftAlignedSecureField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField()
        textField.stringValue = text
        textField.placeholderString = placeholder
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .left
        textField.font = .systemFont(ofSize: 13)
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LeftAlignedSecureField
        
        init(_ parent: LeftAlignedSecureField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                DispatchQueue.main.async {
                    self.parent.text = textField.stringValue
                }
            }
        }
    }
}

// MARK: - 统一胶囊按钮样式
struct CapsuleButtonStyle: ButtonStyle {
    let color: Color
    var isProminent: Bool = false
    @State private var isHovering: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isProminent ? .white : (isHovering ? color : color))
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isProminent ? (isHovering ? color.opacity(0.8) : color) : (isHovering ? color.opacity(0.2) : color.opacity(0.1)))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
    }
}

// MARK: - 端口输入子视图
struct PortInputView: View {
    @Binding var config: ServerConfig
    @State private var textValue: String = ""
    @State private var isUpdating = false
    @State private var lastKnownPort: Int? = nil
    
    var body: some View {
        LeftAlignedTextField(
            text: $textValue,
            placeholder: String(config.protocolType.defaultPort)
        )
        .onAppear {
            updateTextValue()
            lastKnownPort = getCustomPort()
        }
        .onChange(of: config.protocolType) { _, _ in
            updateTextValue()
        }
        .onChange(of: config) { _, _ in
            let currentPort = getCustomPort()
            if lastKnownPort != currentPort {
                lastKnownPort = currentPort
                updateTextValue()
            }
        }
        .onChange(of: textValue) { _, newValue in
            guard !isUpdating else { return }
            isUpdating = true
            defer { isUpdating = false }
            
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue {
                textValue = filtered
                return
            }
            
            if filtered.isEmpty {
                config.protocolConfig.removeValue(forKey: "port")
                lastKnownPort = nil
            } else if let portNum = Int(filtered), portNum > 0, portNum <= 65535 {
                config.setProtocolConfig(key: "port", value: portNum)
                lastKnownPort = portNum
            }
        }
    }
    
    /// 获取用户手动设置的自定义端口（nil = 使用默认端口）
    private func getCustomPort() -> Int? {
        return config.protocolConfig["port"]?.value as? Int
    }
    
    private func updateTextValue() {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        
        let customPort = getCustomPort()
        let newValue: String
        if let storedPort = customPort {
            if storedPort == config.protocolType.defaultPort {
                newValue = ""
            } else {
                newValue = String(storedPort)
            }
        } else {
            newValue = ""
        }
        if textValue != newValue {
            textValue = newValue
        }
        lastKnownPort = customPort
    }
}

// MARK: - 主视图
struct AddServerView: View {
    @Environment(\.dismiss) var dismiss
    
    let serverID: String?
    let isEditing: Bool
    
    @State private var config: ServerConfig
    @State private var showPassword: Bool = false
    @State private var isConnecting: Bool = false
    @State private var connectionError: String?
    @State private var showTestResult = false
    @State private var testResult: NetworkTestResult?
    @State private var isSaving = false
    @State private var passwordInput: String = ""
    
    @State private var subscriptionTokens: [SubscriptionToken] = []
    
    init(serverID: String? = nil, isEditing: Bool = false) {
        self.serverID = serverID
        self.isEditing = isEditing
        
        let defaultConfig = ServerConfig(
            name: "",
            protocolType: .webdav,
            url: "",
            username: "",
            password: "",
            mountPath: "",
            timeout: 30,
            maxRetries: 3,
            retryInterval: 5,
            autoMount: false,
            mountOptions: [:],
            protocolConfig: ["https": AnyCodable(true)],
            isEnabled: true
        )
        _config = State(initialValue: defaultConfig)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(isEditing ? "编辑连接" : "新建连接")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
            
            // 表单
            ScrollView {
                Form {
                    Section {
                        HStack {
                            Text("名称")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            LeftAlignedTextField(text: $config.name, placeholder: "例如: Yiqipro Cloud")
                        }
                        .frame(height: 32)
                        
                        HStack {
                            Text("协议")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $config.protocolType) {
                                ForEach(ProtocolType.allCases, id: \.self) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(isEditing)
                            Spacer()
                        }
                        .frame(height: 32)
                    }
                    
                    Section("连接设置") {
                        HStack {
                            Text("地址")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            LeftAlignedTextField(text: $config.url, placeholder: "例如: webdav.yiqipro.com")
                            PortInputView(config: $config)
                                .frame(width: 80)
                        }
                        .frame(height: 32)
                        
                        HStack {
                            Text("用户")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            LeftAlignedTextField(
                                text: Binding(
                                    get: { config.username ?? "" },
                                    set: { config.username = $0.isEmpty ? nil : $0 }
                                ),
                                placeholder: "例如: admin"
                            )
                        }
                        .frame(height: 32)
                        
                        // ✅ 密码字段
                        HStack {
                            Text("密码")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            HStack(spacing: 4) {
                                if showPassword {
                                    LeftAlignedTextField(
                                        text: $passwordInput,
                                        placeholder: "请输入密码"
                                    )
                                    .onChange(of: passwordInput) { _, newValue in
                                        config.password = newValue.isEmpty ? nil : newValue
                                    }
                                } else {
                                    LeftAlignedSecureField(
                                        text: $passwordInput,
                                        placeholder: "请输入密码"
                                    )
                                    .onChange(of: passwordInput) { _, newValue in
                                        config.password = newValue.isEmpty ? nil : newValue
                                    }
                                }
                                Button(action: {
                                    showPassword.toggle()
                                    passwordInput = config.password ?? ""
                                }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(height: 32)
                        
                        HStack {
                            Text("远程路径")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            LeftAlignedTextField(
                                text: Binding(
                                    get: { config.mountPath ?? "" },
                                    set: { config.mountPath = $0.isEmpty ? nil : $0 }
                                ),
                                placeholder: "（可选）"
                            )
                        }
                        .frame(height: 32)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Toggle("启用 HTTPS", isOn: Binding(
                            get: { config.getProtocolConfig(key: "https", defaultValue: true) },
                            set: { config.setProtocolConfig(key: "https", value: $0) }
                        ))
                        
                        Toggle("允许自签名证书", isOn: Binding(
                            get: { config.getProtocolConfig(key: "selfSigned", defaultValue: false) },
                            set: { config.setProtocolConfig(key: "selfSigned", value: $0) }
                        ))
                        .disabled(!config.getProtocolConfig(key: "https", defaultValue: true))
                        .opacity(config.getProtocolConfig(key: "https", defaultValue: true) ? 1.0 : 0.5)
                    }
                    
                    Section("挂载设置") {
                        Toggle("启动时自动挂载", isOn: $config.autoMount)
                        
                        if config.autoMount {
                            HStack {
                                Text("挂载延迟")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .frame(width: 80, alignment: .leading)
                                Picker("", selection: $config.retryInterval) {
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
                                Spacer()
                            }
                            .frame(height: 32)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: config.autoMount)
                        }
                    }
                    
                    Section("高级设置") {
                        HStack {
                            Text("超时 (秒)")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $config.timeout) {
                                Text("10").tag(10)
                                Text("15").tag(15)
                                Text("30").tag(30)
                                Text("60").tag(60)
                                Text("120").tag(120)
                            }
                            .pickerStyle(.menu)
                            Spacer()
                        }
                        .frame(height: 32)
                        
                        HStack {
                            Text("重试次数")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $config.maxRetries) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("3").tag(3)
                                Text("5").tag(5)
                            }
                            .pickerStyle(.menu)
                            Spacer()
                        }
                        .frame(height: 32)
                    }
                }
                .formStyle(.grouped)
                .padding(.horizontal, 0)
            }
            
            if let error = connectionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("重试") {
                        connectionError = nil
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.05))
            }
            
            Divider()

            // 底部按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(CapsuleButtonStyle(color: .secondary))
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "network")
                                .font(.system(size: 13))
                        }
                        Text("测试连接")
                    }
                }
                .buttonStyle(CapsuleButtonStyle(color: .green))
                .disabled(isConnecting || config.name.isEmpty || config.url.isEmpty)
                
                Button(isEditing ? "保存" : "保存并挂载") {
                    print("🔥🔥🔥 保存按钮被点击！")
                    saveConnection()
                }
                .buttonStyle(CapsuleButtonStyle(color: .accentColor, isProminent: true))
                .disabled(isSaving || isConnecting || config.name.isEmpty || config.url.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 660)
        .sheet(isPresented: $showTestResult) {
            NetworkTestResultView(
                result: testResult,
                isLoading: isConnecting
            )
        }
        .onAppear {
            passwordInput = config.password ?? ""
            setupEventListeners()
            if isEditing, let id = serverID {
                EventBus.shared.publish(LoadServerConfigRequest(serverID: id))
            }
        }
        .onDisappear {
            subscriptionTokens.forEach { $0.unsubscribe() }
            subscriptionTokens.removeAll()
        }
    }
    
    // MARK: - 设置事件监听
    private func setupEventListeners() {
        // 监听加载完成
        let loadToken = EventBus.shared.subscribe(
            to: ServerConfigLoaded.self,
            priority: .high
        ) { event in
            guard event.serverID == self.serverID else { return }
            DispatchQueue.main.async {
                self.config = event.config
                self.passwordInput = self.config.password ?? ""
                let (host, port) = self.extractHostAndPort(from: self.config.url)
                if !host.isEmpty && host != self.config.url {
                    self.config.url = host
                }
                if let port = port {
                    self.config.setProtocolConfig(key: "port", value: port)
                }
            }
        }
        subscriptionTokens.append(loadToken)
        
        // ✅ 监听保存结果
        let saveToken = EventBus.shared.subscribe(
            to: ServerConfigSaved.self,
            priority: .high
        ) { event in
            DispatchQueue.main.async {
                print("📋 [AddServerView] 收到 ServerConfigSaved: success=\(event.success), serverID=\(event.serverID)")
                self.isSaving = false
                if event.success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.dismiss()
                    }
                } else {
                    self.connectionError = event.error ?? "保存失败"
                }
            }
        }
        subscriptionTokens.append(saveToken)
        
        // 监听测试结果
        let testToken = EventBus.shared.subscribe(
            to: TestConnectionResultEvent.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                self.isConnecting = false
                self.testResult = event.result
                self.showTestResult = true
            }
        }
        subscriptionTokens.append(testToken)
    }
    
    // MARK: - 保存连接
    private func saveConnection() {
        print("📋 [AddServerView] saveConnection 被调用")
        print("  - serverID: \(serverID ?? "nil")")
        print("  - isEditing: \(isEditing)")
        print("  - config.name: \(config.name)")
        print("  - config.url: \(config.url)")
        print("  - config.protocolType: \(config.protocolType)")
        
        isSaving = true
        connectionError = nil
        
        var normalizedConfig = config
        
        // 解析并标准化 URL
        let (host, extractedPort) = extractHostAndPort(from: normalizedConfig.url)
        if !host.isEmpty {
            normalizedConfig.url = host
        }

        // 先处理提取出来的端口
        if let extractedPort = extractedPort {
            normalizedConfig.setProtocolConfig(key: "port", value: extractedPort)
        }

        // 获取当前已设置端口（非可选Int）
        let currentPort = normalizedConfig.getPort()
        // 判断：端口为0/无效值时填充默认端口（根据WebDAV常规逻辑）
        if currentPort <= 0 {
            normalizedConfig.setProtocolConfig(key: "port", value: normalizedConfig.protocolType.defaultPort)
        }

        // 同步回原始 config
        config.url = normalizedConfig.url
        if let extractedPort = extractedPort {
            config.setProtocolConfig(key: "port", value: extractedPort)
        } else {
            // 直接读取已经补全端口的 normalizedConfig
            config.setProtocolConfig(key: "port", value: normalizedConfig.getPort())
        }
        
        // ✅ 发送保存请求
        EventBus.shared.publish(
            SaveServerConfigRequest(
                serverID: serverID,
                isEditing: isEditing,
                config: normalizedConfig
            )
        )
        print("📋 [AddServerView] 已发送 SaveServerConfigRequest")
    }
    
    // MARK: - 测试连接
    private func testConnection() {
        guard !config.url.isEmpty else {
            connectionError = "请输入地址"
            return
        }
        
        isConnecting = true
        connectionError = nil
        
        EventBus.shared.publish(
            TestConnectionRequest(config: config)
        )
    }
    
    // MARK: - 辅助方法
    private func extractHostAndPort(from urlString: String) -> (host: String, port: Int?) {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let prefixes = ["https://", "http://", "ftp://", "sftp://", "smb://", "nfs://"]
        for prefix in prefixes {
            if raw.hasPrefix(prefix) {
                raw = String(raw.dropFirst(prefix.count))
                break
            }
        }
        
        if raw.hasPrefix("[") {
            if let closeBracketIndex = raw.firstIndex(of: "]") {
                let ipv6Part = String(raw[...closeBracketIndex])
                let remaining = String(raw[raw.index(after: closeBracketIndex)...])
                if remaining.hasPrefix(":") {
                    let portString = String(remaining.dropFirst())
                    if let p = Int(portString), p > 0, p < 65536 {
                        return (ipv6Part, p)
                    }
                }
                return (ipv6Part, nil)
            }
        }
        
        if let colonIndex = raw.lastIndex(of: ":") {
            let prefix = String(raw[..<colonIndex])
            if !prefix.contains(":") {
                let portString = String(raw[raw.index(after: colonIndex)...])
                if let p = Int(portString), p > 0, p < 65536 {
                    return (prefix, p)
                }
            }
        }
        
        return (raw, nil)
    }
}

#Preview {
    AddServerView()
}
