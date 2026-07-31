//
//  DownloadProgressView.swift
//  SuvikeDrive
//
//  功能: 更新进度 UI
//

import SwiftUI
import AppKit

// MARK: - 更新状态枚举
enum UpdateFlowState {
    case checking
    case showLog
    case downloading
    case downloadComplete
    case installing
    case noUpdate
    case error
}

// MARK: - 按钮悬停效果
struct HoverEffectModifier: ViewModifier {
    let isProminent: Bool
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .background(
                Group {
                    if isProminent {
                        Capsule()
                            .fill(isHovering ? Color.accentColor.opacity(0.8) : Color.accentColor)
                    } else {
                        Capsule()
                            .fill(isHovering ? Color.gray.opacity(0.15) : Color.gray.opacity(0.08))
                    }
                }
            )
    }
}

extension View {
    func hoverEffectBackground(isProminent: Bool = false) -> some View {
        self.modifier(HoverEffectModifier(isProminent: isProminent))
    }
}

// MARK: - 下载进度视图
struct DownloadProgressView: View {
    @Environment(\.dismiss) var dismiss
    
    let state: UpdateFlowState
    let progress: Double
    let status: String
    let version: String?
    let releaseNotes: String?
    let size: String
    let isMandatory: Bool
    let errorMessage: String?
    
    let onDownload: (() -> Void)?
    let onInstall: (() -> Void)?
    let onCancel: (() -> Void)?
    let onDismiss: (() -> Void)?
    let onRetry: (() -> Void)?
    
    private var formattedVersion: String {
        let version = AppInfo.appVersion
        let build = AppInfo.buildNumber
        let dateStr = build.count >= 8 ? String(build.prefix(8)) : build
        return "v\(version) (\(dateStr))"
    }
    
    private var contentHeight: CGFloat {
        switch state {
        case .checking: return 200
        case .showLog: return 380
        case .downloading: return 220
        case .downloadComplete: return 200
        case .installing: return 200
        case .noUpdate: return 180
        case .error: return 200
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            appInfoBar
            Divider().padding(.horizontal, 20)
            contentView
                .padding(.horizontal, 24)
                .padding(.top, 6)
            Spacer(minLength: 6)
            actionButtonsView
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
        }
        .frame(width: 420, height: contentHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.1), radius: 10)
        )
    }
    
    private var appInfoBar: some View {
        VStack(spacing: 1) {
            Text(AppInfo.appName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Text(formattedVersion)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .checking: checkingView
        case .showLog: logView
        case .downloading: downloadingView
        case .downloadComplete: downloadCompleteView
        case .installing: installingView
        case .noUpdate: noUpdateView
        case .error: errorView
        }
    }
    
    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).scaleEffect(0.9)
            Text("正在检查更新...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(height: 70)
        .frame(maxWidth: .infinity)
    }
    
    private var logView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("版本 \(version ?? "未知")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("·")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("大小: \(size)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                if isMandatory {
                    Text("⚠️ 强制更新")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            
            Text("📝 更新日志")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 6)
            
            if let notes = releaseNotes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                )
            } else {
                Text("暂无更新日志")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var downloadingView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("正在下载更新...")
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: progress >= 0.8 ? .green : .accentColor))
                .frame(height: 5)
                .padding(.horizontal, 4)
            if progress > 0 && progress < 1 {
                HStack {
                    Text("下载中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("预计剩余: 计算中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 70)
        .frame(maxWidth: .infinity)
    }
    
    private var downloadCompleteView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("✅ 下载完成")
                    .font(.body)
                    .foregroundColor(.green)
                Spacer()
            }
            if let version = version {
                HStack {
                    Text("版本 \(version) 已就绪")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
    }
    
    // ✅ 安装视图：显示文字在中间，进度条在下方
    private var installingView: some View {
        VStack(spacing: 12) {
            Text("⏳ 正在安装更新...")
                .font(.body)
                .foregroundColor(.orange)
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 5)
                .padding(.horizontal, 4)
        }
        .frame(height: 70)
        .frame(maxWidth: .infinity)
    }
    
    private var noUpdateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text("已是最新版本")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
    }
    
    private var errorView: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.red)
            Text("❌ 更新失败")
                .font(.body)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            switch state {
            case .checking:
                Button("取消") {
                    onCancel?()
                    dismiss()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.gray.opacity(0.08)))
                .foregroundColor(.secondary)
                .font(.system(size: 13, weight: .medium))
                .hoverEffectBackground()
                
            case .showLog:
                Button("稍后") {
                    onDismiss?()
                    dismiss()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.gray.opacity(0.08)))
                .foregroundColor(.secondary)
                .font(.system(size: 13, weight: .medium))
                .hoverEffectBackground()
                Spacer()
                Button("立即下载") {
                    onDownload?()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .medium))
                .hoverEffectBackground(isProminent: true)
                
            case .downloading:
                Button("取消下载") {
                    onCancel?()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.red.opacity(0.1)))
                .foregroundColor(.red)
                .font(.system(size: 13, weight: .medium))
                
            case .downloadComplete:
                if status.contains("成功") {
                    Button("立即重启") {
                        onInstall?()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .frame(width: 100, height: 30)
                    .background(Capsule().fill(Color.green))
                    .foregroundColor(.white)
                    .font(.system(size: 13, weight: .medium))
                    .hoverEffectBackground(isProminent: true)
                } else {
                    Button("稍后安装") {
                        onDismiss?()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .frame(width: 100, height: 30)
                    .background(Capsule().fill(Color.gray.opacity(0.08)))
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))
                    .hoverEffectBackground()
                    Spacer()
                    Button("立即安装") {
                        onInstall?()
                    }
                    .buttonStyle(.plain)
                    .frame(width: 100, height: 30)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
                    .font(.system(size: 13, weight: .medium))
                    .hoverEffectBackground(isProminent: true)
                }
                
            case .installing:
                // ✅ 安装过程中不显示任何按钮
                EmptyView()
                
            case .noUpdate:
                Button("确定") {
                    onDismiss?()
                    dismiss()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .medium))
                .hoverEffectBackground(isProminent: true)
                
            case .error:
                Button("关闭") {
                    onDismiss?()
                    dismiss()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.gray.opacity(0.08)))
                .foregroundColor(.secondary)
                .font(.system(size: 13, weight: .medium))
                .hoverEffectBackground()
                Spacer()
                Button("重试") {
                    onRetry?()
                }
                .buttonStyle(.plain)
                .frame(width: 100, height: 30)
                .background(Capsule().fill(Color.accentColor))
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .medium))
                .hoverEffectBackground(isProminent: true)
            }
        }
        .frame(height: state == .installing ? 0 : 30)
    }
}

#Preview("显示更新日志") {
    DownloadProgressView(
        state: .showLog,
        progress: 0,
        status: "发现新版本 1.0.1",
        version: "1.0.1",
        releaseNotes: "SuvikeDrive v1.0.1\n\n### 修复和改进\n- 修复自动更新功能\n- 改进稳定性和性能\n- 优化网络检测",
        size: "3.2 MB",
        isMandatory: false,
        errorMessage: nil,
        onDownload: nil,
        onInstall: nil,
        onCancel: nil,
        onDismiss: nil,
        onRetry: nil
    )
}
