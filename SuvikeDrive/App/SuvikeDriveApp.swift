//
//  SuvikeDriveApp.swift
//  SuvikeDrive
//
//  功能: 应用入口
//

import SwiftUI
import AppKit

@main
struct SuvikeDriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
    }
}
