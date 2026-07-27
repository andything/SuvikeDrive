//
//  DiskAPI.swift
//  SuvikeDrive
//
//  功能:  全协议远程磁盘统一挂载/卸载底层命令封装
//        本地+远程全盘文件递归扫描逻辑
//        远程目录创建/删除底层IO操作
//        异常挂载磁盘强制卸载、进程清理
//        远程磁盘总容量/已用空间实时查询计算
//        挂载路径权限校验、路径标准化处理
//

import AppKit
import Foundation

class DiskAPI {
    static let shared = DiskAPI()
    
    private let fileManager = FileManager.default
    private let mountQueue = DispatchQueue(label: "com.suvikedrive.disk.mount")
    private let mountedVolumes: NSMutableSet = []
    
    private init() {}
    
    // MARK: - 挂载操作
    func mount(
        url: String,
        mountPath: String,
        credentials: [String: Any]?,
        options: [String: Any]?,
        completion: @escaping (Result<String, DiskError>) -> Void
    ) {
        mountQueue.async {
            guard self.validateMountPath(mountPath) else {
                completion(.failure(.invalidMountPath))
                return
            }
            
            if self.isMounted(mountPath) {
                completion(.failure(.alreadyMounted))
                return
            }
            
            do {
                try self.fileManager.createDirectory(
                    atPath: mountPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                completion(.failure(.mountPointCreationFailed(error)))
                return
            }
            
            let command = self.buildMountCommand(url: url, mountPath: mountPath, credentials: credentials, options: options)
            
            do {
                let output = try self.executeCommand(command)
                
                if self.isMounted(mountPath) {
                    self.mountedVolumes.add(mountPath)
                    Logger.shared.info("挂载成功: \(url) -> \(mountPath)")
                    completion(.success(mountPath))
                } else {
                    try? self.fileManager.removeItem(atPath: mountPath)
                    completion(.failure(.mountFailed(output)))
                }
            } catch {
                try? self.fileManager.removeItem(atPath: mountPath)
                completion(.failure(.commandFailed(error)))
            }
        }
    }
    
    func unmount(mountPath: String, force: Bool = false, completion: @escaping (Result<Void, DiskError>) -> Void) {
        mountQueue.async {
            guard self.isMounted(mountPath) else {
                completion(.failure(.notMounted))
                return
            }
            
            var command = "diskutil unmount \"\(mountPath)\""
            if force {
                command = "diskutil unmount force \"\(mountPath)\""
            }
            
            do {
                _ = try self.executeCommand(command)
                self.mountedVolumes.remove(mountPath)
                try? self.fileManager.removeItem(atPath: mountPath)
                Logger.shared.info("卸载成功: \(mountPath)")
                completion(.success(()))
            } catch {
                if !force {
                    self.unmount(mountPath: mountPath, force: true, completion: completion)
                } else {
                    completion(.failure(.unmountFailed(error)))
                }
            }
        }
    }
    
    func forceUnmount(mountPath: String) -> Bool {
        let command = "diskutil unmount force \"\(mountPath)\""
        
        do {
            let _ = try executeCommand(command)
            mountedVolumes.remove(mountPath)
            try? fileManager.removeItem(atPath: mountPath)
            Logger.shared.info("强制卸载成功: \(mountPath)")
            return true
        } catch {
            Logger.shared.error("强制卸载失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 文件操作
    func listFiles(at path: String) -> Result<[FileInfo], DiskError> {
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            var files: [FileInfo] = []
            
            for item in contents {
                let fullPath = (path as NSString).appendingPathComponent(item)
                let attributes = try fileManager.attributesOfItem(atPath: fullPath)
                let type = attributes[.type] as? FileAttributeType ?? .typeUnknown
                let size = attributes[.size] as? UInt64 ?? 0
                let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                
                let fileInfo = FileInfo(
                    name: item,
                    path: fullPath,
                    isDirectory: type == .typeDirectory,
                    size: size,
                    modificationDate: modificationDate,
                    permissions: self.getPermissions(fullPath)
                )
                files.append(fileInfo)
            }
            
            return .success(files)
        } catch {
            return .failure(.listFailed(error))
        }
    }
    
    func createDirectory(at path: String) -> Result<Void, DiskError> {
        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            return .success(())
        } catch {
            return .failure(.createDirectoryFailed(error))
        }
    }
    
    func deleteItem(at path: String) -> Result<Void, DiskError> {
        do {
            try fileManager.removeItem(atPath: path)
            return .success(())
        } catch {
            return .failure(.deleteFailed(error))
        }
    }
    
    func moveItem(at source: String, to destination: String) -> Result<Void, DiskError> {
        do {
            try fileManager.moveItem(atPath: source, toPath: destination)
            return .success(())
        } catch {
            return .failure(.moveFailed(error))
        }
    }
    
    func copyItem(at source: String, to destination: String) -> Result<Void, DiskError> {
        do {
            try fileManager.copyItem(atPath: source, toPath: destination)
            return .success(())
        } catch {
            return .failure(.copyFailed(error))
        }
    }
    
    // MARK: - 磁盘信息
    func getDiskInfo(at path: String) -> Result<DiskInfo, DiskError> {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: path)
            let totalSize = attributes[.systemSize] as? UInt64 ?? 0
            let freeSize = attributes[.systemFreeSize] as? UInt64 ?? 0
            let usedSize = totalSize - freeSize
            
            let diskInfo = DiskInfo(
                totalSize: totalSize,
                usedSize: usedSize,
                freeSize: freeSize,
                filesystem: attributes[.systemNumber] as? String ?? "unknown"
            )
            
            return .success(diskInfo)
        } catch {
            return .failure(.diskInfoFailed(error))
        }
    }
    
