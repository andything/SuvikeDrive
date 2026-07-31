
//
//  OTAManagerDownload.swift
//  SuvikeDrive
//
//  功能: OTA 下载 + 断点续传 + 下载代理
//

import Foundation

// MARK: - 下载代理
class DownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    var onComplete: ((URL?, Error?) -> Void)?
    var onProgress: ((Double) -> Void)?
    private var progressObservation: NSKeyValueObservation?
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onComplete?(location, nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                let customError = NSError(domain: "OTAManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: error.localizedDescription,
                    NSURLSessionDownloadTaskResumeData: resumeData
                ])
                onComplete?(nil, customError)
                return
            }
            onComplete?(nil, error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(newRequest)
    }
    
    // ✅ 修复：添加 options: [.new] 参数
    func setupProgressObserver(for task: URLSessionDownloadTask) {
        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, change in
            let fraction = change.newValue ?? p.fractionCompleted
            DispatchQueue.main.async {
                self?.onProgress?(fraction)
            }
        }
    }
    
    deinit {
        progressObservation?.invalidate()
    }
}

extension OTAManager {
    
    // MARK: - 下载更新
    func downloadUpdate(progressHandler: @escaping (Double) -> Void, completion: @escaping (Result<URL, UpdateError>) -> Void) {
        guard let updateInfo = self.updateInfo else {
            completion(.failure(.noUpdateAvailable))
            return
        }
        
        if let minOSVersion = updateInfo.minOSVersion {
            let currentOSVersion = ProcessInfo.processInfo.operatingSystemVersion
            let minVersion = minOSVersion.split(separator: ".").map { Int($0) ?? 0 }
            if currentOSVersion.majorVersion < minVersion[0] ||
               (currentOSVersion.majorVersion == minVersion[0] && currentOSVersion.minorVersion < minVersion[1]) {
                completion(.failure(.incompatibleOS))
                return
            }
        }
        
        guard !isDownloading else {
            completion(.failure(.alreadyDownloading))
            return
        }
        
        isDownloading = true
        self.progressHandler = progressHandler
        self.completionHandler = completion
        
        guard let downloadURL = URL(string: updateInfo.downloadURL) else {
            isDownloading = false
            completion(.failure(.downloadFailed(nil)))
            return
        }
        
        let destinationURL = getUpdatePackagePath(for: updateInfo.version)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if verifyUpdatePackage(at: destinationURL, with: updateInfo) {
                Logger.shared.info("更新包已存在且完整: \(destinationURL.path)")
                isDownloading = false
                EventBus.shared.publish(OTADownloadComplete(
                    version: updateInfo.version,
                    packagePath: destinationURL.path
                ))
                DispatchQueue.main.async {
                    completion(.success(destinationURL))
                }
                return
            } else {
                do {
                    try FileManager.default.removeItem(at: destinationURL)
                    Logger.shared.info("已移除损坏的旧包，准备重新下载")
                } catch {
                    Logger.shared.warning("无法删除损坏的旧包: \(error.localizedDescription)")
                }
            }
        }
        
        let resumeDataFile = updateDirectory.appendingPathComponent("resume_data_\(updateInfo.version).dat")
        if let resumeData = try? Data(contentsOf: resumeDataFile) {
            if let resumeURL = extractURLFromResumeData(resumeData), resumeURL == downloadURL {
                self.downloadResumeData = resumeData
                Logger.shared.info("使用断点续传数据恢复下载")
            } else {
                Logger.shared.warning("断点续传数据无效，重新下载")
                try? FileManager.default.removeItem(at: resumeDataFile)
            }
        }
        
