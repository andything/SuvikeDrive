//
//  LogManager.swift
//  SuvikeDrive
//
//  功能: 独立于 SwiftUI 视图的日志订阅管理器（为 LogContentUpdated 提供永久订阅者）
//

import Foundation

final class LogManager {
    // 单例
    static let shared = LogManager()
    
    private var token: SubscriptionToken?
    
    // 用来把日志内容传回给 UI 的回调
    var onLogContentReceived: ((String) -> Void)?
    
    private init() {
        // 私有初始化，防止外部直接实例化
    }
    
    // ✅ 核心修复：显式提供一个启动方法，保证在 AppDelegate 的准确时机绑定
    func startListening() {
        // 如果已经监听过了，就不再重复订阅
        guard token == nil else { return }
        
        token = EventBus.shared.subscribe(to: LogContentUpdated.self) { [weak self] event in
            DispatchQueue.main.async {
                // 只要收到事件，就直接通过闭包传给 UI
                self?.onLogContentReceived?(event.content)
            }
        }
        print("✅ [LogManager] 日志订阅已永久注册，永不丢失")
    }
}
