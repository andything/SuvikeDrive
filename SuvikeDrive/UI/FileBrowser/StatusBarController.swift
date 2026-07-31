//
//  StatusBarController.swift
//  SuvikeDrive
//
//  功能：仅仅是状态栏的容器，负责把 MenuBarView 挂载到菜单栏上
//

import Cocoa
import SwiftUI

final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    init() {
        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else {
            // 如果创建失败，无需崩溃，直接退出
            return
        }
        
        let icon = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "SuvikeDrive")
        button.image = icon
        button.imagePosition = .imageLeading
        button.action = #selector(togglePopover)
        button.target = self
        
        // 准备好弹窗内容（MenuBarView 是你的 UI 主入口）
        let menuView = MenuBarView()
        let hostingController = NSHostingController(rootView: menuView)
        
        popover = NSPopover()
        
        // ✅ 修复点：因为 popover 在上一行已经赋值了，强制用 ! 解包
        popover!.contentSize = NSSize(width: 320, height: 480)
        popover!.behavior = .transient
        popover!.animates = true
        popover!.contentViewController = hostingController
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        guard let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
