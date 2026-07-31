//
//  FileBrowserPathBar.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：顶部路径导航栏，渲染面包屑路径，点击分段快速跳转上层目录
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

struct FileBrowserPathBar: View {
    @ObservedObject var viewModel: FileBrowserViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing:6) {
                Button("根目录") {
                    viewModel.navigateTo(path: "/")
                }
                Text("›")
                pathSegmentsView
            }
            .padding(.horizontal,8)
        }
        .frame(height:36)
        .background(Color.gray.opacity(0.1))
    }
    
    @ViewBuilder
    private var pathSegmentsView: some View {
        let segments = viewModel.currentPath.components(separatedBy: "/").filter{!$0.isEmpty}
        ForEach(segments.indices, id:\.self) { idx in
            let fullPath = "/" + segments[0...idx].joined(separator:"/")
            Button(segments[idx]) {
                viewModel.navigateTo(path: fullPath)
            }
            if idx != segments.count-1 {
                Text("›")
            }
        }
    }
}
