//
//  FileBrowserViewModel.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：文件浏览器核心业务逻辑、目录加载、路径导航、文件排序、缓存读写、事件总线绑定
//        依赖 WebDAVModule 拉取远端目录，CacheManager 实现目录列表LRU内存缓存
//        所有文件实体统一使用 FileInfo，彻底移除旧 FileItem 类型
//  Author: Andything
//  Date: 2026-07-29
//

import Foundation
import Combine
import SwiftUI

// MARK: 排序枚举
enum SortOrder: String, CaseIterable {
    case nameAsc
    case nameDesc
    case sizeAsc
    case sizeDesc
    case dateAsc
    case dateDesc
}

// MARK: - 同步状态枚举
enum SyncState: String {
    case synced = "synced"
    case downloading = "downloading"
    case uploading = "uploading"
    case notSynced = "notSynced"
    case error = "error"
    case unknown = "unknown"
    
    var iconName: String {
        switch self {
        case .synced: return "checkmark.icloud.fill"
        case .downloading: return "icloud.and.arrow.down"
        case .uploading: return "icloud.and.arrow.up"
        case .notSynced: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        case .unknown: return "icloud"
        }
    }
    
    var color: Color {
        switch self {
        case .synced: return .green
        case .downloading: return .blue
        case .uploading: return .orange
        case .notSynced: return .gray
        case .error: return .red
        case .unknown: return .secondary
        }
    }
    
    var tooltip: String {
        switch self {
        case .synced: return "已同步"
        case .downloading: return "下载中..."
        case .uploading: return "上传中..."
        case .notSynced: return "未同步"
        case .error: return "同步错误"
        case .unknown: return "未知状态"
        }
    }
}

// MARK: - 浏览器加载状态枚举
enum BrowserLoadingState: Equatable {
    case idle
    case loading
    case success
    case failure(Error)
    
    static func == (lhs: BrowserLoadingState, rhs: BrowserLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.success, .success):
            return true
        case (.failure(let e1), .failure(let e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - ViewModel
final class FileBrowserViewModel: ObservableObject {
    // UI对外状态
    @Published var currentPath: String = "/"
    @Published var items: [FileInfo] = []
    @Published var loadingState: BrowserLoadingState = .idle
    @Published var errorMessage: String?
    @Published var sortOrder: SortOrder = .nameAsc
    @Published var isLoading: Bool = false
    
    // 同步状态字典：文件路径 -> 同步状态
    @Published var syncStates: [String: SyncState] = [:]
    
    // 正在下载/上传的文件路径集合
    @Published var downloadingFiles: Set<String> = []
    @Published var uploadingFiles: Set<String> = []
    
    // ✅ 传输任务（用于右下角进度条）
    @Published var activeTransferTask: TransferTask?

    private let cacheManager: CacheManager
    private let eventBus: EventBus
    var serverID: String

    // Combine订阅容器
    private var cancellables = Set<AnyCancellable>()
    
    // 事件总线订阅令牌
    private var refreshEventToken: SubscriptionToken?
    
    // MARK: - 目录树相关
    @Published var treeNodes: [TreeNode] = []
    @Published var selectedTreeNode: TreeNode?
    
    // 全局目录缓存
    private var directoryCache: [String: [FileInfo]] = [:]

    // MARK: - Init
    init(serverID: String,
         cacheManager: CacheManager = CacheManager.shared,
         eventBus: EventBus = EventBus.shared) {
        self.serverID = serverID
        self.cacheManager = cacheManager
        self.eventBus = eventBus
        bindEventBus()
        setupSyncStateListeners()
        setupServerListener()
    }
    
    deinit {
        refreshEventToken = nil
    }

    // MARK: 事件总线监听
    private func bindEventBus() {
        let token = eventBus.subscribe(to: FileSystemRefreshEvent.self) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.reloadCurrentDirectory()
            }
        }
        self.refreshEventToken = token
    }
    
    // MARK: - 同步状态监听
    private func setupSyncStateListeners() {
        let downloadToken = eventBus.subscribe(to: FileDownloadProgress.self) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let filePath = event.filePath
                self.downloadingFiles.insert(filePath)
                self.syncStates[filePath] = SyncState.downloading
                self.objectWillChange.send()
            }
        }
        cancellables.insert(AnyCancellable { downloadToken.unsubscribe() })
        