    func isMounted(_ path: String) -> Bool {
        let mountedPaths = getMountedVolumes()
        return mountedPaths.contains { $0 == path || path.hasPrefix($0) }
    }
    
    func getMountedVolumes() -> [String] {
        let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey],
            options: []
        )
        return volumes?.map { $0.path } ?? []
    }
    
    // MARK: - 权限
    func checkPermissions(at path: String) -> Permissions {
        var permissions: Permissions = []
        
        if fileManager.isReadableFile(atPath: path) {
            permissions.insert(.read)
        }
        if fileManager.isWritableFile(atPath: path) {
            permissions.insert(.write)
        }
        if fileManager.isExecutableFile(atPath: path) {
            permissions.insert(.execute)
        }
        return permissions
    }
    
    func setPermissions(at path: String, permissions: Permissions) -> Bool {
        var mode: mode_t = 0
        if permissions.contains(.read) { mode |= S_IRUSR }
        if permissions.contains(.write) { mode |= S_IWUSR }
        if permissions.contains(.execute) { mode |= S_IXUSR }
        return chmod(path, mode) == 0
    }
    
    // MARK: - 辅助方法
    private func buildMountCommand(
        url: String,
        mountPath: String,
        credentials: [String: Any]?,
        options: [String: Any]?
    ) -> String {
        var command = ""
        
        // WebDAV - 使用 /sbin/mount_webdav
        if url.hasPrefix("https://") || url.hasPrefix("http://") {
            command = "/sbin/mount_webdav -i"
            if let creds = credentials,
               let username = creds["username"] as? String {
                command += " -u \"\(username)\""
            }
            if let creds = credentials,
               let password = creds["password"] as? String {
                command += " -p \"\(password)\""
            }
            command += " \"\(url)\" \"\(mountPath)\""
            return command
        }
        
        // SMB - 使用 mount_smbfs
        if url.hasPrefix("smb://") {
            command = "/sbin/mount_smbfs"
            if let creds = credentials,
               let username = creds["username"] as? String {
                command += " //\(username)"
                if let password = creds["password"] as? String {
                    command += ":\(password)"
                }
                let hostPath = url.replacingOccurrences(of: "smb://", with: "")
                command += "@\(hostPath)"
            } else {
                command += " \"\(url)\""
            }
            command += " \"\(mountPath)\""
            return command
        }
        
        // NFS - 使用 mount_nfs
        if url.hasPrefix("nfs://") {
            let hostPath = url.replacingOccurrences(of: "nfs://", with: "")
            command = "/sbin/mount_nfs -o resvport \"\(hostPath)\" \"\(mountPath)\""
            return command
        }
        
        // FTP 或 SFTP - 使用 curlftpfs 或 sshfs（需要安装）
        if url.hasPrefix("ftp://") || url.hasPrefix("sftp://") {
            // 提示用户安装工具
            command = "echo \"需要安装 curlftpfs 或 sshfs\""
            return command
        }
        
        // 默认
        command = "mount -t nfs \"\(url)\" \"\(mountPath)\""
        return command
    }
    
    private func executeCommand(_ command: String) throws -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        guard let output = String(data: data, encoding: .utf8) else {
            throw DiskError.commandFailed(nil)
        }
        
        if task.terminationStatus != 0 {
            throw DiskError.commandFailed(nil)
        }
        
        return output
    }
    
    private func validateMountPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        guard path.hasPrefix("/") else { return false }
        guard !path.contains("..") else { return false }
        return true
    }
    
    private func getPermissions(_ path: String) -> String {
        var permissions = ""
        if fileManager.isReadableFile(atPath: path) {
            permissions += "r"
        } else {
            permissions += "-"
        }
        if fileManager.isWritableFile(atPath: path) {
            permissions += "w"
        } else {
            permissions += "-"
        }
        if fileManager.isExecutableFile(atPath: path) {
            permissions += "x"
        } else {
            permissions += "-"
        }
        return permissions
    }
    
    func normalizePath(_ path: String) -> String {
        var normalized = path
        while normalized.hasSuffix("/") && normalized.count > 1 {
            normalized = String(normalized.dropLast())
        }
        if !normalized.hasPrefix("/") {
            normalized = "/" + normalized
        }
        let components = normalized.components(separatedBy: "/")
        var result: [String] = []
        for component in components {
            if component == ".." {
                if !result.isEmpty {
                    result.removeLast()
                }
            } else if component != "." && !component.isEmpty {
                result.append(component)
            }
        }
        return "/" + result.joined(separator: "/")
    }
    
    func joinPath(_ base: String, _ component: String) -> String {
        let basePath = normalizePath(base)
        let compPath = component.trimmingCharacters(in: .whitespaces)
        return (basePath as NSString).appendingPathComponent(compPath)
    }
}

