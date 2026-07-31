//
//  FileBrowserEvent.swift
//  SuvikeDrive
//  Target: SuvikeDrive
//  Module: Models - EventModels
//  功能：文件浏览器事件定义，EventBus 全局通信事件
//  Author: Andything
//  Date: 2026-07-29
//

import Foundation

// 目录刷新事件
struct FileSystemRefreshEvent: Event {
    var identifier: String { "FileSystemRefreshEvent" }
}

// 文件打开事件
struct FileOpenEvent: Event {
    var identifier: String { "FileOpenEvent" }
    let fileItem: FileInfo
}
