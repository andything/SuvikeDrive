//
//  NetworkTaskManager.swift
//  SuvikeDrive
//
//  模块功能：网络任务管理器
//  职责：管理所有网络任务（下载/上传/请求），支持暂停/恢复/取消
//        断线时自动暂停，重连时自动恢复
//  依赖：Foundation、Combine、NetworkTypes
//

import Foundation
import Combine

// MARK: - 任务状态
enum NetworkTaskStatus {
    case pending      // 等待执行
    case running      // 执行中
    case paused       // 暂停（断线/用户暂停）
    case completed    // 完成
    case failed       // 失败
    case cancelled    // 取消
    case retrying     // 重试中
}

// MARK: - 任务类型
enum NetworkTaskType {
    case request      // 普通请求
    case download     // 下载
    case upload       // 上传
}

// MARK: - 任务协议
protocol NetworkTask: AnyObject {
    var id: UUID { get }
    var serverID: String { get }
    var type: NetworkTaskType { get }
    var status: NetworkTaskStatus { get set }
    var progress: Double { get }
    var error: Error? { get set }
    var retryCount: Int { get set }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    
    func resume()
    func pause()
    func cancel()
}

// MARK: - 下载任务
class DownloadNetworkTask: NetworkTask, ObservableObject {
    let id = UUID()
    let serverID: String
    let type: NetworkTaskType = .download
    let url: URL
    let destination: URL
    let totalSize: Int64
    let createdAt = Date()
    
    @Published var status: NetworkTaskStatus = .pending
    @Published var downloadedSize: Int64 = 0
    @Published var progress: Double = 0
    @Published var updatedAt = Date()
    
    var error: Error?
    var retryCount: Int = 0
    var resumeData: Data?          // URLSession 的 resumeData
    var task: URLSessionDownloadTask?
    
    init(serverID: String, url: URL, destination: URL, totalSize: Int64 = 0) {
        self.serverID = serverID
        self.url = url
        self.destination = destination
        self.totalSize = totalSize
    }
    
    func resume() {
        status = .running
        updatedAt = Date()
    }
    
    func pause() {
        status = .paused
        updatedAt = Date()
    }
    
    func cancel() {
        status = .cancelled
        task?.cancel()
        updatedAt = Date()
    }
    
    func updateProgress(bytesWritten: Int64, totalBytes: Int64) {
        downloadedSize = bytesWritten
        progress = totalBytes > 0 ? Double(bytesWritten) / Double(totalBytes) : 0
        updatedAt = Date()
    }
}

// MARK: - 上传任务
class UploadNetworkTask: NetworkTask, ObservableObject {
    let id = UUID()
    let serverID: String
    let type: NetworkTaskType = .upload
    let fileURL: URL
    let remoteURL: URL
    let totalSize: Int64
    let createdAt = Date()
    
    @Published var status: NetworkTaskStatus = .pending
    @Published var uploadedSize: Int64 = 0
    @Published var progress: Double = 0
    @Published var updatedAt = Date()
    
    var error: Error?
    var retryCount: Int = 0
    var task: URLSessionUploadTask?
    var chunkIndex: Int = 0
    var chunkCount: Int = 0
    
    init(serverID: String, fileURL: URL, remoteURL: URL, totalSize: Int64) {
        self.serverID = serverID
        self.fileURL = fileURL
        self.remoteURL = remoteURL
        self.totalSize = totalSize
    }
    
    func resume() {
        status = .running
        updatedAt = Date()
    }
    
    func pause() {
        status = .paused
        updatedAt = Date()
    }
    
    func cancel() {
        status = .cancelled
        task?.cancel()
        updatedAt = Date()
    }
    
    func updateProgress(bytesWritten: Int64, totalBytes: Int64) {
        uploadedSize = bytesWritten
        progress = totalBytes > 0 ? Double(bytesWritten) / Double(totalBytes) : 0
        updatedAt = Date()
    }
}

// MARK: - 任务管理器
class NetworkTaskManager: ObservableObject {
    static let shared = NetworkTaskManager()
    
    @Published private(set) var tasks: [String: [NetworkTask]] = [:]  // serverID -> [任务]
    @Published private(set) var activeTaskCount: Int = 0
    @Published private(set) var isPaused: Bool = false
    
    private let maxConcurrentTasks = 3
    private var runningTasks: [UUID] = []
    private let taskLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    
    // ✅ 网络状态监听
    private var isNetworkAvailable: Bool = true
    
