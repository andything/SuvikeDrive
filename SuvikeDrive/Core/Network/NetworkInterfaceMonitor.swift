//
//  NetworkInterfaceMonitor.swift
//  SuvikeDrive
//
//  功能: 读取系统网卡真实流量数据
//

import Foundation
import Darwin

class NetworkInterfaceMonitor {
    static let shared = NetworkInterfaceMonitor()
    
    // MARK: - 流量数据
    struct InterfaceTraffic {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var packetsIn: UInt64 = 0
        var packetsOut: UInt64 = 0
        var name: String = ""
    }
    
    // MARK: - 属性
    private var previousTraffic: InterfaceTraffic?
    private var downloadSpeed: Double = 0
    private var uploadSpeed: Double = 0
    private var totalDownload: UInt64 = 0
    private var totalUpload: UInt64 = 0
    private let lock = NSLock()
    private var monitorTimer: Timer?
    private var activeInterfaces: [String] = []
    private var isRunning = false
    private var lastUpdateTime: Date?
    private var updateInterval: TimeInterval = 1.0
    
    // 回调 - 在主线程触发
    var onTrafficUpdate: ((_ downloadSpeed: Double, _ uploadSpeed: Double, _ totalDownload: UInt64, _ totalUpload: UInt64) -> Void)?
    
    private init() {
        updateActiveInterfaces()
    }
    
    // MARK: - 启动/停止监控
    func startMonitoring(interval: TimeInterval = 1.0) {
        guard !isRunning else {
            return
        }
        
        stopMonitoring()
        
        self.updateInterval = interval
        previousTraffic = nil
        downloadSpeed = 0
        uploadSpeed = 0
        lastUpdateTime = Date()
        
        let initialTraffic = getTotalTrafficFromInterface()
        previousTraffic = initialTraffic
        
        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateTraffic()
        }
        
