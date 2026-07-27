//
//  EventBus.swift
//  SuvikeDrive
//
//  功能:  全局事件订阅、发布、跨模块异步通信
//        事件优先级分级调度控制（高/中/低）
//        一次性自动销毁订阅，避免内存泄漏
//        超时未消费事件自动回收处理
//        死信队列存储异常未消费事件，支持重放
//

import AppKit
import Foundation

class EventBus {
    static let shared = EventBus()
    
    private var subscribers: [String: [EventSubscription]] = [:]
    private var pendingEvents: [EventWrapper] = []
    private var deadLetterQueue: [Event] = []
    private let eventQueue = DispatchQueue(label: "com.suvikedrive.eventbus", attributes: .concurrent)
    private let processingQueue = DispatchQueue(label: "com.suvikedrive.eventbus.processing")
    private var isProcessing = false
    private var eventTimers: [String: Timer] = [:]
    private let maxPendingEvents = 1000
    private let eventTimeout: TimeInterval = 30.0
    private let deadLetterMaxSize = 100
    
    private init() {}
    
    // MARK: - 事件订阅
    @discardableResult
    func subscribe<T: Event>(
        to eventType: T.Type,
        priority: EventPriority = .medium,
        once: Bool = false,
        handler: @escaping (T) -> Void
    ) -> SubscriptionToken {
        let eventName = String(describing: eventType)
        let token = UUID().uuidString
        let subscription = EventSubscription(
            token: token,
            eventName: eventName,
            priority: priority,
            once: once,
            handler: { event in
                if let typedEvent = event as? T {
                    handler(typedEvent)
                }
            }
        )
        
        eventQueue.async(flags: .barrier) {
            if self.subscribers[eventName] == nil {
                self.subscribers[eventName] = []
            }
            self.subscribers[eventName]?.append(subscription)
        }
        
        return SubscriptionToken(token: token, eventBus: self)
    }
    
    func unsubscribe(token: SubscriptionToken) {
        // ✅ 使用 token.token 字符串，避免 token 被释放后访问
        let tokenString = token.token
        eventQueue.async(flags: .barrier) {
            for (eventName, var subscriptions) in self.subscribers {
                subscriptions.removeAll { $0.token == tokenString }
                self.subscribers[eventName] = subscriptions
            }
        }
    }
    
    // MARK: - 事件发布
    func publish(_ event: Event) {
        let _ = String(describing: type(of: event))
        
        eventQueue.async(flags: .barrier) {
            let eventWrapper = EventWrapper(event: event, timestamp: Date())
            self.pendingEvents.append(eventWrapper)
            
            // 限制待处理事件数量
            if self.pendingEvents.count > self.maxPendingEvents {
                let overflow = self.pendingEvents.removeFirst()
                self.moveToDeadLetter(overflow.event)
            }
            
            self.processEvents()
        }
    }
    
    func publishSync<T: Event>(_ event: T) {
        let eventName = String(describing: type(of: event))
        let subscribers = getSubscribers(for: eventName)
        
        for subscription in subscribers {
            subscription.handler(event)
        }
    }
    
    // MARK: - 事件处理
    private func processEvents() {
        processingQueue.async {
            guard !self.isProcessing else { return }
            self.isProcessing = true
            
            defer {
                self.isProcessing = false
            }
            
            while let eventWrapper = self.getNextEvent() {
                self.dispatchEvent(eventWrapper)
            }
        }
    }
    
    private func getNextEvent() -> EventWrapper? {
        var result: EventWrapper?
        
        eventQueue.sync {
            guard !self.pendingEvents.isEmpty else { return }
            result = self.pendingEvents.removeFirst()
        }
        
        return result
    }
    
    private func dispatchEvent(_ eventWrapper: EventWrapper) {
        let event = eventWrapper.event
        let eventName = String(describing: type(of: event))
        
        // 获取订阅者并按优先级排序
        let subscribers = getSubscribers(for: eventName)
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
        
        guard !subscribers.isEmpty else {
            // 没有订阅者，移入死信队列
            if shouldMoveToDeadLetter(event) {
                moveToDeadLetter(event)
            }
            return
        }
        
        // 分发事件
        for subscription in subscribers {
            // 执行处理
            subscription.handler(event)
            
            // 如果是一次性订阅，移除
            if subscription.once {
                removeSubscription(token: subscription.token)
            }
        }
        
        // 检查事件是否超时
        let elapsed = Date().timeIntervalSince(eventWrapper.timestamp)
        if elapsed > eventTimeout {
            Logger.shared.warning("事件处理超时: \(eventName)")
            moveToDeadLetter(event)
        }
    }
    
