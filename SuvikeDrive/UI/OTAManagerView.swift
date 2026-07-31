//
//  OTAManagerView.swift
//  SuvikeDrive
//
//  功能: OTA 更新 UI 视图
//

import SwiftUI
import Combine

// MARK: - OTA 管理器 ViewModel
class OTAManagerViewModel: ObservableObject {
    @Published var showingUpdateWindow = false
    @Published var updateFlowState: UpdateFlowState = .checking
    @Published var updateProgress: Double = 0
    @Published var updateStatusText: String = "正在检查更新..."
    @Published var updateVersion: String? = nil
    @Published var updateReleaseNotes: String? = nil
    @Published var updateSize: String = "0 KB"
    @Published var isMandatory: Bool = false
    @Published var updateError: String? = nil
    
    private var eventTokens: [SubscriptionToken] = []
    
    init() {
        setupEventBusListeners()
    }
    
    deinit {
        eventTokens.forEach { $0.unsubscribe() }
        eventTokens.removeAll()
    }
    
    // MARK: - EventBus 监听
    private func setupEventBusListeners() {
        // 1. 监听更新可用事件（需要下载）
        let availableToken = EventBus.shared.subscribe(
            to: OTAUpdateAvailable.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateVersion = event.version
                self.updateReleaseNotes = event.releaseNotes
                self.updateSize = ByteCountFormatter().string(fromByteCount: event.size)
                self.updateFlowState = .showLog
                self.updateStatusText = "发现新版本 \(event.version)"
                self.showingUpdateWindow = true
            }
        }
        eventTokens.append(availableToken)
        
