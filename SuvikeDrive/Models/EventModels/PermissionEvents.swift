//
//  PermissionEvents.swift
//  SuvikeDrive
//
//  功能: 系统权限申请、授权、拒绝、状态更新事件
//

import AppKit
import Foundation

struct PermissionGranted: Event {
    let permissionType: String
    let timestamp: Date
    
    init(permissionType: String) {
        self.permissionType = permissionType
        self.timestamp = Date()
    }
}

struct PermissionDenied: Event {
    let permissionType: String
    let timestamp: Date
    
    init(permissionType: String) {
        self.permissionType = permissionType
        self.timestamp = Date()
    }
}

struct PermissionRequired: Event {
    let permissionType: String
    let message: String
    let timestamp: Date
    
    init(permissionType: String, message: String) {
        self.permissionType = permissionType
        self.message = message
        self.timestamp = Date()
    }
}

struct PermissionStatusUpdated: Event {
    let permissionType: String
    let isGranted: Bool
    let timestamp: Date
    
    init(permissionType: String, isGranted: Bool) {
        self.permissionType = permissionType
        self.isGranted = isGranted
        self.timestamp = Date()
    }
}

struct RequestPermissionEvent: Event {
    let permissionType: String
    let timestamp: Date
    
    init(permissionType: String) {
        self.permissionType = permissionType
        self.timestamp = Date()
    }
}
