//
//  FileBrowserSkeletonView.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：完整页面骨架屏，组装左侧目录树骨架和右侧文件列表骨架
//        加载时显示完整双栏布局占位效果
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

struct FileBrowserSkeletonView: View {
    @State private var sidebarWidth: CGFloat = 200
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：目录树骨架
            DirectoryTreeSkeletonView()
                .frame(width: sidebarWidth)
                .background(Color(.windowBackgroundColor))
                .overlay(
                    Divider()
                        .frame(width: 1)
                        .background(Color.gray.opacity(0.3)),
                    alignment: .trailing
                )
            
            // 右侧：文件列表骨架
            FileListSkeletonView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
        }
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - 目录树骨架（独立组件）
struct DirectoryTreeSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 模拟目录树层级结构
            let treeData: [(indent: Int, nameWidth: Int)] = [
                (0, 80), (0, 100), (1, 70), (1, 90), (1, 60),
                (0, 110), (1, 85), (2, 75), (2, 95), (0, 65),
                (1, 80), (0, 120), (1, 70), (1, 90), (0, 100)
            ]
            
            ForEach(0..<treeData.count, id: \.self) { index in
                let data = treeData[index]
                HStack(spacing: 6) {
                    // 缩进
                    let indent = CGFloat(data.indent) * 16
                    
                    // 展开箭头占位
                    RoundedRectangle(cornerRadius: 2)
                        .frame(width: 10, height: 10)
                        .foregroundColor(.gray.opacity(0.15))
                        .padding(.leading, indent)
                    
                    // 文件夹图标占位
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 16, height: 16)
                        .foregroundColor(.gray.opacity(0.15))
                    
                    // 文件夹名称占位
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: CGFloat(data.nameWidth), height: 14)
                        .foregroundColor(.gray.opacity(0.15))
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 文件列表骨架（独立组件）
struct FileListSkeletonView: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<12, id: \.self) { _ in
                HStack {
                    // 文件图标占位
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.gray.opacity(0.15))
                    
                    // 文件名占位
                    let nameWidth = CGFloat(Int.random(in: 120...200))
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: nameWidth, height: 16)
                        .foregroundColor(.gray.opacity(0.15))
                    
                    Spacer()
                    
                    // 文件大小占位
                    let sizeWidth = CGFloat(Int.random(in: 40...70))
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: sizeWidth, height: 14)
                        .foregroundColor(.gray.opacity(0.15))
                    
                    // 修改日期占位
                    let dateWidth = CGFloat(Int.random(in: 60...90))
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: dateWidth, height: 14)
                        .foregroundColor(.gray.opacity(0.15))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
#Preview {
    FileBrowserSkeletonView()
        .frame(width: 800, height: 600)
}
