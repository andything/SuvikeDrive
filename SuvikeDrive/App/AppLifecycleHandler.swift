//
//  AppLifecycleHandler.swift
//  SuvikeDrive
//
//  功能: 应用生命周期事件处理
//

import Cocoa

struct AppLifecycleHandler {
    
    // MARK: - 退出前检查
    static func shouldTerminate() -> NSApplication.TerminateReply {
        let mountedServers = MountManager.shared.getMountedServers()
        
        if mountedServers.isEmpty {
            print("📢 没有已挂载的服务器，直接退出")
            return .terminateNow
        }
        
        print("📢 发现 \(mountedServers.count) 个已挂载的服务器")
        
        // 获取服务器名称
        let allServers = ConfigurationManager.shared.getServers()
        var serverNames: [String] = []
        for serverID in mountedServers {
            if let config = allServers.first(where: { $0.id == serverID }) {
                serverNames.append(config.name)
            } else {
                serverNames.append(serverID)
            }
        }
        
        // 创建自定义视图
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        
        let titleLabel = NSTextField(labelWithString: "⚠️ 有服务器正在挂载中")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.frame = NSRect(x: 16, y: 168, width: 390, height: 26)
        titleLabel.textColor = NSColor.systemOrange
        containerView.addSubview(titleLabel)
        
        let hintLabel = NSTextField(labelWithString: "退出前需要先卸载以下 \(mountedServers.count) 个服务器：")
        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.frame = NSRect(x: 16, y: 145, width: 390, height: 20)
        hintLabel.textColor = NSColor.secondaryLabelColor
        containerView.addSubview(hintLabel)
        
        let serverList = serverNames.enumerated().map { "  \($0 + 1).  \($1)" }.joined(separator: "\n")
        let listLabel = NSTextField(labelWithString: serverList)
        listLabel.frame = NSRect(x: 24, y: 30, width: 370, height: 108)
        listLabel.lineBreakMode = .byWordWrapping
        listLabel.font = NSFont.systemFont(ofSize: 13)
        listLabel.textColor = NSColor.labelColor
        containerView.addSubview(listLabel)
        
        let listBackground = NSView(frame: NSRect(x: 12, y: 22, width: 395, height: 120))
        listBackground.wantsLayer = true
        listBackground.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        listBackground.layer?.cornerRadius = 8
        listBackground.layer?.borderWidth = 0.5
        listBackground.layer?.borderColor = NSColor.separatorColor.cgColor
        containerView.addSubview(listBackground)
        containerView.addSubview(listLabel)
        
        let alert = NSAlert()
        alert.messageText = ""
        alert.accessoryView = containerView
        alert.addButton(withTitle: "一键卸载并退出")
        alert.addButton(withTitle: "强制退出")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        
        if let firstButton = alert.buttons.first {
            firstButton.keyEquivalent = "\r"
        }
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            print("📢 开始卸载所有服务器...")
            let group = DispatchGroup()
            for serverID in mountedServers {
                group.enter()
                MountManager.shared.unmount(serverID: serverID, force: true) { _ in
                    group.leave()
                }
            }
            _ = group.wait(timeout: .now() + .seconds(5))
            print("📢 卸载完成，退出应用")
            return .terminateNow
            
        case .alertSecondButtonReturn:
            print("📢 强制退出")
            return .terminateNow
            
        default:
            print("📢 取消退出")
            return .terminateCancel
        }
    }
    
    // MARK: - 应用终止清理
    static func willTerminate(eventTokens: inout [SubscriptionToken]) {
        print("📢 应用即将退出")
        Logger.shared.info("应用即将退出")
        
        eventTokens.forEach { $0.unsubscribe() }
        eventTokens.removeAll()
        
        AppLifecycleManager.shared.stop()
        WatchdogProcessManager.shared.cleanup()
        
        // 尝试卸载所有已挂载的服务器（兜底）
        let mountedServers = MountManager.shared.getMountedServers()
        if !mountedServers.isEmpty {
            print("📢 正在卸载 \(mountedServers.count) 个服务器...")
            for serverID in mountedServers {
                MountManager.shared.unmount(serverID: serverID, force: true) { result in
                    switch result {
                    case .success:
                        print("✅ 已卸载: \(serverID)")
                    case .failure(let error):
                        print("⚠️ 卸载失败: \(serverID) - \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
