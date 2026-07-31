//
//  FileBrowserToolbar.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：顶部工具栏，提供前进后退、显示隐藏文件、查看类型、刷新、排序等操作入口
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

struct FileBrowserToolbar: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    @State private var showHiddenFiles: Bool = false
    @State private var viewMode: ViewMode = .list
    
    enum ViewMode {
        case list
        case grid
        case columns
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // ========== 左侧：导航按钮组 ==========
            // 后退按钮
            Button(action: {
                viewModel.navigateUp()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("后退")
            .disabled(viewModel.currentPath == "/")
            .opacity(viewModel.currentPath == "/" ? 0.4 : 1.0)
            
            // 前进按钮
            Button(action: {
                // TODO: 实现前进功能（需要维护导航历史）
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("前进")
            .disabled(true) // 暂时禁用，需要实现历史记录
            .opacity(0.4)
            
            // 向上按钮
            Button(action: {
                viewModel.navigateUp()
            }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("向上一级")
            .disabled(viewModel.currentPath == "/")
            .opacity(viewModel.currentPath == "/" ? 0.4 : 1.0)
            
            Divider()
                .frame(height: 20)
            
            // ========== 中间：视图切换按钮组 ==========
            // 列表视图
            Button(action: {
                viewMode = .list
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("列表视图")
            .background(viewMode == .list ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
            
            // 网格视图
            Button(action: {
                viewMode = .grid
            }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("网格视图")
            .background(viewMode == .grid ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
            
            // 分栏视图
            Button(action: {
                viewMode = .columns
            }) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("分栏视图")
            .background(viewMode == .columns ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
            
            Divider()
                .frame(height: 20)
            
            // ========== 右侧：操作按钮组 ==========
            // 显示隐藏文件
            Button(action: {
                showHiddenFiles.toggle()
                // TODO: 实现显示/隐藏文件过滤
            }) {
                Image(systemName: showHiddenFiles ? "eye" : "eye.slash")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(showHiddenFiles ? "隐藏隐藏文件" : "显示隐藏文件")
            
            // 刷新按钮
            Button(action: {
                withoutAnimation {
                    viewModel.refreshCache()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("刷新")
            
            Divider()
                .frame(height: 20)
            
            // 排序菜单
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: {
                        withoutAnimation {
                            viewModel.sortOrder = order
                        }
                    }) {
                        HStack {
                            Text(orderText(order))
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                    Text("排序")
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.borderless)
            .help("排序方式")
            
            // 更多操作菜单
            Menu {
                Button("新建文件夹") {
                    // TODO: 实现新建文件夹
                }
                Button("新建文件") {
                    // TODO: 实现新建文件
                }
                Divider()
                Button("选择全部") {
                    // TODO: 实现全选
                }
                Button("取消选择") {
                    // TODO: 实现取消全选
                }
                Divider()
                Button("在终端中打开") {
                    // TODO: 实现终端打开
                }
                Button("在Finder中打开") {
                    // TODO: 实现Finder打开
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("更多操作")
            
            Spacer()
            
            // ========== 右侧状态信息 ==========
            Text("\(viewModel.items.count) 个项目")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
        .overlay(
            Divider()
                .frame(height: 1)
                .background(Color.gray.opacity(0.2)),
            alignment: .bottom
        )
    }
    
    private func orderText(_ order: SortOrder) -> String {
        switch order {
        case .nameAsc: return "名称升序"
        case .nameDesc: return "名称降序"
        case .sizeAsc: return "大小升序"
        case .sizeDesc: return "大小降序"
        case .dateAsc: return "时间升序"
        case .dateDesc: return "时间降序"
        }
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
    return FileBrowserToolbar(viewModel: viewModel)
        .frame(height: 44)
        .padding()
}
