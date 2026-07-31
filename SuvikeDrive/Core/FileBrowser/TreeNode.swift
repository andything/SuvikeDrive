//
//  TreeNode.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：目录树节点模型，支持按需加载子目录
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI
import Combine

class TreeNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    @Published var children: [TreeNode] = []
    @Published var isExpanded: Bool = false
    @Published var isLoading: Bool = false
    weak var parent: TreeNode?
    
    init(name: String, path: String, isDirectory: Bool = true) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}
