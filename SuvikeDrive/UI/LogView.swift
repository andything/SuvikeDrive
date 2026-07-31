//
//  LogView.swift
//  SuvikeDrive
//
//  功能:  日志查看窗口（纯 UI，通过 EventBus 接收数据）
//

import SwiftUI
import AppKit

// MARK: - 使用 AppKit 的 NSTextView 来实现日志显示
struct NativeLogView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = font
        textView.backgroundColor = .clear
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textColor = NSColor.controlTextColor
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
            if context.coordinator.shouldAutoScroll {
                nsView.contentView.scroll(to: .zero)
            }
        }
        textView.textColor = NSColor.controlTextColor
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var shouldAutoScroll: Bool = true
    }
}

// MARK: - 胶囊按钮样式
struct LogCapsuleIconButton: View {
    let icon: String
    let action: () -> Void
    var color: Color = .secondary
    var help: String? = nil
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isHovering ? Color.secondary.opacity(0.15) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 胶囊关闭按钮
struct LogCapsuleCloseButton: View {
    let action: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text("关闭")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
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

// MARK: - 自定义分割线
struct LogDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
    }
}

// MARK: - LogView（纯 UI，通过 LogManager 接收数据）
struct LogView: View {
    // MARK: - UI State
    @State private var logContent: String = ""
    @State private var filter: String = ""
    @State private var autoRefresh: Bool = true
    @State private var isRefreshing: Bool = false
    @State private var logPath: String = ""
    @State private var toastMessage: String = ""
    @State private var showToast: Bool = false
    @State private var toastColor: Color = .green
    @State private var isExporting: Bool = false
    @Environment(\.dismiss) var dismiss
    
    // MARK: - 状态管理
    @State private var isLogLoading: Bool = false
    
    // MARK: - 日志级别关键词
    private let levelKeywords = ["INFO", "ERROR", "WARNING", "DEBUG", "CRASH"]
    
    // MARK: - 筛选（纯 UI 计算）
    private var filteredLog: String {
        if filter.isEmpty {
            return logContent
        }
        
        let lines = logContent.components(separatedBy: .newlines)
        let upperFilter = filter.uppercased()
        
        if levelKeywords.contains(upperFilter) {
            return lines
                .filter { line in
                    let upperLine = line.uppercased()
                    return upperLine.contains("[\(upperFilter)]") ||
                           upperLine.contains(" \(upperFilter) ") ||
                           upperLine.hasPrefix("\(upperFilter):") ||
                           upperLine.contains(" \(upperFilter):")
                }
                .joined(separator: "\n")
        }
        
        let lowerFilter = filter.lowercased()
        return lines
            .filter { $0.lowercased().contains(lowerFilter) }
            .joined(separator: "\n")
    }
    
    private var lineCount: Int {
        logContent.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
    
    private var filteredLineCount: Int {
        filteredLog.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 工具栏（移除了标题）
            HStack {
                // 左侧留空，或者可以放一些状态信息
                Spacer()
                
                HStack(spacing: 12) {
                    if !filter.isEmpty {
                        Text("已筛选: \(filteredLineCount) 行")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Toggle("自动更新", isOn: Binding(
                        get: { self.autoRefresh },
                        set: { newValue in
                            self.autoRefresh = newValue
                            if newValue {
                                self.requestRefresh()
                                Logger.shared.onLogFileUpdated = {
                                    self.requestRefresh()
                                }
                            } else {
                                Logger.shared.onLogFileUpdated = nil
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    
                    LogCapsuleIconButton(
                        icon: "arrow.clockwise",
                        action: {
                            print("🟢 [按钮] 点击了刷新按钮！准备发送请求...")
                            
                            isRefreshing = true
                            requestRefresh()
                            isRefreshing = false
                        },
                        help: "刷新日志"
                    )
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.5) : .default, value: isRefreshing)
                    .disabled(isRefreshing)
                    .opacity(isRefreshing ? 0.5 : 1)
                    
                    LogCapsuleIconButton(
                        icon: "square.and.arrow.up",
                        action: { requestExport() },
                        help: "导出日志"
                    )
                    .disabled(isExporting)
                    .opacity(isExporting ? 0.5 : 1)
                    
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                    
                    LogCapsuleIconButton(
                        icon: "trash",
                        action: { requestClear() },
                        color: .red,
                        help: "清空日志"
                    )
                    
                    LogCapsuleCloseButton(action: { dismiss() })
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            
            LogDivider()
            
            // MARK: - 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("筛选日志... (支持 INFO, ERROR, WARNING, DEBUG, CRASH)", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                if !filter.isEmpty {
                    Button(action: { filter = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            
            LogDivider()
            
            // MARK: - 日志内容
            let displayContent = filter.isEmpty ? logContent : logContent
                .components(separatedBy: .newlines)
                .filter { $0.localizedCaseInsensitiveContains(filter) }
                .joined(separator: "\n")
            
            if displayContent.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(filter.isEmpty ? "暂无日志" : "没有匹配的日志")
                        .font(.body)
                        .foregroundColor(.secondary)
                    if !filter.isEmpty {
                        Text("提示: 输入 INFO, ERROR, WARNING, DEBUG, CRASH 按级别筛选")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            } else {
                NativeLogView(text: .constant(displayContent))
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .padding(.horizontal, 0)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            LogDivider()
            
            // MARK: - 底部状态（含 Toast 提示）
            HStack {
                if filter.isEmpty {
                    Text("共 \(lineCount) 行日志")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("共 \(lineCount) 行日志 (筛选: \(filteredLineCount) 行)")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                if isRefreshing {
                    Text("刷新中...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                if showToast {
                    HStack(spacing: 4) {
                        Image(systemName: toastColor == .green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(toastColor)
                        Text(toastMessage)
                            .font(.system(size: 12))
                            .foregroundColor(toastColor == .green ? .green : .red)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showToast)
                }
                
                if !logPath.isEmpty && !showToast {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(logPath)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
        }
        .frame(minWidth: 500, minHeight: 300)  // 设置最小尺寸
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            requestRefresh()
            LogManager.shared.onLogContentReceived = { content in
                let wasFiltering = !self.filter.isEmpty
                
                self.logContent = content
                if wasFiltering {
                    self.filter = ""
                    self.filter = " "
                }
                
                print("📢 [LogView] 内容已更新，长度: \(content.count)")
            }
            
            requestLogPath()
            
            Logger.shared.onLogFileUpdated = {
                if autoRefresh {
                    requestRefresh()
                }
            }
        }
        .onDisappear {
            LogManager.shared.onLogContentReceived = nil
            Logger.shared.onLogFileUpdated = nil
        }
    }
    
    // MARK: - 事件发送
    private func requestRefresh() {
        guard !isLogLoading else { return }
        isLogLoading = true
        print("📢 [LogView] 准备发送 LogRefreshRequested...")
        EventBus.shared.publish(LogRefreshRequested())
    }
    
    private func requestClear() {
        EventBus.shared.publish(LogClearRequested())
    }
    
    private func requestExport() {
        EventBus.shared.publish(LogExportRequested())
    }
    
    private func requestLogPath() {
        EventBus.shared.publish(LogPathRequested())
    }
    
    // MARK: - Toast 提示
    private func showToastMessage(message: String, isSuccess: Bool = true) {
        withAnimation(.easeInOut(duration: 0.3)) {
            toastMessage = message
            toastColor = isSuccess ? .green : .red
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showToast = false
            }
        }
    }
}

// MARK: - 预览
#Preview {
    LogView()
        .frame(width: 800, height: 600)  // 预览时给一个较大的尺寸
}