        // 2. 监听安装包已就绪事件（已有完整安装包）
        let packageReadyToken = EventBus.shared.subscribe(
            to: OTAPackageReady.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let updateInfo = OTAManager.shared.getUpdateInfo() {
                    self.updateVersion = updateInfo.version
                    self.updateReleaseNotes = updateInfo.releaseNotes
                    self.updateSize = ByteCountFormatter().string(fromByteCount: updateInfo.size)
                    self.isMandatory = updateInfo.isMandatory
                }
                self.updateFlowState = .downloadComplete
                self.updateStatusText = "安装包已准备就绪，点击安装"
                self.updateProgress = 1.0
                self.showingUpdateWindow = true
            }
        }
        eventTokens.append(packageReadyToken)
        
        // 3. 监听下载进度
        let progressToken = EventBus.shared.subscribe(
            to: OTADownloadProgress.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateProgress = event.progress
                self.updateFlowState = .downloading
                if event.progress < 0.3 {
                    self.updateStatusText = "正在下载..."
                } else if event.progress < 0.6 {
                    self.updateStatusText = "下载中，请稍候..."
                } else if event.progress < 0.9 {
                    self.updateStatusText = "即将完成..."
                } else {
                    self.updateStatusText = "正在验证下载..."
                }
            }
        }
        eventTokens.append(progressToken)
        
        // 4. 监听下载完成
        let completeToken = EventBus.shared.subscribe(
            to: OTADownloadComplete.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // ✅ 强制更新状态
                self.updateStatusText = "下载完成，点击安装"
                self.updateProgress = 1.0
                self.updateFlowState = .downloadComplete
            }
        }
        eventTokens.append(completeToken)
        
        // 5. 监听安装开始
        let installStartedToken = EventBus.shared.subscribe(
            to: OTAInstallStarted.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateFlowState = .installing
                self.updateStatusText = "⏳ 正在安装更新..."
            }
        }
        eventTokens.append(installStartedToken)
        
        // 6. 监听安装完成
        let installCompleteToken = EventBus.shared.subscribe(
            to: OTAInstallComplete.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateStatusText = "✅ 更新成功！即将重启..."
                self.updateFlowState = .downloadComplete
                self.updateProgress = 1.0
            }
        }
        eventTokens.append(installCompleteToken)
        
        // 7. 监听安装失败
        let installFailedToken = EventBus.shared.subscribe(
            to: OTAInstallFailed.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateFlowState = .error
                self.updateStatusText = "❌ 安装失败"
                self.updateError = event.error
            }
        }
        eventTokens.append(installFailedToken)
    }
    
    // MARK: - 公开方法
    func checkForUpdate() {
        updateFlowState = .checking
        updateStatusText = "正在检查更新..."
        updateProgress = 0
        updateError = nil
        showingUpdateWindow = true
        
        OTAManager.shared.checkForUpdates { [weak self] hasUpdate in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !hasUpdate {
                    self.updateFlowState = .noUpdate
                    self.updateStatusText = "已是最新版本"
                    self.updateProgress = 1
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.showingUpdateWindow = false
                    }
                }
            }
        }
    }
    
    // MARK: - 下载更新
    func startDownload() {
        guard let updateInfo = OTAManager.shared.getUpdateInfo() else {
            updateFlowState = .error
            updateStatusText = "❌ 下载失败"
            updateError = "未找到更新信息"
            return
        }
        
        let packagePath = OTAManager.shared.getUpdatePackagePath(for: updateInfo.version)
        
        // ✅ 检查本地是否有安装包
        if FileManager.default.fileExists(atPath: packagePath.path) {
            let isValid = OTAManager.shared.verifyUpdatePackage(at: packagePath, with: updateInfo)
            if isValid {
                updateFlowState = .downloadComplete
                updateStatusText = "安装包已准备就绪，点击安装"
                updateProgress = 1.0
                return
            } else {
                try? FileManager.default.removeItem(at: packagePath)
                updateStatusText = "安装包已损坏，重新下载..."
            }
        }
        
        // 没有完整安装包，开始下载
        updateFlowState = .downloading
        updateProgress = 0
        updateStatusText = "正在下载更新..."
        
        OTAManager.shared.downloadUpdate(progressHandler: { _ in
            // 进度通过 EventBus 的 OTADownloadProgress 处理
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let url):
                    if OTAManager.shared.verifyUpdatePackage(at: url, with: updateInfo) {
                        // ✅ 直接更新状态，确保 UI 刷新
                        self.updateFlowState = .downloadComplete
                        self.updateStatusText = "下载完成，点击安装"
                        self.updateProgress = 1.0
                    } else {
                        try? FileManager.default.removeItem(at: url)
                        self.updateFlowState = .error
                        self.updateStatusText = "❌ 下载失败"
                        self.updateError = "安装包校验失败，请重试"
                    }
                case .failure(let error):
                    self.updateFlowState = .error
                    self.updateStatusText = "❌ 下载失败"
                    self.updateError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - 安装更新
    func performInstall() {
        guard let updateInfo = OTAManager.shared.getUpdateInfo() else {
            updateFlowState = .error
            updateStatusText = "❌ 安装失败"
            updateError = "未找到更新信息"
            return
        }
        
        let packagePath = OTAManager.shared.getUpdatePackagePath(for: updateInfo.version)
        
        guard FileManager.default.fileExists(atPath: packagePath.path) else {
            updateFlowState = .error
            updateStatusText = "❌ 安装失败"
            updateError = "更新包不存在，请重新下载"
            return
        }
        
        let isValid = OTAManager.shared.verifyUpdatePackage(at: packagePath, with: updateInfo)
        if !isValid {
            try? FileManager.default.removeItem(at: packagePath)
            updateFlowState = .error
            updateStatusText = "❌ 安装失败"
            updateError = "更新包已损坏，请重新下载"
            return
        }
        
        updateFlowState = .installing
        updateStatusText = "⏳ 正在安装更新..."
        
        OTAManager.shared.installUpdate(updatePackage: packagePath) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.updateFlowState = .downloadComplete
                    self.updateStatusText = "✅ 更新成功！即将重启..."
                    self.updateProgress = 1.0
                case .failure(let error):
                    self.updateFlowState = .error
                    self.updateStatusText = "❌ 安装失败"
                    self.updateError = error.localizedDescription
                }
            }
        }
    }
    
    func cancelUpdate() {
        OTAManager.shared.cancelDownload()
        showingUpdateWindow = false
    }
}

// MARK: - OTA 更新视图
struct OTAManagerView: View {
    @ObservedObject var viewModel: OTAManagerViewModel
    
    var body: some View {
        EmptyView()
            .sheet(isPresented: $viewModel.showingUpdateWindow) {
                DownloadProgressView(
                    state: viewModel.updateFlowState,
                    progress: viewModel.updateProgress,
                    status: viewModel.updateStatusText,
                    version: viewModel.updateVersion,
                    releaseNotes: viewModel.updateReleaseNotes,
                    size: viewModel.updateSize,
                    isMandatory: viewModel.isMandatory,
                    errorMessage: viewModel.updateError,
                    onDownload: {
                        viewModel.startDownload()
                    },
                    onInstall: {
                        viewModel.performInstall()
                    },
                    onCancel: {
                        viewModel.cancelUpdate()
                    },
                    onDismiss: {
                        viewModel.showingUpdateWindow = false
                    },
                    onRetry: {
                        viewModel.checkForUpdate()
                    }
                )
            }
    }
    
    func checkForUpdate() {
        viewModel.checkForUpdate()
    }
}
