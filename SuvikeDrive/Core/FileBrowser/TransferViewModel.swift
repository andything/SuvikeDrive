//
//  TransferViewModel.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：文件传输任务管理
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI
import Combine

// MARK: - 传输任务
struct TransferTask: Identifiable {
    let id = UUID()
    let fileName: String
    let filePath: String
    var progress: Double = 0
    var speed: String?
    var isUpload: Bool
    var isSuccess: Bool = false
    var completedAt: Date = Date()
    var isCancelled: Bool = false
}

// MARK: - 传输 ViewModel
class TransferViewModel: ObservableObject {
    @Published var downloadingTasks: [TransferTask] = []
    @Published var uploadingTasks: [TransferTask] = []
    @Published var completedTasks: [TransferTask] = []
    
    private var eventTokens: [SubscriptionToken] = []
    private var downloadProgressMap: [String: Double] = [:]
    private var uploadProgressMap: [String: Double] = [:]
    private var speedTimers: [String: Timer] = [:]
    private var lastBytesTransferred: [String: Int64] = [:]
    private var lastUpdateTime: [String: Date] = [:]
    
    init() {
        setupEventListeners()
    }
    
    deinit {
        eventTokens.forEach { $0.unsubscribe() }
        eventTokens.removeAll()
        speedTimers.values.forEach { $0.invalidate() }
    }
    
    // MARK: - 事件监听
    private func setupEventListeners() {
        // 下载进度
        let downloadProgressToken = EventBus.shared.subscribe(to: FileDownloadProgress.self) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleDownloadProgress(event)
            }
        }
        eventTokens.append(downloadProgressToken)
        
        // 下载完成
        let downloadCompleteToken = EventBus.shared.subscribe(to: FileDownloadComplete.self) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleDownloadComplete(event)
            }
        }
        eventTokens.append(downloadCompleteToken)
        
        // 上传进度
        let uploadProgressToken = EventBus.shared.subscribe(to: FileUploadProgress.self) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleUploadProgress(event)
            }
        }
        eventTokens.append(uploadProgressToken)
        
        // 上传完成
        let uploadCompleteToken = EventBus.shared.subscribe(to: FileUploadComplete.self) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleUploadComplete(event)
            }
        }
        eventTokens.append(uploadCompleteToken)
    }
    
    // MARK: - 下载处理
    func handleDownloadProgress(_ event: FileDownloadProgress) {
        let fileName = (event.fileName as NSString).lastPathComponent
        
        if let index = downloadingTasks.firstIndex(where: { $0.filePath == event.filePath }) {
            var task = downloadingTasks[index]
            task.progress = event.progress
            task.speed = calculateSpeed(filePath: event.filePath, bytes: event.bytesTransferred)
            downloadingTasks[index] = task
        } else {
            let task = TransferTask(
                fileName: fileName,
                filePath: event.filePath,
                progress: event.progress,
                isUpload: false
            )
            downloadingTasks.append(task)
        }
        
        downloadProgressMap[event.filePath] = event.progress
    }
    
    func handleDownloadComplete(_ event: FileDownloadComplete) {
        if let index = downloadingTasks.firstIndex(where: { $0.filePath == event.filePath }) {
            var task = downloadingTasks[index]
            task.isSuccess = event.success
            task.progress = event.success ? 1.0 : task.progress
            task.completedAt = Date()
            downloadingTasks.remove(at: index)
            
            if event.success {
                completedTasks.insert(task, at: 0)
            }
        }
        
        downloadProgressMap.removeValue(forKey: event.filePath)
        speedTimers[event.filePath]?.invalidate()
        speedTimers.removeValue(forKey: event.filePath)
        lastBytesTransferred.removeValue(forKey: event.filePath)
        lastUpdateTime.removeValue(forKey: event.filePath)
    }
    
    // MARK: - 上传处理
    func handleUploadProgress(_ event: FileUploadProgress) {
        let fileName = (event.fileName as NSString).lastPathComponent
        
        if let index = uploadingTasks.firstIndex(where: { $0.filePath == event.filePath }) {
            var task = uploadingTasks[index]
            task.progress = event.progress
            task.speed = calculateSpeed(filePath: event.filePath, bytes: event.bytesTransferred)
            uploadingTasks[index] = task
        } else {
            let task = TransferTask(
                fileName: fileName,
                filePath: event.filePath,
                progress: event.progress,
                isUpload: true
            )
            uploadingTasks.append(task)
        }
        
        uploadProgressMap[event.filePath] = event.progress
    }
    
    func handleUploadComplete(_ event: FileUploadComplete) {
        if let index = uploadingTasks.firstIndex(where: { $0.filePath == event.filePath }) {
            var task = uploadingTasks[index]
            task.isSuccess = event.success
            task.progress = event.success ? 1.0 : task.progress
            task.completedAt = Date()
            uploadingTasks.remove(at: index)
            
            if event.success {
                completedTasks.insert(task, at: 0)
            }
        }
        
        uploadProgressMap.removeValue(forKey: event.filePath)
        speedTimers[event.filePath]?.invalidate()
        speedTimers.removeValue(forKey: event.filePath)
        lastBytesTransferred.removeValue(forKey: event.filePath)
        lastUpdateTime.removeValue(forKey: event.filePath)
    }
    
    // MARK: - 速度计算
    private func calculateSpeed(filePath: String, bytes: Int64) -> String {
        let now = Date()
        let lastBytes = lastBytesTransferred[filePath] ?? bytes
        let lastTime = lastUpdateTime[filePath] ?? now
        let timeDiff = now.timeIntervalSince(lastTime)
        
        lastBytesTransferred[filePath] = bytes
        lastUpdateTime[filePath] = now
        
        if timeDiff > 0.5 {
            let speed = Double(bytes - lastBytes) / timeDiff
            return formatSpeed(speed)
        }
        return formatSpeed(0)
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 0 { return "0 B/s" }
        if bytesPerSecond < 1024 { return String(format: "%.0f B/s", bytesPerSecond) }
        if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        }
        if bytesPerSecond < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        }
        return String(format: "%.2f GB/s", bytesPerSecond / (1024 * 1024 * 1024))
    }
    
    // MARK: - 操作
    func cancelDownload(_ id: UUID) {
        if let index = downloadingTasks.firstIndex(where: { $0.id == id }) {
            let task = downloadingTasks[index]
            EventBus.shared.publish(CancelDownloadRequest(filePath: task.filePath))
            downloadingTasks.remove(at: index)
        }
    }
    
    func cancelUpload(_ id: UUID) {
        if let index = uploadingTasks.firstIndex(where: { $0.id == id }) {
            let task = uploadingTasks[index]
            EventBus.shared.publish(CancelUploadRequest(filePath: task.filePath))
            uploadingTasks.remove(at: index)
        }
    }
    
    func startMonitoring() {
        // 已通过 EventBus 自动监听
    }
    
    func stopMonitoring() {
        // 不需要额外操作
    }
}
