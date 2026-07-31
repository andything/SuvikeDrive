//
//  FileBrowserAuxiliary.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：浏览器全局工具函数、文件图标匹配、文件大小格式化、日期格式化、无动画执行封装
//        所有视图共用辅助方法统一放在此处，减少重复代码
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI

// MARK: 无动画执行代码块，规避视图切换多余动画
func withoutAnimation<T>(_ action: () -> T) -> T {
    withAnimation(.none) {
        action()
    }
}

// MARK: 根据FileInfo匹配系统SF图标名称
func getFileIconName(_ file: FileInfo) -> String {
    if file.isDirectory {
        return "folder"
    }
    let ext = file.name.components(separatedBy: ".").last?.lowercased() ?? ""
    switch ext {
    case "jpg", "jpeg", "png", "heic", "webp":
        return "photo"
    case "mp4", "mov", "mkv":
        return "video"
    case "pdf":
        return "doc.pdf"
    case "zip", "7z", "tar", "gz":
        return "archivebox"
    default:
        return "doc"
    }
}

// MARK: 文件字节大小格式化展示
func formatFileSize(_ byte: UInt64) -> String {
    guard byte > 0 else { return "0 B" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(byte))
}

// MARK: 文件修改日期格式化展示
func formatFileDate(_ date: Date?) -> String {
    guard let date = date else { return "-" }
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
