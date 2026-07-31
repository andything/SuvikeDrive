//
//  FileDirectoryTreeView.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：左侧目录树视图，使用 TreeNode 按需加载子目录
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

// MARK: - 目录树视图

struct FileDirectoryTreeView: View, Equatable {
    // ✅ 改为 @ObservedObject，消除紫色警告
    @ObservedObject var viewModel: FileBrowserViewModel
    
    // ✅ 防闪：只要路径没变、树的个数没变，绝对不重绘
    static func == (lhs: FileDirectoryTreeView, rhs: FileDirectoryTreeView) -> Bool {
        lhs.viewModel.currentPath == rhs.viewModel.currentPath &&
        lhs.viewModel.treeNodes.count == rhs.viewModel.treeNodes.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.treeNodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("暂无目录")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else {
                    ForEach(viewModel.treeNodes, id: \.id) { node in
                        TreeNodeView(node: node, viewModel: viewModel)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            // 如果树还没建，就建一次
            if viewModel.treeNodes.isEmpty {
                viewModel.buildTree()
                viewModel.highlightCurrentPath()
            }
        }
        // 绝杀：切掉导致全屏闪烁的 .onReceive，只保留高亮更新
        .onReceive(viewModel.$currentPath) { _ in
            // 仅仅是更新高亮，不重建树
            viewModel.highlightCurrentPath()
        }
    }
}

// MARK: - 树节点视图（递归）

struct TreeNodeView: View {
    @ObservedObject var node: TreeNode
    @ObservedObject var viewModel: FileBrowserViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                // 展开/折叠按钮
                if node.isDirectory {
                    Button(action: {
                        // ✅ 添加平滑动画，让展开折叠更像原生
                        withAnimation(.easeInOut(duration: 0.15)) {
                            node.isExpanded.toggle()
                        }
                        // 如果展开且没有子节点，去加载
                        if node.isExpanded && node.children.isEmpty && !node.isLoading {
                            viewModel.loadChildren(for: node)
                        }
                    }) {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
                
                // 图标
                Image(systemName: node.isDirectory ? (node.isExpanded ? "folder.fill" : "folder") : "doc")
                    .font(.system(size: 13))
                    .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                
                // 名称
                Text(node.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(node.path == viewModel.currentPath ? .accentColor : .primary)
                
                Spacer()
                
                // 加载指示器
                if node.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.3)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(node.path == viewModel.currentPath ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    node.isExpanded = true
                    viewModel.selectedTreeNode = node
                    viewModel.navigateTo(path: node.path)
                }
            }
            
            // 子节点（递归）
            if node.isDirectory && node.isExpanded && !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(node.children) { child in
                        TreeNodeView(node: child, viewModel: viewModel)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
}