        isRunning = true
    }
    
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        isRunning = false
        lastUpdateTime = nil
    }
    
    // MARK: - 更新流量数据
    private func updateTraffic() {
        let currentTraffic = getTotalTrafficFromInterface()
        let currentTime = Date()
        
        guard let previous = previousTraffic else {
            previousTraffic = currentTraffic
            lastUpdateTime = currentTime
            return
        }
        
        let timeDiff = lastUpdateTime.map { currentTime.timeIntervalSince($0) } ?? updateInterval
        lastUpdateTime = currentTime
        
        let bytesInDiff = currentTraffic.bytesIn > previous.bytesIn ? currentTraffic.bytesIn - previous.bytesIn : 0
        let bytesOutDiff = currentTraffic.bytesOut > previous.bytesOut ? currentTraffic.bytesOut - previous.bytesOut : 0
        
        let hasTraffic = bytesInDiff > 0 || bytesOutDiff > 0
        
        if hasTraffic {
            lock.lock()
            totalDownload += bytesInDiff
            totalUpload += bytesOutDiff
            lock.unlock()
            
            downloadSpeed = Double(bytesInDiff) / timeDiff
            uploadSpeed = Double(bytesOutDiff) / timeDiff
        } else {
            downloadSpeed = 0
            uploadSpeed = 0
        }
        
        previousTraffic = currentTraffic
        
        DispatchQueue.main.async {
            if let lastSpeed = self._lastNotifiedSpeed {
                let downDiff = abs(self.downloadSpeed - lastSpeed.download)
                let upDiff = abs(self.uploadSpeed - lastSpeed.upload)
                let threshold: Double = 100
                
                if downDiff > threshold || upDiff > threshold || self.downloadSpeed == 0 || self.uploadSpeed == 0 {
                    self._lastNotifiedSpeed = (self.downloadSpeed, self.uploadSpeed)
                    self.onTrafficUpdate?(self.downloadSpeed, self.uploadSpeed, self.totalDownload, self.totalUpload)
                }
            } else {
                self._lastNotifiedSpeed = (self.downloadSpeed, self.uploadSpeed)
                self.onTrafficUpdate?(self.downloadSpeed, self.uploadSpeed, self.totalDownload, self.totalUpload)
            }
        }
    }
    
    private var _lastNotifiedSpeed: (download: Double, upload: Double)?
    
    // MARK: - 获取当前速度
    func getCurrentSpeeds() -> (download: Double, upload: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (downloadSpeed, uploadSpeed)
    }
    
    // MARK: - 获取总流量
    func getTotalTraffic() -> (download: UInt64, upload: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (totalDownload, totalUpload)
    }
    
    // MARK: - 重置统计
    func resetTrafficStats() {
        lock.lock()
        totalDownload = 0
        totalUpload = 0
        downloadSpeed = 0
        uploadSpeed = 0
        _lastNotifiedSpeed = nil
        previousTraffic = getTotalTrafficFromInterface()
        lock.unlock()
    }
    
    // MARK: - 获取活跃的网络接口
    private func updateActiveInterfaces() {
        var interfaceNames: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            return
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            
            let name = String(cString: interface.ifa_name)
            let flags = interface.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isRunning = (flags & UInt32(IFF_RUNNING)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            
            if !isLoopback && isUp && isRunning {
                interfaceNames.append(name)
            }
        }
        
        activeInterfaces = interfaceNames
    }
    
    // MARK: - 获取所有接口的总流量
    private func getTotalTrafficFromInterface() -> InterfaceTraffic {
        var total = InterfaceTraffic()
        var interfaceFound = false
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            return total
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            
            let name = String(cString: interface.ifa_name)
            let flags = interface.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isRunning = (flags & UInt32(IFF_RUNNING)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            
            guard !isLoopback && isUp && isRunning else { continue }
            
            if activeInterfaces.isEmpty || activeInterfaces.contains(name) {
                if let addr = interface.ifa_addr?.pointee {
                    if addr.sa_family == AF_LINK {
                        let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
                        if let data = data {
                            let bytesIn = UInt64(data.ifi_ibytes)
                            let bytesOut = UInt64(data.ifi_obytes)
                            
                            total.bytesIn += bytesIn
                            total.bytesOut += bytesOut
                            total.packetsIn += UInt64(data.ifi_ipackets)
                            total.packetsOut += UInt64(data.ifi_opackets)
                            if total.name.isEmpty {
                                total.name = name
                            }
                            interfaceFound = true
                        }
                    }
                }
            }
        }
        
        if !interfaceFound {
            var fallbackTotal = InterfaceTraffic()
            var ifaddr2: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddr2) == 0 else {
                return total
            }
            defer { freeifaddrs(ifaddr2) }
            
            var ptr2 = ifaddr2
            while ptr2 != nil {
                defer { ptr2 = ptr2?.pointee.ifa_next }
                
                guard let interface = ptr2?.pointee else { continue }
                
                let name = String(cString: interface.ifa_name)
                let flags = interface.ifa_flags
                let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
                let isUp = (flags & UInt32(IFF_UP)) != 0
                let isRunning = (flags & UInt32(IFF_RUNNING)) != 0
                
                guard !isLoopback && isUp && isRunning else { continue }
                
                if let addr = interface.ifa_addr?.pointee {
                    if addr.sa_family == AF_LINK {
                        let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
                        if let data = data {
                            fallbackTotal.bytesIn += UInt64(data.ifi_ibytes)
                            fallbackTotal.bytesOut += UInt64(data.ifi_obytes)
                            if fallbackTotal.name.isEmpty {
                                fallbackTotal.name = name
                            }
                        }
                    }
                }
                ptr2 = ptr2?.pointee.ifa_next
            }
            
            if fallbackTotal.bytesIn > 0 || fallbackTotal.bytesOut > 0 {
                total = fallbackTotal
            }
        }
        
        return total
    }
    
    // MARK: - 格式化工具
    func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        
        let absSpeed = abs(bytesPerSecond)
        if absSpeed >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1024 / 1024 / 1024)
        } else if absSpeed >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1024 / 1024)
        } else if absSpeed >= 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
