//
//  TransferProgressView.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：文件上传/下载进度条视图
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

struct TransferProgressView: View {
    let fileName: String
    let progress: Double
    let isUploading: Bool
    let speed: String?
    let onCancel: (() -> Void)?
    
    @State private var isHovering: Bool = false
    @State private var animatedProgress: Double = 0
    
    private let panelWidth: CGFloat = 280
    private let progressHeight: CGFloat = 4
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: isUploading ? "arrow.up.circle" : "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(isUploading ? .orange : .blue)
                
                Text(fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
                
                if let onCancel = onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.gray.opacity(isHovering ? 0.15 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHovering = hovering
                    }
                    .help("取消传输")
                }
            }
            .padding(.bottom, 6)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: progressHeight / 2)
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: progressHeight)
                    
                    RoundedRectangle(cornerRadius: progressHeight / 2)
                        .fill(
                            LinearGradient(
                                colors: isUploading ? [.orange, .yellow] : [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * animatedProgress), height: progressHeight)
                        .animation(.easeInOut(duration: 0.3), value: animatedProgress)
                }
            }
            .frame(height: progressHeight)
            
            if let speed = speed {
                HStack {
                    Spacer()
                    Text(speed)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            animatedProgress = progress
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - 传输列表视图
struct TransferListView: View {
    @StateObject private var viewModel = TransferViewModel()
    @State private var selectedTab: TransferTab = .downloading
    
    enum TransferTab {
        case downloading, uploading, completed
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabButton(title: "下载中", isSelected: selectedTab == .downloading) {
                    selectedTab = .downloading
                }
                TabButton(title: "上传中", isSelected: selectedTab == .uploading) {
                    selectedTab = .uploading
                }
                TabButton(title: "已完成", isSelected: selectedTab == .completed) {
                    selectedTab = .completed
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 8) {
                    switch selectedTab {
                    case .downloading:
                        if viewModel.downloadingTasks.isEmpty {
                            emptyStateView(message: "没有正在下载的任务")
                        } else {
                            ForEach(viewModel.downloadingTasks) { task in
                                TransferProgressView(
                                    fileName: task.fileName,
                                    progress: task.progress,
                                    isUploading: false,
                                    speed: task.speed,
                                    onCancel: {
                                        viewModel.cancelDownload(task.id)
                                    }
                                )
                            }
                        }
                        
                    case .uploading:
                        if viewModel.uploadingTasks.isEmpty {
                            emptyStateView(message: "没有正在上传的任务")
                        } else {
                            ForEach(viewModel.uploadingTasks) { task in
                                TransferProgressView(
                                    fileName: task.fileName,
                                    progress: task.progress,
                                    isUploading: true,
                                    speed: task.speed,
                                    onCancel: {
                                        viewModel.cancelUpload(task.id)
                                    }
                                )
                            }
                        }
                        
                    case .completed:
                        if viewModel.completedTasks.isEmpty {
                            emptyStateView(message: "没有已完成的任务")
                        } else {
                            ForEach(viewModel.completedTasks) { task in
                                CompletedTransferRow(task: task)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 420, height: 400)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
    @ViewBuilder
    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

struct CompletedTransferRow: View {
    let task: TransferTask
    
    var body: some View {
        HStack {
            Image(systemName: task.isUpload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(task.isSuccess ? .green : .red)
            
            Text(task.fileName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            Text(task.isSuccess ? "✅ 完成" : "❌ 失败")
                .font(.system(size: 12))
                .foregroundColor(task.isSuccess ? .green : .red)
            
            Text(formatDate(task.completedAt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.04))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
