//
//  CacheTab.swift
//  SuvikeDrive
//
//  功能: 缓存标签页 (全 EventBus 通信)
//

import SwiftUI
import Combine

struct CacheTab: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    // UI 状态
    @State private var cacheSizeText: String = "计算中..."
    @State private var memoryCacheSizeText: String = "0"
    @State private var serverCacheSizes: [String: String] = [:]
    
    // 生命周期管理
    @State private var isViewLoaded = false
    @State private var isDeallocating = false
    @State private var cachedMountedServers: [String] = []
    
    // ✅ EventBus 订阅
    @State private var eventTokens: [SubscriptionToken] = []
    
    private let menuWidth: CGFloat = 130
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ========== 缓存管理 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleView(label: "启用缓存", isOn: $viewModel.cacheEnabled) { newValue in
                        ConfigurationManager.shared.set(key: "cache.enabled", value: newValue)
                        CacheManager.shared.refreshConfig()
                        EventBus.shared.publish(ConfigurationChanged(key: "cache.enabled", oldValue: nil, newValue: newValue))
                    }
                    
                    Divider()
                    
                    ToggleView(label: "自动清理", isOn: $viewModel.cacheAutoCleanup) { newValue in
                        ConfigurationManager.shared.set(key: "cache.autoCleanup", value: newValue)
                        if newValue {
                            CacheManager.shared.refreshConfig()
                        }
                        EventBus.shared.publish(ConfigurationChanged(key: "cache.autoCleanup", oldValue: nil, newValue: newValue))
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "gear", title: "缓存管理")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // ========== 缓存位置 ==========
            GroupBox {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    
                    Text(viewModel.cachePath)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    SettingsCapsuleActionButton(
                        title: "更改",
                        action: {
                            viewModel.selectCacheDirectory()
                        }
                    )
                    
                    SettingsCapsuleActionButton(
                        title: "重置",
                        action: {
                            viewModel.resetCachePath()
                        }
                    )
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "location", title: "缓存位置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 大小限制 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsMenuPicker(
                        label: "磁盘缓存上限",
                        selection: $viewModel.cacheMaxDiskSize,
                        options: viewModel.cacheSizeOptions,
                        formatter: { $0 },
                        width: menuWidth
                    )
                    
                    Divider()
                    
                    SettingsMenuPicker(
                        label: "内存缓存条目",
                        selection: $viewModel.cacheMaxMemoryEntries,
                        options: viewModel.cacheEntryOptions,
                        formatter: { $0 },
                        width: menuWidth
                    )
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "square.resize", title: "大小限制")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 过期时间 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsMenuPicker(
                        label: "传输缓存保留",
                        selection: $viewModel.cacheTTL,
                        options: viewModel.cacheTTLOptions,
                        formatter: { $0 },
                        width: menuWidth
                    )
                    
                    Divider()
                    
                    SettingsMenuPicker(
                        label: "文件列表缓存",
                        selection: $viewModel.cacheFileListTTL,
                        options: viewModel.fileListTTLOptions,
                        formatter: { $0 },
                        width: menuWidth
                    )
                    
                    Divider()
                    
                    SettingsMenuPicker(
                        label: "WebDAV文件缓存",
                        selection: $viewModel.cacheWebDAVTTL,
                        options: viewModel.webDAVTTLOptions,
                        formatter: { $0 },
                        width: menuWidth
                    )
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "clock", title: "过期时间")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 服务器缓存 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if cachedMountedServers.isEmpty {
                        HStack {
                            Text("暂无挂载的服务器")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(cachedMountedServers, id: \.self) { serverName in
                            HStack {
                                Text(serverName)
                                    .font(.system(size: 13))
                                    .padding(.leading, 4)
                                    .lineLimit(1)
                                Spacer()
                                Text(serverCacheSizes[serverName] ?? "计算中...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                SettingsCapsuleActionButton(
                                    title: "清除",
                                    action: {
                                        viewModel.clearCache(for: serverName)
                                    },
                                    backgroundColor: Color.red.opacity(0.15),
                                    foregroundColor: .red
                                )
                            }
                            if serverName != cachedMountedServers.last {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "server.rack", title: "服务器缓存")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // ========== 缓存统计 ==========
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("当前缓存大小")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Text(cacheSizeText)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("内存缓存条目")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Text(memoryCacheSizeText)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("磁盘缓存大小")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Text(cacheSizeText)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("可用磁盘空间")
                            .font(.system(size: 13))
                            .padding(.leading, 4)
                        Spacer()
                        Text(viewModel.getFreeSpace())
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                LabelView(icon: "chart.bar", title: "缓存统计")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .onAppear {
            guard !isViewLoaded else { return }
            isViewLoaded = true
            isDeallocating = false
            
            // 加载服务器列表
            refreshMountedServers()
            
            // ✅ 直接订阅 EventBus
            setupEventBusListeners()
            
            // 加载初始数据
            loadInitialData()
        }
        .onDisappear {
            isDeallocating = true
            
            // ✅ 取消所有 EventBus 订阅
            eventTokens.forEach { $0.unsubscribe() }
            eventTokens.removeAll()
            
            isViewLoaded = false
            cachedMountedServers.removeAll()
        }
    }
    
    // MARK: - 刷新服务器列表
    private func refreshMountedServers() {
        let servers = viewModel.mountedServers
        cachedMountedServers = servers
        print("📋 [CacheTab] 刷新服务器列表: \(servers)")
    }
    
    // MARK: - 加载初始数据
    private func loadInitialData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let size = CacheManager.shared.getCacheSizeFormatted()
            let memCount = CacheManager.shared.getMemoryCacheSize()
            
            var serverSizes: [String: String] = [:]
            for serverName in self.cachedMountedServers {
                let size = self.viewModel.getCacheSize(for: serverName)
                serverSizes[serverName] = size
            }
            
            DispatchQueue.main.async {
                guard !self.isDeallocating else { return }
                self.cacheSizeText = size
                self.memoryCacheSizeText = "\(memCount)"
                self.serverCacheSizes = serverSizes
                print("📋 [CacheTab] 初始加载完成: cacheSize=\(size), memoryCount=\(memCount)")
            }
        }
    }
    
    // MARK: - 加载服务器缓存大小
    private func loadAllServerCacheSizesInBackground() {
        var serverSizes: [String: String] = [:]
        for serverName in cachedMountedServers {
            let size = viewModel.getCacheSize(for: serverName)
            serverSizes[serverName] = size
        }
        DispatchQueue.main.async {
            guard !self.isDeallocating else { return }
            self.serverCacheSizes = serverSizes
            print("📋 [CacheTab] 服务器缓存大小已更新: \(serverSizes)")
        }
    }
    
    // MARK: - ✅ EventBus 监听
    private func setupEventBusListeners() {
        // 订阅总缓存大小变化
        let sizeToken = EventBus.shared.subscribe(
            to: CacheSizeChanged.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                self.cacheSizeText = event.formattedSize
                // ✅ 同时更新内存缓存条目
                self.memoryCacheSizeText = "\(CacheManager.shared.getMemoryCacheSize())"
            }
        }
        eventTokens.append(sizeToken)
        
        // 订阅单个服务器缓存大小变化
        let serverSizeToken = EventBus.shared.subscribe(
            to: ServerCacheSizeChanged.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                print("📋 [CacheTab] 收到服务器缓存事件: \(event.serverName) = \(event.formattedSize)")
                self.serverCacheSizes[event.serverName] = event.formattedSize
            }
        }
        eventTokens.append(serverSizeToken)
        
        // 订阅缓存清除事件
        let clearToken = EventBus.shared.subscribe(
            to: CacheCleared.self,
            priority: .medium
        ) { _ in
            DispatchQueue.main.async {
                self.cacheSizeText = "0 KB"
                self.memoryCacheSizeText = "0"
                self.loadAllServerCacheSizesInBackground()
            }
        }
        eventTokens.append(clearToken)
        
        // ✅ 订阅挂载完成事件 - 刷新服务器列表
        let mountToken = EventBus.shared.subscribe(
            to: MountCompleted.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                // 通过 serverID 查找服务器名称
                let servers = ConfigurationManager.shared.getServers()
                let serverName = servers.first(where: { $0.id == event.serverID })?.name ?? event.serverID
                print("📋 [CacheTab] 收到挂载完成事件: \(event.serverID), \(serverName)")
                // 刷新服务器列表
                self.refreshMountedServers()
                // 重新加载所有服务器缓存大小
                self.loadAllServerCacheSizesInBackground()
                // 刷新总缓存大小
                self.cacheSizeText = CacheManager.shared.getCacheSizeFormatted()
                // ✅ 更新内存缓存条目
                self.memoryCacheSizeText = "\(CacheManager.shared.getMemoryCacheSize())"
            }
        }
        eventTokens.append(mountToken)
        
        // ✅ 订阅卸载完成事件 - 刷新服务器列表
        let unmountToken = EventBus.shared.subscribe(
            to: UnmountCompleted.self,
            priority: .medium
        ) { event in
            DispatchQueue.main.async {
                print("📋 [CacheTab] 收到卸载完成事件: \(event.serverID)")
                // 刷新服务器列表
                self.refreshMountedServers()
                // 重新加载所有服务器缓存大小
                self.loadAllServerCacheSizesInBackground()
                // 刷新总缓存大小
                self.cacheSizeText = CacheManager.shared.getCacheSizeFormatted()
                // ✅ 更新内存缓存条目
                self.memoryCacheSizeText = "\(CacheManager.shared.getMemoryCacheSize())"
            }
        }
        eventTokens.append(unmountToken)
    }
}
