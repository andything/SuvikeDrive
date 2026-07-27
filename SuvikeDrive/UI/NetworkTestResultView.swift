//
//  NetworkTestResultView.swift
//  SuvikeDrive
//
//  功能: 网络测试结果展示窗口（纯 UI）
//        数据由主程序 NetworkManager 提供
//

import SwiftUI
import AppKit

// MARK: - 自定义分割线（适配黑白模式）
struct NetworkTestDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(height: 1)
    }
}

// MARK: - 网络测试结果视图（纯 UI）
struct NetworkTestResultView: View {
    // ✅ 使用 NetworkManager 中的 NetworkTestResult
    let result: NetworkTestResult?
    let isLoading: Bool
    @Environment(\.dismiss) var dismiss
    
    @State private var showCopyToast = false
    
    private var fullResultText: String {
        guard let result = result else { return "" }
        var text = result.message + "\n\n"
        for (key, value) in result.details.sorted(by: { $0.key < $1.key }) {
            text += "\(key): \(value)\n"
        }
        return text
    }
    
    // 从完整 URL 中提取主机名（不含端口）
    private func extractHost(from urlString: String) -> String {
        var host = urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "ftp://", with: "")
            .replacingOccurrences(of: "sftp://", with: "")
            .replacingOccurrences(of: "smb://", with: "")
            .replacingOccurrences(of: "nfs://", with: "")
        
        if let colonIndex = host.lastIndex(of: ":") {
            let prefix = String(host[..<colonIndex])
            if !prefix.contains(":") || prefix.filter({ $0 == ":" }).count <= 1 {
                host = String(host[..<colonIndex])
            }
        }
        
        return host
    }
    
    private func getDisplayValue(for key: String, value: String) -> String {
        if key == "目标地址" {
            return extractHost(from: value)
        }
        return value
    }
    
    private func getTextColor(for value: String) -> Color {
        if value.contains("失败") || value.contains("错误") || value.contains("异常") {
            return .red
        } else if value.contains("成功") || value.contains("支持") || value.contains("✅") {
            return .green
        }
        return .primary
    }
    
    // ✅ 判断是否包含目录列表
    private var hasDirectoryList: Bool {
        guard let result = result else { return false }
        return result.details.keys.contains { $0.contains("目录列表") || $0.contains("📁") }
    }
    
    // ✅ 获取目录列表
    private var directoryEntries: [String] {
        guard let result = result else { return [] }
        for (key, value) in result.details {
            if key.contains("目录列表") || key.contains("📁") {
                return value.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
        }
        return []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(1.2)
                    Text("网络测试中... 请稍等")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            } else if let result = result {
                resultContent(result: result)
            }
        }
        .frame(minWidth: 420, maxWidth: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.25), value: showCopyToast)
    }
    
    @ViewBuilder
    private func resultContent(result: NetworkTestResult) -> some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(result.success ? .green : .red)
                Text(result.success ? "连接成功" : "连接失败")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                
                if showCopyToast {
                    Text("已复制")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Button(action: copyResult) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制结果")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            
            NetworkTestDivider()
            
            // ✅ 结果详情 + 目录列表
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // 主消息
                    Text(result.message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(result.success ? .green : .red)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)
                    
                    // ✅ 详细测试结果
                    ForEach(result.details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        // ✅ 目录列表单独处理，用列表展示
                        if key.contains("目录列表") || key.contains("📁") {
                            // ✅ 目录列表上方加横线
                            NetworkTestDivider()
                                .padding(.vertical, 6)
                            directoryListView(value: value)
                        } else if key.contains("总耗时") {
                            HStack(alignment: .center, spacing: 8) {
                                Text(key + ":")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                
                                Text(value)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                Text(key + ":")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                
                                Text(getDisplayValue(for: key, value: value))
                                    .font(.system(size: 13))
                                    .foregroundColor(getTextColor(for: value))
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            NetworkTestDivider()
            
            // 底部按钮
            HStack {
                // ✅ 如果有目录列表，显示条目数
                if hasDirectoryList {
                    Text("📁 \(directoryEntries.count) 个条目")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 目录列表视图
    @ViewBuilder
    private func directoryListView(value: String) -> some View {
        let entries = value.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("📁 目录列表:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(entries.count) 个条目")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if entries.isEmpty {
                Text("(空目录)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                // ✅ 用网格或列表显示
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ], alignment: .leading, spacing: 2) {
                    ForEach(entries, id: \.self) { entry in
                        HStack(spacing: 4) {
                            Image(systemName: entry.hasSuffix("/") ? "folder" : "doc")
                                .font(.system(size: 10))
                                .foregroundColor(entry.hasSuffix("/") ? .blue : .secondary)
                            Text(entry)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 0)
    }
    
    private func copyResult() {
        guard result != nil else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullResultText, forType: .string)
        
        withAnimation {
            showCopyToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyToast = false
            }
        }
    }
}

#Preview {
    let sampleDetails: [String: String] = [
        "目标地址": "https://webdav.yiqipro.com:15006",
        "DNS 解析": "成功: 183.7.146.22",
        "TCP 连接": "成功",
        "HTTP 请求": "200",
        "认证测试": "认证成功",
        "📁 目录列表": "/dav/\n/dav/Documents/\n/dav/Photos/\n/dav/Movies/\n/dav/Music/\n/dav/Backup/\n/README.md",
        "总耗时": "245.00ms"
    ]
    
    return NetworkTestResultView(
        result: NetworkTestResult(
            success: true,
            message: "✅ 连接成功！找到 6 个目录/文件",
            details: sampleDetails
        ),
        isLoading: false
    )
}