    private init() {
        // 监听网络状态
        NetworkManager.shared.$isReachable
            .sink { [weak self] isReachable in
                if isReachable && self?.isPaused == true {
                    // 网络恢复，恢复所有任务
                    self?.resumeAll()
                } else if !isReachable && self?.isPaused == false {
                    // 网络断开，暂停所有任务
                    self?.pauseAll()
                }
                self?.isPaused = !isReachable
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 添加任务
    
    func addDownloadTask(serverID: String, url: URL, destination: URL, totalSize: Int64 = 0) -> DownloadNetworkTask {
        let task = DownloadNetworkTask(serverID: serverID, url: url, destination: destination, totalSize: totalSize)
        addTask(task, serverID: serverID)
        return task
    }
    
    func addUploadTask(serverID: String, fileURL: URL, remoteURL: URL, totalSize: Int64) -> UploadNetworkTask {
        let task = UploadNetworkTask(serverID: serverID, fileURL: fileURL, remoteURL: remoteURL, totalSize: totalSize)
        addTask(task, serverID: serverID)
        return task
    }
    
    private func addTask(_ task: NetworkTask, serverID: String) {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        if tasks[serverID] == nil {
            tasks[serverID] = []
        }
        tasks[serverID]?.append(task)
        
        // 尝试执行
        processQueue()
    }
    
    // MARK: - 任务控制
    
    func pauseAll() {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        isPaused = true
        for (_, taskList) in tasks {
            for task in taskList where task.status == .running {
                task.pause()
                // 如果是下载任务，保存 resumeData
                if let downloadTask = task as? DownloadNetworkTask {
                    downloadTask.task?.cancel(byProducingResumeData: { data in
                        downloadTask.resumeData = data
                    })
                }
            }
        }
        activeTaskCount = 0
        runningTasks.removeAll()
        print("📶 [TaskManager] 所有任务已暂停（网络断开）")
    }
    
    func resumeAll() {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        isPaused = false
        for (_, taskList) in tasks {
            for task in taskList where task.status == .paused {
                task.resume()
            }
        }
        processQueue()
        print("📶 [TaskManager] 所有任务已恢复（网络恢复）")
    }
    
    func cancelAll(serverID: String? = nil) {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        if let serverID = serverID {
            if let taskList = tasks[serverID] {
                for task in taskList {
                    task.cancel()
                }
                tasks[serverID] = []
            }
        } else {
            for (_, taskList) in tasks {
                for task in taskList {
                    task.cancel()
                }
            }
            tasks.removeAll()
        }
        runningTasks.removeAll()
        activeTaskCount = 0
    }
    
    // MARK: - 队列处理
    
    private func processQueue() {
        guard !isPaused else { return }
        
        let runningCount = runningTasks.count
        if runningCount >= maxConcurrentTasks { return }
        
        let availableSlots = maxConcurrentTasks - runningCount
        var addedCount = 0
        
        for (_, taskList) in tasks {
            for task in taskList where task.status == .pending && addedCount < availableSlots {
                task.resume()
                runningTasks.append(task.id)
                addedCount += 1
            }
            if addedCount >= availableSlots { break }
        }
        
        activeTaskCount = runningTasks.count
    }
    
    func taskDidComplete(_ task: NetworkTask) {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        runningTasks.removeAll { $0 == task.id }
        activeTaskCount = runningTasks.count
        processQueue()
    }
    
    // MARK: - 查询
    
    func getTasks(for serverID: String) -> [NetworkTask] {
        taskLock.lock()
        defer { taskLock.unlock() }
        return tasks[serverID] ?? []
    }
    
    func getTask(by id: UUID) -> NetworkTask? {
        taskLock.lock()
        defer { taskLock.unlock() }
        
        for (_, taskList) in tasks {
            if let task = taskList.first(where: { $0.id == id }) {
                return task
            }
        }
        return nil
    }
    
    func getActiveTasks(for serverID: String) -> [NetworkTask] {
        return getTasks(for: serverID).filter { $0.status == .running || $0.status == .pending }
    }
    
    func getCompletedTasks(for serverID: String) -> [NetworkTask] {
        return getTasks(for: serverID).filter { $0.status == .completed }
    }
    
    func getFailedTasks(for serverID: String) -> [NetworkTask] {
        return getTasks(for: serverID).filter { $0.status == .failed }
    }
}
