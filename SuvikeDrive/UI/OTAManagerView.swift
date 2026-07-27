//
//  OTAManagerView.swift
//  SuvikeDrive
//
//  功能: OTA 更新 UI 视图
//

import SwiftUI
import Combine

// ⚠️ 注意：UpdateFlowState 在 DownloadProgressView.swift 中定义，这里不要重复定义

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
        
        let completeToken = EventBus.shared.subscribe(
            to: OTADownloadComplete.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateStatusText = "下载完成"
                self.updateProgress = 1
                self.updateFlowState = .downloadComplete
            }
        }
        eventTokens.append(completeToken)
        
        let installStartedToken = EventBus.shared.subscribe(
            to: OTAInstallStarted.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateFlowState = .installing
                self.updateStatusText = "正在安装更新..."
            }
        }
        eventTokens.append(installStartedToken)
        
        let installCompleteToken = EventBus.shared.subscribe(
            to: OTAInstallComplete.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateStatusText = "安装完成，即将重启..."
                self.updateFlowState = .downloadComplete
            }
        }
        eventTokens.append(installCompleteToken)
        
        let installFailedToken = EventBus.shared.subscribe(
            to: OTAInstallFailed.self,
            priority: .medium
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateFlowState = .error
                self.updateStatusText = "安装失败"
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
    
    func startDownload() {
        guard OTAManager.shared.getUpdateInfo() != nil else {
            updateFlowState = .error
            updateStatusText = "下载失败"
            updateError = "未找到更新信息"
            return
        }
        
        updateFlowState = .downloading
        updateProgress = 0
        updateStatusText = "正在下载更新..."
        
        OTAManager.shared.downloadUpdate(progressHandler: { _ in
            // 进度通过 EventBus 的 OTADownloadProgress 处理
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    break
                case .failure(let error):
                    self.updateFlowState = .error
                    self.updateStatusText = "下载失败"
                    self.updateError = error.localizedDescription
                }
            }
        }
    }
    
    func performInstall() {
        guard let updateInfo = OTAManager.shared.getUpdateInfo() else {
            updateFlowState = .error
            updateStatusText = "安装失败"
            updateError = "未找到更新信息"
            return
        }
        
        let packagePath = OTAManager.shared.getUpdatePackagePath(for: updateInfo.version)
        
        guard FileManager.default.fileExists(atPath: packagePath.path) else {
            updateFlowState = .error
            updateStatusText = "更新包不存在"
            updateError = "更新包已损坏或丢失，请重新下载"
            return
        }
        
        updateFlowState = .installing
        updateStatusText = "正在安装更新..."
        
        OTAManager.shared.installUpdate(updatePackage: packagePath) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    break
                case .failure(let error):
                    self.updateFlowState = .error
                    self.updateStatusText = "安装失败"
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