    private func getSubscribers(for eventName: String) -> [EventSubscription] {
        var result: [EventSubscription] = []
        
        eventQueue.sync {
            result = self.subscribers[eventName] ?? []
        }
        
        return result
    }
    
    private func removeSubscription(token: String) {
        eventQueue.async(flags: .barrier) {
            for (eventName, var subscriptions) in self.subscribers {
                subscriptions.removeAll { $0.token == token }
                self.subscribers[eventName] = subscriptions
            }
        }
    }
    
    // MARK: - 死信队列
    private func moveToDeadLetter(_ event: Event) {
        eventQueue.async(flags: .barrier) {
            self.deadLetterQueue.append(event)
            
            // 限制死信队列大小
            if self.deadLetterQueue.count > self.deadLetterMaxSize {
                self.deadLetterQueue.removeFirst()
            }
            
            Logger.shared.warning("事件移入死信队列: \(String(describing: type(of: event)))")
        }
    }
    
    private func shouldMoveToDeadLetter(_ event: Event) -> Bool {
        // 检查是否应该移入死信队列
        // 某些事件不需要死信处理
        let ignoreTypes = ["HeartbeatEvent", "PingEvent"]
        let eventName = String(describing: type(of: event))
        return !ignoreTypes.contains(eventName)
    }
    
    func replayDeadLetter() {
        eventQueue.async(flags: .barrier) {
            let events = self.deadLetterQueue
            self.deadLetterQueue.removeAll()
            
            for event in events {
                self.publish(event)
            }
            
            Logger.shared.info("重放死信队列: \(events.count)个事件")
        }
    }
    
    func clearDeadLetter() {
        eventQueue.async(flags: .barrier) {
            self.deadLetterQueue.removeAll()
            Logger.shared.info("已清空死信队列")
        }
    }
    
    func getDeadLetterCount() -> Int {
        var count = 0
        eventQueue.sync {
            count = self.deadLetterQueue.count
        }
        return count
    }
    
    func getPendingEventCount() -> Int {
        var count = 0
        eventQueue.sync {
            count = self.pendingEvents.count
        }
        return count
    }
    
    // MARK: - 清理
    func cleanup() {
        eventQueue.async(flags: .barrier) {
            // 清理过期的订阅
            for (eventName, var subscriptions) in self.subscribers {
                subscriptions.removeAll { $0.isExpired }
                self.subscribers[eventName] = subscriptions
            }
            
            // 清理待处理事件
            self.pendingEvents.removeAll()
            
            Logger.shared.debug("EventBus清理完成")
        }
    }
}

// MARK: - 辅助结构
protocol Event {
    var timestamp: Date { get }
}

extension Event {
    var timestamp: Date {
        return Date()
    }
}

enum EventPriority: Int {
    case high = 3
    case medium = 2
    case low = 1
}

class EventSubscription {
    let token: String
    let eventName: String
    let priority: EventPriority
    let once: Bool
    let handler: (Event) -> Void
    let createdAt: Date
    var isExpired: Bool = false
    
    init(token: String, eventName: String, priority: EventPriority, once: Bool, handler: @escaping (Event) -> Void) {
        self.token = token
        self.eventName = eventName
        self.priority = priority
        self.once = once
        self.handler = handler
        self.createdAt = Date()
    }
}

struct EventWrapper {
    let event: Event
    let timestamp: Date
}

// MARK: 修复 SubscriptionToken 内存管理
class SubscriptionToken {
    let token: String
    weak var eventBus: EventBus?
    private var isUnsubscribed: Bool = false  // ✅ 防止重复释放
    
    init(token: String, eventBus: EventBus) {
        self.token = token
        self.eventBus = eventBus
    }
    
    deinit {
        unsubscribe()
    }
    
    func unsubscribe() {
        guard !isUnsubscribed else { return }
        isUnsubscribed = true
        eventBus?.unsubscribe(token: self)
    }
}