        Logger.shared.info("开始下载更新: \(updateInfo.version)")
        startDownloadTask(from: downloadURL, to: destinationURL, resumeData: downloadResumeData)
    }
    
    // MARK: - 开始下载任务
    private func startDownloadTask(from url: URL, to destination: URL, resumeData: Data?) {
        let delegate = DownloadDelegate()
        self.downloadDelegate = delegate
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
        
        let task: URLSessionDownloadTask
        if let resumeData = resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: url)
        }
        
        delegate.onProgress = { [weak self] progress in
            DispatchQueue.main.async {
                self?.updateProgress = progress
                self?.progressHandler?(progress)
                if let updateInfo = self?.updateInfo {
                    EventBus.shared.publish(OTADownloadProgress(
                        version: updateInfo.version,
                        progress: progress,
                        downloadedBytes: Int64(progress * Double(updateInfo.size)),
                        totalBytes: updateInfo.size
                    ))
                }
            }
        }
        
        delegate.onComplete = { [weak self] tempURL, error in
            guard let self = self else { return }
            self.isDownloading = false
            self.downloadDelegate = nil
            
            if let error = error {
                var resumeData: Data?
                if let nsError = error as NSError? {
                    resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                }
                if let resumeData = resumeData {
                    let resumeDataFile = self.updateDirectory.appendingPathComponent("resume_data_\(self.updateInfo?.version ?? "unknown").dat")
                    try? resumeData.write(to: resumeDataFile)
                    self.downloadResumeData = resumeData
                    Logger.shared.info("保存断点续传数据")
                }
                Logger.shared.error("下载更新失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.completionHandler?(.failure(.downloadFailed(error)))
                    self.completionHandler = nil
                }
                return
            }
            
            guard let tempURL = tempURL else {
                Logger.shared.error("下载完成但文件路径为空")
                DispatchQueue.main.async {
                    self.completionHandler?(.failure(.downloadFailed(nil)))
                    self.completionHandler = nil
                }
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                
                guard let updateInfo = self.updateInfo else {
                    try FileManager.default.removeItem(at: destination)
                    DispatchQueue.main.async {
                        self.completionHandler?(.failure(.checksumMismatch))
                        self.completionHandler = nil
                    }
                    return
                }
                
                let isValid = self.verifyUpdatePackage(at: destination, with: updateInfo)
                if !isValid {
                    try FileManager.default.removeItem(at: destination)
                    DispatchQueue.main.async {
                        self.completionHandler?(.failure(.checksumMismatch))
                        self.completionHandler = nil
                    }
                    return
                }
                
                let resumeDataFile = self.updateDirectory.appendingPathComponent("resume_data_\(updateInfo.version).dat")
                try? FileManager.default.removeItem(at: resumeDataFile)
                
                Logger.shared.info("更新包下载完成: \(destination.path)")
                
                EventBus.shared.publish(OTADownloadComplete(
                    version: updateInfo.version,
                    packagePath: destination.path
                ))
                
                DispatchQueue.main.async {
                    self.completionHandler?(.success(destination))
                    self.completionHandler = nil
                }
            } catch {
                Logger.shared.error("保存更新包失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.completionHandler?(.failure(.saveFailed(error)))
                    self.completionHandler = nil
                }
            }
        }
        
        // ✅ 现在这个方法内部已修复
        delegate.setupProgressObserver(for: task)
        self.downloadTask = task
        task.resume()
    }
    
    // MARK: - 从断点续传数据中提取 URL
    private func extractURLFromResumeData(_ resumeData: Data) -> URL? {
        do {
            if let dict = try PropertyListSerialization.propertyList(from: resumeData, options: [], format: nil) as? [String: Any] {
                if let urlString = dict["NSURLSessionDownloadURL"] as? String {
                    return URL(string: urlString)
                }
                if let urlString = dict["URL"] as? String {
                    return URL(string: urlString)
                }
            }
        } catch {
            if let urlString = String(data: resumeData, encoding: .utf8) {
                let pattern = "https?://[^\\s\"]+"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) {
                    if let range = Range(match.range, in: urlString) {
                        return URL(string: String(urlString[range]))
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - 取消下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        updateProgress = 0
        downloadResumeData = nil
        progressHandler = nil
        completionHandler = nil
        downloadDelegate = nil
        Logger.shared.info("更新下载已取消")
    }
}