        let downloadCompleteToken = eventBus.subscribe(to: FileDownloadComplete.self) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let filePath = event.filePath
                self.downloadingFiles.remove(filePath)
                if event.success {
                    self.syncStates[filePath] = SyncState.synced
                } else {
                    self.syncStates[filePath] = SyncState.error
                }
                self.objectWillChange.send()
            }
        }
        cancellables.insert(AnyCancellable { downloadCompleteToken.unsubscribe() })
        
        let uploadToken = eventBus.subscribe(to: FileUploadProgress.self) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let filePath = event.filePath
                self.uploadingFiles.insert(filePath)
                self.syncStates[filePath] = SyncState.uploading
                self.objectWillChange.send()
            }
        }
        cancellables.insert(AnyCancellable { uploadToken.unsubscribe() })
        
        let uploadCompleteToken = eventBus.subscribe(to: FileUploadComplete.self) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let filePath = event.filePath
                self.uploadingFiles.remove(filePath)
                if event.success {
                    self.syncStates[filePath] = SyncState.synced
                } else {
                    self.syncStates[filePath] = SyncState.error
                }
                self.objectWillChange.send()
            }
        }
        cancellables.insert(AnyCancellable { uploadCompleteToken.unsubscribe() })
    }

    // MARK: - 服务器切换监听
    private func setupServerListener() {
        let token = eventBus.subscribe(to: ServerSwitchRequested.self) { [weak self] event in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.switchServer(to: event.serverID)
            }
        }
        cancellables.insert(AnyCancellable { token.unsubscribe() })
    }
    
    // MARK: - 切换服务器
    func switchServer(to serverID: String) {
        if serverID.isEmpty {
            self.serverID = ""
            self.currentPath = "/"
            self.items = []
            self.treeNodes = []
            self.directoryCache.removeAll()
            self.syncStates.removeAll()
            self.downloadingFiles.removeAll()
            self.uploadingFiles.removeAll()
            self.activeTransferTask = nil
            self.errorMessage = "请选择服务器"
            self.loadingState = .idle
            return
        }
        
        guard self.serverID != serverID else { return }
        
        Logger.shared.info("切换服务器: \(self.serverID) -> \(serverID)")
        
        self.serverID = serverID
        self.currentPath = "/"
        self.items = []
        self.treeNodes = []
        self.directoryCache.removeAll()
        self.syncStates.removeAll()
        self.downloadingFiles.removeAll()
        self.uploadingFiles.removeAll()
        self.activeTransferTask = nil
        self.errorMessage = nil
        self.loadingState = .idle
        
        let serverName = ConfigurationManager.shared.getServers()
            .first(where: { $0.id == serverID })?.name ?? serverID
        eventBus.publish(ServerSwitched(serverID: serverID, serverName: serverName))
        
        reloadCurrentDirectory()
        preloadRootDirectory()
    }

    // MARK: - 缓存Key生成规则
    private func cacheKey(for path: String) -> String {
        return "\(serverID)_\(normalizePath(path))"
    }

    // MARK: - 目录导航操作
    func navigateTo(path: String) {
        let normalized = normalizePath(path)
        currentPath = normalized
        loadDirectory(path: normalized)
    }

    func navigateUp() {
        guard currentPath != "/" else { return }
        let parent = getParentPath(currentPath)
        navigateTo(path: parent)
    }

    func reloadCurrentDirectory() {
        loadDirectory(path: currentPath)
    }

    // MARK: 加载目录核心逻辑
    private func loadDirectory(path: String) {
        guard loadingState != .loading else { return }
        loadingState = .loading
        errorMessage = nil
        
        let key = cacheKey(for: path)
        let currentServerID = self.serverID

        // ✅ 使用子线程执行所有操作
        Thread.detachNewThread { [weak self] in
            guard let self = self else { return }
            
            // ✅ 使用同步版本（在子线程调用）
            if let cachedList = self.cacheManager.getFileListSync(key: key) {
                let sortedItems = self.sortItems(cachedList)
                self.restoreSyncStates(for: cachedList)
                
                DispatchQueue.main.async {
                    self.items = sortedItems
                    self.loadingState = .success
                    self.objectWillChange.send()
                }
            }
            
            // 网络请求
            do {
                let remoteItems = try WebDAVModule.shared.listFiles(serverID: currentServerID, path: path)
                
                let sortedItems = self.sortItems(remoteItems)
                self.cacheManager.setFileList(key: key, files: remoteItems)
                let dirs = remoteItems.filter { $0.isDirectory }
                
                DispatchQueue.main.async {
                    self.items = sortedItems
                    self.directoryCache[path] = dirs
                    self.updateSyncStates(for: remoteItems)
                    self.buildTree()
                    self.highlightCurrentPath()
                    self.loadingState = .success
                    self.objectWillChange.send()
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.loadingState = .failure(error)
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // MARK: - 同步状态管理
    
    private func updateSyncStates(for files: [FileInfo]) {
        for file in files {
            if file.isDirectory {
                syncStates[file.path] = SyncState.synced
                continue
            }
            
            if downloadingFiles.contains(file.path) {
                syncStates[file.path] = SyncState.downloading
                continue
            }
            
            if uploadingFiles.contains(file.path) {
                syncStates[file.path] = SyncState.uploading
                continue
            }
            
            let isCached = cacheManager.isFileCachedInMirror(
                serverID: serverID,
                remotePath: file.path
            )
            syncStates[file.path] = isCached ? .synced : .notSynced
        }
    }

    private func restoreSyncStates(for files: [FileInfo]) {
        for file in files {
            if syncStates[file.path] == nil {
                let isCached = cacheManager.isFileCachedInMirror(
                    serverID: serverID,
                    remotePath: file.path
                )
                syncStates[file.path] = isCached ? .synced : .notSynced
            }
        }
    }
    
    func getSyncState(for file: FileInfo) -> SyncState {
        if let state = syncStates[file.path] {
            return state
        }
        if file.isDirectory {
            return .synced
        }
        if cacheManager.isFileCachedInMirror(serverID: serverID, remotePath: file.path) {
            return .synced
        }
        return .notSynced
    }
    
    func markAsSynced(filePath: String) {
        syncStates[filePath] = SyncState.synced
        objectWillChange.send()
    }
    
    func markAsDownloading(filePath: String) {
        downloadingFiles.insert(filePath)
        syncStates[filePath] = SyncState.downloading
        objectWillChange.send()
    }
    
    func markAsUploading(filePath: String) {
        uploadingFiles.insert(filePath)
        syncStates[filePath] = SyncState.uploading
        objectWillChange.send()
    }

    // MARK: 文件排序逻辑
    private func sortItems(_ list: [FileInfo]) -> [FileInfo] {
        list.sorted { a, b in
            let aFolder = a.isDirectory
            let bFolder = b.isDirectory
            if aFolder != bFolder { return aFolder }
            switch sortOrder {
            case .nameAsc: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedStandardCompare(b.name) == .orderedDescending
            case .sizeAsc: return a.size < b.size
            case .sizeDesc: return a.size > b.size
            case .dateAsc: return a.modificationDate < b.modificationDate
            case .dateDesc: return a.modificationDate > b.modificationDate
            }
        }
    }

    // MARK: 路径标准化工具
    private func normalizePath(_ rawPath: String) -> String {
        var p = rawPath.trimmingCharacters(in: .whitespaces)
        if !p.starts(with: "/") {
            p = "/" + p
        }
        while p.contains("//") {
            p = p.replacingOccurrences(of: "//", with: "/")
        }
        if p != "/" && p.hasSuffix("/") {
            p.removeLast()
        }
        return p
    }

    // MARK: 获取父目录路径
    private func getParentPath(_ path: String) -> String {
        guard path != "/" else { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let lastSlashIndex = trimmed.lastIndex(of: "/") else { return "/" }
        if lastSlashIndex == trimmed.startIndex {
            return "/"
        }
        let parent = String(trimmed[..<lastSlashIndex])
        return normalizePath(parent)
    }

    // MARK: 文件点击操作分发
    func openItem(_ item: FileInfo) {
        if item.isDirectory {
            navigateTo(path: item.path)
        } else {
            if isFileCached(file: item) {
                if let localPath = getLocalCachePath(for: item) {
                    print("📂 [FileBrowser] 打开已缓存文件: \(localPath.path)")
                    NSWorkspace.shared.open(localPath)
                    return
                }
            }
            
            print("📥 [FileBrowser] 下载文件: \(item.path)")
            downloadFile(item)
        }
    }

    // MARK: 强制刷新当前目录
    func refreshCache() {
        let key = cacheKey(for: currentPath)
        cacheManager.invalidateFileList(key: key)
        directoryCache.removeAll()
        reloadCurrentDirectory()
    }
    
    // MARK: - 文件操作
        
    func renameFile(at path: String, newName: String) {
        guard !newName.isEmpty else {
            errorMessage = "名称不能为空"
            return
        }
        
        let directory = (path as NSString).deletingLastPathComponent
        let newPath = directory + "/" + newName
        
        if items.contains(where: { $0.path == newPath }) {
            errorMessage = "已存在同名文件"
            return
        }
        
        guard let module = ProtocolModuleManager.shared.getInstance(serverID: serverID) else {
            errorMessage = "协议实例不存在"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try module.moveItem(serverID: serverID, from: path, to: newPath)
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.reloadCurrentDirectory()
                    self.eventBus.publish(FileSystemRefreshEvent())
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "重命名失败: \(error.localizedDescription)"
                }
            }
        }
    }
        
    func deleteFile(at path: String) {
        guard let module = ProtocolModuleManager.shared.getInstance(serverID: serverID) else {
            errorMessage = "协议实例不存在"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try module.deleteItem(serverID: serverID, path: path)
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.syncStates.removeValue(forKey: path)
                    self.reloadCurrentDirectory()
                    self.eventBus.publish(FileSystemRefreshEvent())
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "删除失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - 上传下载功能
    
    /// 获取本地缓存路径（保持远程目录结构）
    private func getLocalCachePath(for file: FileInfo) -> URL? {
        return cacheManager.getMirrorFilePath(
            serverID: serverID,
            remotePath: file.path
        )
    }
    
    /// 检查文件是否已缓存
    func isFileCached(file: FileInfo) -> Bool {
        return cacheManager.isFileCachedInMirror(
            serverID: serverID,
            remotePath: file.path
        )
    }
    
    /// 获取缓存文件路径
    func getCachedFileURL(for file: FileInfo) -> URL? {
        return getLocalCachePath(for: file)
    }
    
    /// 下载单个文件（在后台执行）
    func downloadFile(_ file: FileInfo) {
        guard !file.isDirectory else {
            errorMessage = "不能下载文件夹"
            return
        }
        
        guard let localPath = getLocalCachePath(for: file) else {
            errorMessage = "无法获取缓存路径"
            return
        }
        
        let parentDir = localPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )
        }
        
        if FileManager.default.fileExists(atPath: localPath.path) {
            NSWorkspace.shared.open(localPath)
            return
        }
        
        isLoading = true
        errorMessage = nil
        let currentServerID = self.serverID  // ✅ 捕获值
        
        self.activeTransferTask = TransferTask(
            fileName: file.name,
            filePath: file.path,
            progress: 0,
            isUpload: false
        )
        
        eventBus.publish(TransferStarted(
            transferID: UUID().uuidString,
            serverID: serverID,
            filePath: file.path,
            localPath: localPath.path,
            totalBytes: file.size,
            isUpload: false
        ))
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try WebDAVModule.shared.downloadFile(
                    serverID: currentServerID,
                    remotePath: file.path,
                    localPath: localPath.path
                ) { progress in
                    DispatchQueue.main.async {
                        self.activeTransferTask?.progress = progress
                        self.objectWillChange.send()
                        self.eventBus.publish(FileDownloadProgress(
                            fileName: file.name,
                            filePath: file.path,
                            progress: progress,
                            bytesTransferred: Int64(progress * Double(file.size))
                        ))
                    }
                }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.activeTransferTask = nil
                    self.eventBus.publish(FileDownloadComplete(
                        fileName: file.name,
                        filePath: file.path,
                        success: true,
                        localPath: localPath.path
                    ))
                    self.syncStates[file.path] = .synced
                    self.objectWillChange.send()
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.activeTransferTask = nil
                    self.errorMessage = "下载失败: \(error.localizedDescription)"
                    self.eventBus.publish(FileDownloadComplete(
                        fileName: file.name,
                        filePath: file.path,
                        success: false,
                        localPath: nil,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    /// 上传单个文件
    func uploadFile(localPath: URL, remotePath: String) {
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            errorMessage = "文件不存在"
            return
        }
        
        let fileName = localPath.lastPathComponent
        let currentServerID = self.serverID  // ✅ 捕获值
        
        if items.contains(where: { $0.name == fileName }) {
            let alert = NSAlert()
            alert.messageText = "文件已存在"
            alert.informativeText = "远程目录中已存在同名文件 \"\(fileName)\"，是否覆盖？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            
            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                return
            }
        }
        
        isLoading = true
        errorMessage = nil
        
        let remoteFullPath = (remotePath as NSString).appendingPathComponent(fileName)
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: localPath.path)
        let fileSize = (attributes?[.size] as? UInt64) ?? 0
        
        self.activeTransferTask = TransferTask(
            fileName: fileName,
            filePath: remoteFullPath,
            progress: 0,
            isUpload: true
        )
        
        eventBus.publish(TransferStarted(
            transferID: UUID().uuidString,
            serverID: serverID,
            filePath: remoteFullPath,
            localPath: localPath.path,
            totalBytes: fileSize,
            isUpload: true
        ))
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try WebDAVModule.shared.uploadFile(
                    serverID: currentServerID,
                    localPath: localPath.path,
                    remotePath: remoteFullPath
                ) { progress in
                    DispatchQueue.main.async {
                        self.activeTransferTask?.progress = progress
                        self.objectWillChange.send()
                        self.eventBus.publish(FileUploadProgress(
                            fileName: fileName,
                            filePath: remoteFullPath,
                            progress: progress,
                            bytesTransferred: Int64(progress * Double(fileSize))
                        ))
                    }
                }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.activeTransferTask = nil
                    self.eventBus.publish(FileUploadComplete(
                        fileName: fileName,
                        filePath: remoteFullPath,
                        success: true
                    ))
                    self.reloadCurrentDirectory()
                    self.objectWillChange.send()
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.activeTransferTask = nil
                    self.errorMessage = "上传失败: \(error.localizedDescription)"
                    self.eventBus.publish(FileUploadComplete(
                        fileName: fileName,
                        filePath: remoteFullPath,
                        success: false,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
    
    /// 上传多个文件
    func uploadFiles(urls: [URL], to remotePath: String) {
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                uploadFolder(url: url, to: remotePath)
            } else {
                uploadFile(localPath: url, remotePath: remotePath)
            }
        }
    }
    
    /// 上传文件夹（递归）
    func uploadFolder(url: URL, to remotePath: String) {
        let folderName = url.lastPathComponent
        let remoteFolderPath = (remotePath as NSString).appendingPathComponent(folderName)
        
        do {
            try WebDAVModule.shared.createDirectory(serverID: serverID, path: remoteFolderPath)
        } catch {
            errorMessage = "创建远程目录失败: \(error.localizedDescription)"
            return
        }
        
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: url.path, with: "")
            let remoteFilePath = (remoteFolderPath as NSString).appendingPathComponent(relativePath)
            
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                try? WebDAVModule.shared.createDirectory(serverID: serverID, path: remoteFilePath)
            } else {
                let parentPath = (remoteFolderPath as NSString).appendingPathComponent(
                    (relativePath as NSString).deletingLastPathComponent
                )
                uploadFile(localPath: fileURL, remotePath: parentPath)
            }
        }
    }
    
    /// 取消下载
    func cancelDownload(filePath: String) {
        NetworkManager.shared.cancelAllTasks(serverID: serverID)
        downloadingFiles.remove(filePath)
        syncStates[filePath] = .notSynced
        activeTransferTask = nil
        objectWillChange.send()
        eventBus.publish(TransferCancelled(
            transferID: UUID().uuidString,
            serverID: serverID
        ))
    }
    
    /// 取消上传
    func cancelUpload(filePath: String) {
        NetworkManager.shared.cancelAllTasks(serverID: serverID)
        uploadingFiles.remove(filePath)
        syncStates[filePath] = .notSynced
        activeTransferTask = nil
        objectWillChange.send()
        eventBus.publish(TransferCancelled(
            transferID: UUID().uuidString,
            serverID: serverID
        ))
    }
    
    // MARK: - 目录树方法
    
    func buildTree() {
        let rootNode = TreeNode(name: "根目录", path: "/", isDirectory: true)
        rootNode.isExpanded = true
        
        var nodeDict: [String: TreeNode] = [:]
        nodeDict["/"] = rootNode
        
        let allPaths = directoryCache.keys.sorted()
        
        for path in allPaths where path != "/" {
            let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
            var currentPath = ""
            
            for component in components {
                let fullPath = currentPath.isEmpty ? "/" + component : currentPath + "/" + component
                if nodeDict[fullPath] == nil {
                    let newNode = TreeNode(name: component, path: fullPath, isDirectory: true)
                    nodeDict[fullPath] = newNode
                    
                    let parentPath = currentPath.isEmpty ? "/" : currentPath
                    if let parentNode = nodeDict[parentPath] {
                        if !parentNode.children.contains(where: { $0.path == fullPath }) {
                            parentNode.children.append(newNode)
                            newNode.parent = parentNode
                        }
                    }
                }
                currentPath = fullPath
            }
        }
        
        for (path, node) in nodeDict {
            if let cachedDirs = directoryCache[path] {
                for dir in cachedDirs {
                    if !node.children.contains(where: { $0.path == dir.path }) {
                        let childNode = TreeNode(name: dir.name, path: dir.path, isDirectory: true)
                        childNode.parent = node
                        node.children.append(childNode)
                    }
                }
            }
        }
        
        sortTreeNodes(rootNode)
        treeNodes = [rootNode]
    }
    
    private func sortTreeNodes(_ node: TreeNode) {
        node.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for child in node.children {
            sortTreeNodes(child)
        }
    }
    
    func loadChildren(for node: TreeNode) {
        guard node.isDirectory else { return }
        guard !node.isLoading else { return }
        
        node.isLoading = true
        let currentServerID = self.serverID  // ✅ 捕获值
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let files = try WebDAVModule.shared.listFiles(serverID: currentServerID, path: node.path)
                let directories = files.filter { $0.isDirectory }
                
                DispatchQueue.main.async {
                    node.isLoading = false
                    self.directoryCache[node.path] = directories
                    
                    let existingPaths = Set(node.children.map { $0.path })
                    
                    for dir in directories {
                        if !existingPaths.contains(dir.path) {
                            let child = TreeNode(name: dir.name, path: dir.path, isDirectory: true)
                            child.parent = node
                            node.children.append(child)
                        }
                    }
                    
                    node.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    self.objectWillChange.send()
                }
            } catch {
                DispatchQueue.main.async {
                    node.isLoading = false
                    self.errorMessage = "加载子目录失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func highlightCurrentPath() {
        guard let rootNode = treeNodes.first else { return }
        
        let components = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
        var currentNode = rootNode
        var currentFullPath = ""
        
        for component in components {
            currentFullPath = currentFullPath.isEmpty ? "/" + component : currentFullPath + "/" + component
            if let child = currentNode.children.first(where: { $0.name == component }) {
                child.isExpanded = true
                currentNode = child
            } else {
                break
            }
        }
    }
    
    func preloadRootDirectory() {
        if directoryCache["/"] == nil {
            let currentServerID = self.serverID  // ✅ 捕获值
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                do {
                    let files = try WebDAVModule.shared.listFiles(serverID: currentServerID, path: "/")
                    let dirs = files.filter { $0.isDirectory }
                    DispatchQueue.main.async {
                        self.directoryCache["/"] = dirs
                        self.buildTree()
                        self.highlightCurrentPath()
                    }
                } catch {
                    print("预加载根目录失败: \(error)")
                }
            }
        }
    }
}
