//
//  EventBus.swift
//  SuvikeDrive
//
//  功能:  全局事件订阅、发布、跨模块异步通信
//        事件优先级分级调度控制（高/中/低）
//        一次性自动销毁订阅，避免内存泄漏
//        超时未消费事件自动回收处理
//        死信队列存储异常未消费事件，支持重放
//        ✅ 新增：同一订阅者实例禁止重复订阅同一事件
//        ✅ 新增：hasSubscribers 方法
//        ✅ 新增：CacheSizeChanged 延迟死信处理（多次重试）
//        ✅ 新增：publishWithoutDelay 避免递归
//

import AppKit
import Foundation

final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}

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
    
    // MARK: - 事件处理深度控制
    private var processingDepth = 0
    private let maxProcessingDepth = 10
    
    // MARK: - 调试模式
    private var isDebugMode: Bool = true
    
    // MARK: 防重复订阅索引
    private var dedupIndex: [String: String] = [:]
    
    // MARK: - 重试配置
    private let maxRetryCount = 10
    private let retryInterval: TimeInterval = 0.5
    
    private init() {}
    
    // MARK: - 检查是否有订阅者
    func hasSubscribers<T: Event>(for eventType: T.Type) -> Bool {
        let eventName = String(describing: eventType)
        return hasSubscribers(for: eventName)
    }
    
    private func hasSubscribers(for eventName: String) -> Bool {
        var count = 0
        eventQueue.sync {
            count = self.subscribers[eventName]?.count ?? 0
        }
        return count > 0
    }
    
    // MARK: - 【原有API】无订阅者绑定
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
        
        if isDebugMode {
            print("📋 [EventBus] 订阅事件: \(eventName), token: \(token.prefix(8))")
        }
        
        eventQueue.async(flags: .barrier) {
            if self.subscribers[eventName] == nil {
                self.subscribers[eventName] = []
            }
            self.subscribers[eventName]?.append(subscription)
            
            if self.isDebugMode {
                print("📋 [EventBus] 订阅完成: \(eventName), 当前订阅者: \(self.subscribers[eventName]?.count ?? 0)")
            }
        }
        
        return SubscriptionToken(token: token, eventBus: self)
    }
    
    // MARK: - 【新增API】带订阅者，自动防重复订阅
    @discardableResult
    func subscribe<T: Event>(
        _ subscriber: AnyObject,
        to eventType: T.Type,
        priority: EventPriority = .medium,
        once: Bool = false,
        handler: @escaping (T) -> Void
    ) -> SubscriptionToken {
        let eventName = String(describing: eventType)
        let subscriberKey = "\(eventName)|\(ObjectIdentifier(subscriber))"
        
        eventQueue.sync(flags: .barrier) {
            if let existToken = self.dedupIndex[subscriberKey] {
                if self.isDebugMode {
                    print("📋 [EventBus] 防重复订阅生效：\(eventName)，订阅者已存在，复用token:\(existToken.prefix(8))")
                }
                return
            }
        }
        
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
        
        if isDebugMode {
            print("📋 [EventBus] 订阅事件: \(eventName), token: \(token.prefix(8))")
        }
        
        eventQueue.async(flags: .barrier) {
            if self.subscribers[eventName] == nil {
                self.subscribers[eventName] = []
            }
            self.subscribers[eventName]?.append(subscription)
            self.dedupIndex[subscriberKey] = token
            
            if self.isDebugMode {
                print("📋 [EventBus] 订阅完成: \(eventName), 当前订阅者: \(self.subscribers[eventName]?.count ?? 0)")
            }
        }
        
        return SubscriptionToken(token: token, eventBus: self)
    }
    
    func unsubscribe(token: SubscriptionToken) {
        let tokenString = token.token
        if isDebugMode {
            print("📋 [EventBus] 取消订阅: \(tokenString.prefix(8))")
        }
        eventQueue.async(flags: .barrier) {
            for (eventName, var subscriptions) in self.subscribers {
                let removedItems = subscriptions.filter { $0.token == tokenString }
                guard !removedItems.isEmpty else { continue }
                
                subscriptions.removeAll { $0.token == tokenString }
                self.subscribers[eventName] = subscriptions
                
                let keysToRemove = self.dedupIndex.compactMap { pair -> String? in
                    pair.value == tokenString ? pair.key : nil
                }
                keysToRemove.forEach { self.dedupIndex.removeValue(forKey: $0) }
                
                if self.isDebugMode {
                    print("📋 [EventBus] 已取消订阅: \(eventName)")
                }
            }
        }
    }
    
    // MARK: - 事件发布（主入口）
    func publish(_ event: Event) {
        let eventName = String(describing: type(of: event))
        
        if isDebugMode {
            print("📋 [EventBus] 发布事件: \(eventName)")
        }
        
        let hasSubscribers = hasSubscribers(for: eventName)
        
        if isDebugMode {
            print("📋 [EventBus] 事件 \(eventName) 是否有订阅者: \(hasSubscribers)")
        }
        
        if hasSubscribers {
            // 有订阅者，直接分发
            enqueueAndProcess(event)
        } else {
            // ✅ CacheSizeChanged 和 ServerCacheSizeChanged 多次重试
            if eventName == "CacheSizeChanged" || eventName == "ServerCacheSizeChanged" {
                if isDebugMode {
                    print("📋 [EventBus] \(eventName) 无订阅者，开始重试检查 (最多 \(maxRetryCount) 次)...")
                }
                retryPublishWithDelay(event: event, eventName: eventName, retryCount: 0)
            } else {
                if isDebugMode {
                    print("⚠️ [EventBus] 没有订阅者，事件移入死信队列: \(eventName)")
                }
                moveToDeadLetter(event)
            }
        }
    }
    
    // MARK: - 带重试的延迟发布
    private func retryPublishWithDelay(event: Event, eventName: String, retryCount: Int) {
        guard retryCount < maxRetryCount else {
            if isDebugMode {
                print("⚠️ [EventBus] \(eventName) 重试 \(maxRetryCount) 次后仍无订阅者，移入死信队列")
            }
            moveToDeadLetter(event)
            return
        }
        
        // 递增延迟：0.5s, 1.0s, 1.5s, 2.0s, ...
        let delay = Double(retryCount + 1) * retryInterval
        
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            if self.hasSubscribers(for: eventName) {
                if self.isDebugMode {
                    print("📋 [EventBus] \(eventName) 订阅者已注册 (重试 \(retryCount + 1) 次)，重新发布")
                }
                self.publishWithoutDelay(event)
            } else {
                if self.isDebugMode {
                    print("📋 [EventBus] \(eventName) 仍无订阅者，\(String(format: "%.1f", delay + self.retryInterval))s 后重试 (第 \(retryCount + 1)/\(self.maxRetryCount) 次)")
                }
                self.retryPublishWithDelay(event: event, eventName: eventName, retryCount: retryCount + 1)
            }
        }
    }
    
    // MARK: - 直接入队处理（不检查订阅者）
    private func enqueueAndProcess(_ event: Event) {
        eventQueue.async(flags: .barrier) {
            let eventWrapper = EventWrapper(event: event, timestamp: Date())
            self.pendingEvents.append(eventWrapper)
            
            if self.pendingEvents.count > self.maxPendingEvents {
                let overflow = self.pendingEvents.removeFirst()
                self.moveToDeadLetter(overflow.event)
            }
            
            self.processEvents()
        }
    }
    
    // MARK: - 发布但不检查订阅者（避免递归）
    private func publishWithoutDelay(_ event: Event) {
        let eventName = String(describing: type(of: event))
        
        if isDebugMode {
            print("📋 [EventBus] 重新发布（无延迟）: \(eventName)")
        }
        
        // 直接入队处理，不再检查订阅者（避免递归）
        enqueueAndProcess(event)
    }
    
    // MARK: - 发布并忽略无订阅者
    func publishIgnoringNoSubscribers(_ event: Event) {
        let eventName = String(describing: type(of: event))
        let hasSubscribers = hasSubscribers(for: eventName)
        
        if isDebugLoggingEnabled {
            print("📡 [EventBus] 发出: \(eventName)")
        }
        
        if hasSubscribers {
            publish(event)
        }
    }
    
    // MARK: - 同步发布事件
    func publishSync<T: Event>(_ event: T) {
        let eventName = String(describing: type(of: event))
        let subscribers = getSubscribers(for: eventName)
        
        if isDebugLoggingEnabled {
            print("📡 [EventBus] 同步发出: \(eventName)")
        }
        
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
        guard processingDepth < maxProcessingDepth else {
            print("⚠️ [EventBus] 事件处理深度超过限制，跳过: \(String(describing: type(of: eventWrapper.event)))")
            return
        }
        processingDepth += 1
        defer { processingDepth -= 1 }
        
        let event = eventWrapper.event
        let eventName = String(describing: type(of: event))
        
        let subscribers = getSubscribers(for: eventName)
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
        
        if isDebugMode {
            print("📋 [EventBus] 分发事件: \(eventName), 订阅者: \(subscribers.count), 深度: \(processingDepth)")
        }
        
        guard !subscribers.isEmpty else {
            if shouldMoveToDeadLetter(event) {
                moveToDeadLetter(event)
            }
            return
        }
        
        for subscription in subscribers {
            subscription.handler(event)
            
            if subscription.once {
                removeSubscription(token: subscription.token)
            }
        }
        
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
            let keysToRemove = self.dedupIndex.compactMap { pair -> String? in
                pair.value == token ? pair.key : nil
            }
            keysToRemove.forEach { self.dedupIndex.removeValue(forKey: $0) }
        }
    }
    
    // MARK: - 死信队列
    private func moveToDeadLetter(_ event: Event) {
        let eventName = String(describing: type(of: event))
        
        eventQueue.async(flags: .barrier) {
            self.deadLetterQueue.append(event)
            
            if self.deadLetterQueue.count > self.deadLetterMaxSize {
                self.deadLetterQueue.removeFirst()
            }
            
            Logger.shared.warning("事件移入死信队列: \(eventName)")
        }
    }
    
    private func shouldMoveToDeadLetter(_ event: Event) -> Bool {
        let ignoreTypes = ["HeartbeatEvent", "PingEvent", "ConfigurationChanged"]
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
            for (eventName, var subscriptions) in self.subscribers {
                subscriptions.removeAll { $0.isExpired }
                self.subscribers[eventName] = subscriptions
            }
            
            self.pendingEvents.removeAll()
            self.dedupIndex.removeAll()
            
            Logger.shared.debug("EventBus清理完成")
        }
    }
    
    // MARK: - 调试辅助
    func getProcessingStatus() -> Bool {
        var result = false
        processingQueue.sync {
            result = self.isProcessing
        }
        return result
    }
    
    func getPendingCount() -> Int {
        var count = 0
        eventQueue.sync {
            count = self.pendingEvents.count
        }
        return count
    }
    
    func getSubscriberCount(for eventType: String) -> Int {
        var count = 0
        eventQueue.sync {
            count = self.subscribers[eventType]?.count ?? 0
        }
        return count
    }
    
    func printSubscribers() {
        eventQueue.sync {
            print("📋 [EventBus] ===== 当前订阅者 =====")
            for (eventName, subscriptions) in self.subscribers {
                print("  \(eventName): \(subscriptions.count) 个订阅")
            }
            print("📋 [EventBus] =====================")
        }
    }
    
    func printStatus() {
        print("📋 [EventBus] 状态检查:")
        print("  - 处理中: \(getProcessingStatus())")
        print("  - 待处理事件: \(getPendingCount())")
        print("  - 死信队列: \(getDeadLetterCount())")
        printSubscribers()
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

// MARK: - SubscriptionToken
class SubscriptionToken {
    let token: String
    weak var eventBus: EventBus?
    private var isUnsubscribed: Bool = false
    
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

extension EventBus {
    var isDebugLoggingEnabled: Bool {
        return Logger.shared.getLogLevel() == .debug
    }
}
