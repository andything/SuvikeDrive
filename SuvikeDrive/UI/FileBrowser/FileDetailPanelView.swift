//
//  FileDetailPanelView.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：底部文件详情面板，独立组件
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

// MARK: - 底部详情面板 (独立组件)

struct FileDetailPanelView: View {
    let file: FileInfo
    @ObservedObject var viewModel: FileBrowserViewModel
    @State private var showRenameDialog: Bool = false
    @State private var renameText: String = ""
    @State private var showDeleteConfirmation: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // 大图标
            Image(systemName: getFileIconName(file))
                .font(.system(size: 20))
                .foregroundColor(file.isDirectory ? .accentColor : .secondary)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 0) {
                // 文件名
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(file.isDirectory ? "文件夹" : "\(file.fileExtension.uppercased()) 文件")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 8)
                    
                    Text(formatFileSize(file.size))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 8)
                    
                    Text("修改: \(formatFileDate(file.modificationDate))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 同步状态
            let syncState = viewModel.getSyncState(for: file)
            HStack(spacing: 3) {
                Image(systemName: syncState.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(syncState.color)
                Text(syncState.tooltip)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(syncState.color.opacity(0.1))
            )
            
            // 操作按钮组
            HStack(spacing: 4) {
                Button(action: {
                    renameText = file.name
                    showRenameDialog = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("重命名")
                
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("删除")
                
                Divider()
                    .frame(height: 12)
                
                if !file.isDirectory {
                    Button(action: {
                        viewModel.openItem(file)
                    }) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("下载文件")
                }
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.path, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("复制路径")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 50)
        .background(Color(.windowBackgroundColor))
        .alert("重命名", isPresented: $showRenameDialog) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) { }
            Button("确定") {
                if !renameText.isEmpty {
                    viewModel.renameFile(at: file.path, newName: renameText)
                }
            }
        } message: {
            Text("请输入新的名称")
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                viewModel.deleteFile(at: file.path)
            }
        } message: {
            Text("确定要删除 \"\(file.name)\" 吗？此操作不可恢复！")
        }
    }
}

// MARK: - 文件夹详情面板

struct FolderDetailPanelView: View {
    let folder: FileInfo
    let itemCount: Int
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("文件夹")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 8)
                    
                    Text("\(itemCount) 个子项目")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 50)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Preview
#Preview {
    let cacheManager = CacheManager.shared
    let eventBus = EventBus.shared
    let viewModel = FileBrowserViewModel(
        serverID: "preview",
        cacheManager: cacheManager,
        eventBus: eventBus
    )
    
    let sampleFile = FileInfo(
        name: "DS_Store",
        path: "/DS_Store",
        isDirectory: false,
        size: 4096,
        modificationDate: Date(),
        permissions: nil,
        owner: nil,
        group: nil,
        creationDate: nil,
        lastAccessDate: nil
    )
    
    return FileDetailPanelView(file: sampleFile, viewModel: viewModel)
        .frame(width: 600, height: 50)
}

// MARK: - FileInfo 扩展
// 补充被删掉的 fileExtension 计算属性

extension FileInfo {
    var fileExtension: String {
        if isDirectory { return "" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "文件" : ext
    }
}