// MARK: - 数据模型
struct DiskInfo {
    let totalSize: UInt64
    let usedSize: UInt64
    let freeSize: UInt64
    let filesystem: String
}

struct Permissions: OptionSet {
    let rawValue: Int
    static let read = Permissions(rawValue: 1 << 0)
    static let write = Permissions(rawValue: 1 << 1)
    static let execute = Permissions(rawValue: 1 << 2)
}

// MARK: - 错误
enum DiskError: Error {
    case invalidMountPath
    case alreadyMounted
    case notMounted
    case mountPointCreationFailed(Error)
    case mountFailed(String)
    case unmountFailed(Error)
    case commandFailed(Error?)
    case listFailed(Error)
    case createDirectoryFailed(Error)
    case deleteFailed(Error)
    case moveFailed(Error)
    case copyFailed(Error)
    case diskInfoFailed(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidMountPath:
            return "无效的挂载路径"
        case .alreadyMounted:
            return "目标已挂载"
        case .notMounted:
            return "未挂载"
        case .mountPointCreationFailed(let error):
            return "创建挂载点失败: \(error.localizedDescription)"
        case .mountFailed(let output):
            return "挂载失败: \(output)"
        case .unmountFailed(let error):
            return "卸载失败: \(error.localizedDescription)"
        case .commandFailed(let error):
            return "命令执行失败: \(error?.localizedDescription ?? "未知错误")"
        case .listFailed(let error):
            return "列出文件失败: \(error.localizedDescription)"
        case .createDirectoryFailed(let error):
            return "创建目录失败: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "删除失败: \(error.localizedDescription)"
        case .moveFailed(let error):
            return "移动失败: \(error.localizedDescription)"
        case .copyFailed(let error):
            return "复制失败: \(error.localizedDescription)"
        case .diskInfoFailed(let error):
            return "获取磁盘信息失败: \(error.localizedDescription)"
        }
    }
}
