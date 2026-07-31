//
//  FileBrowserView.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：浏览器顶层容器视图，组装路径栏、目录树、文件列表、骨架屏、底部工具栏
//        对外暴露的主入口View，外部直接实例化使用
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @State private var sidebarWidth: CGFloat = 200
    @State private var isSidebarVisible: Bool = true
    @State private var isResizing: Bool = false
    @State private var selectedFile: FileInfo?
    @State private var availableServers: [ServerConfig] = []
    @State private var selectedServerID: String?
    @State private var eventTokens: [SubscriptionToken] = []
    @State private var isMounting: Bool = false
    @State private var isDropTargeted: Bool = false
    
    private let minSidebarWidth: CGFloat = 120
    private let maxSidebarWidth: CGFloat = 400
    
    private var isServerError: Bool {
        return viewModel.serverID.isEmpty ||
               viewModel.errorMessage?.contains("请选择服务器") == true ||
               viewModel.errorMessage?.contains("instanceNotFound") == true ||
               viewModel.errorMessage?.contains("未挂载") == true ||
               viewModel.errorMessage?.contains("未找到服务器配置") == true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            FileBrowserToolbar(viewModel: viewModel)
                .frame(height: 44)
            
            // 路径导航栏 + 服务器选择
            pathBarWithServer
            
            // 中间：双栏布局
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // 左侧：目录树
                    if isSidebarVisible {
                        Group {
                            switch viewModel.loadingState {
                            case .loading:
                                DirectoryTreeSkeletonView()
                            default:
                                FileDirectoryTreeView(viewModel: viewModel)
                            }
                        }
                        .frame(width: sidebarWidth)
                        .background(Color(.windowBackgroundColor))
                        .overlay(
                            Rectangle()
                                .fill(isResizing ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: isResizing ? 2 : 1)
                                .padding(.vertical, 0)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            isResizing = true
                                            let newWidth = sidebarWidth + value.translation.width
                                            sidebarWidth = min(max(newWidth, minSidebarWidth), maxSidebarWidth)
                                        }
                                        .onEnded { _ in
                                            isResizing = false
                                            UserDefaults.standard.set(sidebarWidth, forKey: "fb_sidebarWidth")
                                        }
                                )
                                .cursor(.resizeLeftRight),
                            alignment: .trailing
                        )
                    }
                    
                    // 右侧：文件列表 + 底部详情面板
                    VStack(spacing: 0) {
                        // 文件列表
                        ZStack {
                            switch viewModel.loadingState {
                            case .loading:
                                FileListSkeletonView()
                            case .failure(let error):
                                if isServerError {
                                    VStack(spacing: 16) {
                                        Image(systemName: "server.rack")
                                            .font(.system(size: 40))
                                            .foregroundColor(.secondary)
                                        Text("请选择服务器")
                                            .font(.headline)
                                        Text("从上方下拉菜单中选择已挂载的服务器")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if isMounting {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("正在挂载...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                } else {
                                    VStack(spacing: 16) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.system(size: 40))
                                            .foregroundColor(.orange)
                                        Text("加载失败")
                                            .font(.headline)
                                        Text(error.localizedDescription)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                        Button("重试") {
                                            viewModel.reloadCurrentDirectory()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding()
                                    .background(Color(.windowBackgroundColor).opacity(0.9))
                                    .cornerRadius(12)
                                }
                            default:
                                FileContentView(
                                    files: viewModel.items,
                                    viewModel: viewModel,
                                    onFileSelected: { file in
                                        selectedFile = file
                                    }
                                )
                                .overlay {
                                    if viewModel.items.isEmpty && viewModel.loadingState != .loading && !viewModel.serverID.isEmpty {
                                        VStack(spacing: 12) {
                                            Image(systemName: "folder")
                                                .font(.system(size: 50))
                                                .foregroundColor(.gray.opacity(0.5))
                                            Text("此目录为空")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // 拖拽上传
                        .onDrop(
                            of: [.fileURL],
                            isTargeted: $isDropTargeted
                        ) { providers in
                            handleDrop(providers: providers)
                            return true
                        }
                        // ✅ 换成 no-corner-radius 的边框，防止裁切原生列表
                        .overlay(
                            Rectangle()
                                .stroke(
                                    isDropTargeted ? Color.accentColor : Color.clear,
                                    lineWidth: isDropTargeted ? 2 : 0
                                )
                                .padding(4)
                                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
                        )
                        
                        // 底部详情面板
                        Divider()
                        if let file = selectedFile, !file.isDirectory {
                            FileDetailPanelView(file: file, viewModel: viewModel)
                                .frame(height: 50)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let folder = selectedFile, folder.isDirectory {
                            let subCount = viewModel.items.filter { $0.isDirectory }.count
                            FolderDetailPanelView(folder: folder, itemCount: subCount)
                                .frame(height: 50)
                        } else {
                            Rectangle()
                                .fill(Color(.windowBackgroundColor))
                                .frame(height: 50)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            setupEventListeners()
            loadServers()
            
            let savedWidth = UserDefaults.standard.object(forKey: "fb_sidebarWidth") as? CGFloat
            sidebarWidth = savedWidth ?? 200
            sidebarWidth = min(max(sidebarWidth, minSidebarWidth), maxSidebarWidth)
            
            if !viewModel.serverID.isEmpty {
                viewModel.reloadCurrentDirectory()
                viewModel.preloadRootDirectory()
            }
        }
        .onDisappear {
            eventTokens.forEach { $0.unsubscribe() }
            eventTokens.removeAll()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .help("切换目录树")
            }
        }
        // ✅ 右下角进度条
        .overlay(alignment: .bottomTrailing) {
            if let activeTask = viewModel.activeTransferTask {
                TransferProgressView(
                    fileName: activeTask.fileName,
                    progress: activeTask.progress,
                    isUploading: activeTask.isUpload,
                    speed: activeTask.speed,
                    onCancel: {
                        if activeTask.isUpload {
                            viewModel.cancelUpload(filePath: activeTask.filePath)
                        } else {
                            viewModel.cancelDownload(filePath: activeTask.filePath)
                        }
                    }
                )
                .padding(.trailing, 16)
                .padding(.bottom, 80)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.3), value: viewModel.activeTransferTask != nil)
            }
        }
    }
    
    // MARK: - 拖拽上传处理
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard !viewModel.serverID.isEmpty else {
            viewModel.errorMessage = "请先选择服务器"
            return
        }
        
        print("📋 [FileBrowserView] 拖拽文件到窗口，处理 \(providers.count) 个项目")
        
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error = error {
                    print("❌ [FileBrowserView] 加载拖拽项目失败: \(error)")
                    return
                }
                
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                
                DispatchQueue.main.async {
                    self.handleUploadURL(url)
                }
            }
        }
    }
    
    private func handleUploadURL(_ url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        print("📋 [FileBrowserView] 上传: \(url.lastPathComponent) (目录: \(isDirectory.boolValue))")
        
        if isDirectory.boolValue {
            viewModel.uploadFolder(url: url, to: viewModel.currentPath)
        } else {
            viewModel.uploadFile(localPath: url, remotePath: viewModel.currentPath)
        }
    }
    
    // MARK: - 路径导航栏 + 服务器选择
    @ViewBuilder
    private var pathBarWithServer: some View {
        HStack(spacing: 0) {
            // 服务器选择器
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $selectedServerID) {
                    Text("选择服务器").tag(String?.none)
                    ForEach(availableServers, id: \.id) { server in
                        Text(server.name).tag(server.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .labelsHidden()
                .onChange(of: selectedServerID) { _, newValue in
                    if let serverID = newValue {
                        switchServer(to: serverID)
                    }
                }
            }
            .padding(.leading, 8)
            
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 8)
            
            // 路径导航
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button("根目录") {
                        viewModel.navigateTo(path: "/")
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.plain)
                    .foregroundColor(viewModel.currentPath == "/" ? .primary : .secondary)
                    
                    let segments = viewModel.currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
                    ForEach(segments.indices, id: \.self) { idx in
                        Text("›")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        let fullPath = "/" + segments[0...idx].joined(separator: "/")
                        Button(segments[idx]) {
                            viewModel.navigateTo(path: fullPath)
                        }
                        .font(.system(size: 13))
                        .buttonStyle(.plain)
                        .foregroundColor(idx == segments.count - 1 ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
            }
            
            Spacer()
            
            // 刷新按钮
            Button(action: {
                viewModel.refreshCache()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .disabled(selectedServerID == nil)
            .padding(.trailing, 8)
        }
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .frame(height: 34)
        .overlay(
            Divider()
                .frame(height: 1)
                .background(Color.gray.opacity(0.15)),
            alignment: .bottom
        )
    }
    
    // MARK: - 加载服务器列表
    private func loadServers() {
        let servers = ConfigurationManager.shared.getServers()
        availableServers = servers
        
        let mountedList = MountManager.shared.getMountedServers()
        if selectedServerID == nil {
            if let firstMounted = mountedList.first, servers.contains(where: { $0.id == firstMounted }) {
                selectedServerID = firstMounted
                switchServer(to: firstMounted)
            } else if servers.count == 1 {
                selectedServerID = servers.first?.id
                if let id = servers.first?.id {
                    switchServer(to: id)
                }
            }
        }
    }
    
    // MARK: - 切换服务器（自动挂载）
    private func switchServer(to serverID: String) {
        let mountedList = MountManager.shared.getMountedServers()
        
        if mountedList.contains(serverID) {
            isMounting = false
            viewModel.switchServer(to: serverID)
            if let server = availableServers.first(where: { $0.id == serverID }) {
                EventBus.shared.publish(ServerSwitched(serverID: serverID, serverName: server.name))
            }
        } else {
            guard let config = availableServers.first(where: { $0.id == serverID }) else {
                print("❌ [FileBrowserView] 未找到服务器配置: \(serverID)")
                viewModel.errorMessage = "未找到服务器配置"
                viewModel.loadingState = .failure(NSError(
                    domain: "FileBrowserView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "未找到服务器配置"]
                ))
                return
            }
            
            isMounting = true
            print("📋 [FileBrowserView] 自动挂载服务器: \(serverID)")
            
            MountManager.shared.mount(serverID: serverID, config: config) { result in
                DispatchQueue.main.async {
                    self.isMounting = false
                    switch result {
                    case .success:
                        print("✅ [FileBrowserView] 自动挂载成功: \(serverID)")
                        self.viewModel.switchServer(to: serverID)
                        if let server = self.availableServers.first(where: { $0.id == serverID }) {
                            EventBus.shared.publish(ServerSwitched(serverID: serverID, serverName: server.name))
                        }
                    case .failure(let error):
                        print("❌ [FileBrowserView] 自动挂载失败: \(error)")
                        self.viewModel.errorMessage = "挂载失败: \(error.localizedDescription)"
                        self.viewModel.loadingState = .failure(error)
                    }
                }
            }
        }
    }
    
    // MARK: - 事件监听
    private func setupEventListeners() {
        let listToken = EventBus.shared.subscribe(to: ServerListUpdated.self, priority: .medium) { _ in
            DispatchQueue.main.async {
                self.loadServers()
            }
        }
        eventTokens.append(listToken)
        
        let mountToken = EventBus.shared.subscribe(to: MountCompleted.self, priority: .low) { _ in
            DispatchQueue.main.async {
                self.loadServers()
            }
        }
        eventTokens.append(mountToken)
        
        let unmountToken = EventBus.shared.subscribe(to: UnmountCompleted.self, priority: .low) { _ in
            DispatchQueue.main.async {
                self.loadServers()
            }
        }
        eventTokens.append(unmountToken)
        
        // ✅ 监听服务器切换完成事件
        let switchToken = EventBus.shared.subscribe(to: ServerSwitched.self, priority: .low) { event in
            DispatchQueue.main.async {
                print("📋 [FileBrowserView] 服务器切换完成: \(event.serverName) (\(event.serverID))")
                self.selectedServerID = event.serverID
            }
        }
        eventTokens.append(switchToken)
    }
}

// MARK: - Preview
#Preview {
    let cacheManager = CacheManager.shared
    let eventBus = EventBus.shared
    let viewModel = FileBrowserViewModel(
        serverID: "preview_server",
        cacheManager: cacheManager,
        eventBus: eventBus
    )
    FileBrowserView(viewModel: viewModel)
        .frame(width: 800, height: 600)
}
