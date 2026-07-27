//
//  AboutView.swift
//  SuvikeDrive
//
//  功能: 关于窗口
//

import SwiftUI
import AppKit

// MARK: - 胶囊按钮（带悬停效果）
struct AboutCapsuleButton: View {
    let title: String
    let action: () -> Void
    var backgroundColor: Color = Color.gray.opacity(0.12)
    var foregroundColor: Color = .primary
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(foregroundColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isHovering ? backgroundColor.opacity(1.3) : backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 主色关闭按钮（带悬停效果）
struct AboutCloseButton: View {
    let action: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text("关闭")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isHovering ? Color.accentColor.opacity(0.8) : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 自定义分割线（更明显）
struct AboutDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
            .padding(.horizontal, 40)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 14) {
            // ✅ 应用图标
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 52))
                .foregroundColor(.accentColor)
            
            // ✅ 应用名称
            Text(AppInfo.appName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // ✅ 描述
            Text(AppInfo.appDescription)
                .font(.title3)
                .foregroundColor(.secondary)
            
            // ✅ 版本信息
            Text(AppInfo.fullVersion)
                .font(.body)
                .foregroundColor(.secondary)
            
            AboutDivider()
            
            // ✅ 作者信息 - 居中
            VStack(spacing: 4) {
                Text("作者 \(AppInfo.author)")
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text("邮箱 \(AppInfo.email)")
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text("网站 \(AppInfo.website)")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            AboutDivider()
            
            // ✅ 系统信息 - 居中
            VStack(spacing: 3) {
                Text("系统版本 \(AppInfo.systemVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("处理器 \(AppInfo.processorInfo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("内存 \(AppInfo.memorySize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            AboutDivider()
            
            // ✅ 底部按钮 - 居中（带悬停效果）
            HStack(spacing: 14) {
                AboutCapsuleButton(
                    title: "帮助",
                    action: {
                        openURL(AppInfo.helpURL)
                    }
                )
                
                AboutCapsuleButton(
                    title: "访问官网",
                    action: {
                        openURL(AppInfo.websiteURL)
                    }
                )
                
                AboutCapsuleButton(
                    title: "反馈",
                    action: {
                        openURL(AppInfo.feedbackEmail)
                    }
                )
            }
            
            // ✅ 版权信息
            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // ✅ 关闭按钮 - 居中，主色胶囊样式（带悬停效果）
            AboutCloseButton(action: {
                dismiss()
            })
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    AboutView()
}
