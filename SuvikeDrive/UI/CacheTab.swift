//
//  CacheTab.swift
//  SuvikeDrive
//
//  功能: 缓存标签页
//

import SwiftUI

struct CacheTab: View {
    @Binding var cacheEnabled: Bool
    @Binding var cacheAutoCleanup: Bool
    @Binding var cacheMaxDiskSize: String
    @Binding var cacheMaxMemoryEntries: String
    @Binding var cachePath: String
    
    let cacheSizeOptions = ["100 MB", "200 MB", "500 MB", "1 GB", "2 GB", "5 GB", "10 GB", "无限制"]
    let cacheEntryOptions = ["50", "100", "200", "500", "1000"]
    
    var body: some View {
        Group {
            Section("缓存管理") {
                HStack {
                    Text("启用缓存")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $cacheEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: cacheEnabled) { _, newValue in
                            ConfigurationManager.shared.set(key: "cache.enabled", value: newValue)
                        }
                }
                
                HStack {
                    Text("自动清理")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $cacheAutoCleanup)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: cacheAutoCleanup) { _, newValue in
                            ConfigurationManager.shared.set(key: "cache.autoCleanup", value: newValue)
                            if newValue {
                                CacheManager.shared.refreshConfig()
                            }
                        }
                }
            }
            
            Section("缓存位置") {
                HStack {
                    Text(cachePath)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    SettingsCapsuleActionButton(
                        title: "更改...",
                        action: {
                            selectCacheDirectory()
                        }
                    )
                }
            }
            
            Section("缓存大小限制") {
                HStack {
                    Text("磁盘缓存上限")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $cacheMaxDiskSize) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                HStack {
                    Text("内存缓存条目")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $cacheMaxMemoryEntries) {
                        ForEach(cacheEntryOptions, id: \.self) { count in
                            Text(count).tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
            
            Section("缓存统计") {
                HStack {
                    Text("当前缓存大小")
                        .font(.body)
                    Spacer()
                    Text(getCacheSize())
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("内存缓存条目")
                        .font(.body)
                    Spacer()
                    Text("\(CacheManager.shared.getMemoryCacheSize())")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("磁盘缓存大小")
                        .font(.body)
                    Spacer()
                    Text(getCacheSize())
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("可用磁盘空间")
                        .font(.body)
                    Spacer()
                    Text(getFreeSpace())
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func getCacheSize() -> String {
        return CacheManager.shared.getCacheSizeFormatted()
    }
    
    private func getFreeSpace() -> String {
        let path = "/"
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: path)
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return formatBytes(freeSize.uint64Value)
            }
        } catch {
            return "0 KB"
        }
        return "0 KB"
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func selectCacheDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择缓存目录"
        panel.message = "请选择用于存储缓存的文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.level = .floating
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        let currentURL = URL(fileURLWithPath: cachePath)
        if FileManager.default.fileExists(atPath: currentURL.path) {
            panel.directoryURL = currentURL.deletingLastPathComponent()
        } else {
            panel.directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                updateCachePath(to: url)
            }
        }
    }
    
    private func updateCachePath(to url: URL) {
        let newPath: String
        if url.path.hasSuffix("/Cache") {
            newPath = url.path
        } else {
            newPath = url.appendingPathComponent("Cache").path
        }
        
        do {
            try FileManager.default.createDirectory(atPath: newPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "创建缓存目录失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        cachePath = newPath
        ConfigurationManager.shared.set(key: "cache.customPath", value: newPath)
        NotificationCenter.default.post(name: .ConfigurationChanged, object: nil)
        Logger.shared.info("缓存路径已更新: \(newPath)")
    }
}
