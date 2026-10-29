import Foundation
import Observation
import os

@Observable
@MainActor
final class TrafficMonitor {
    let store = UsageStore()
    let history = RateHistory()
    private let sampler: InterfaceSampling
    private let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "tick")
    private var previousCounters: [String: InterfaceCounters] = [:]
    private(set) var wifiRate = CategoryDelta.zero
    private(set) var iphoneRate = CategoryDelta.zero
    /// 各类别当前使用的接口 BSD 名（主页展示用）
    private(set) var interfaceByCategory: [InterfaceCategory: String] = [:]
    private var observers: [UUID: () -> Void] = [:]
    private var timer: Timer?

    init(sampler: InterfaceSampling = InterfaceSampler()) {
        self.sampler = sampler
        // 首次采样作为基线：接口计数器是"开机以来累计"，不能直接计入
        previousCounters = Self.counterMap(from: sampler.sample())
    }

    /// 全部类别的总速率
    var totalRate: CategoryDelta {
        CategoryDelta(rx: wifiRate.rx + iphoneRate.rx, tx: wifiRate.tx + iphoneRate.tx)
    }

    /// 任一模块重置后回调（外部据此重新武装告警等）
    var onReset: (() -> Void)?

    // MARK: - 观察者（UI 刷新）

    @discardableResult
    func addObserver(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() {
        observers.values.forEach { $0() }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        update(from: sampler.sample())
        logger.debug("wifiRx=\(self.store.wifi.rx, format: .decimal) wifiTx=\(self.store.wifi.tx, format: .decimal) iphoneRx=\(self.store.iphone.rx, format: .decimal) iphoneTx=\(self.store.iphone.tx, format: .decimal)")
    }

    /// 用一份新采样推进状态（测试可直接调用）
    func update(from samples: [ClassifiedSample]) {
        var categories: [String: InterfaceCategory] = [:]
        for s in samples {
            if let c = s.category {
                categories[s.name] = c
                interfaceByCategory[c] = s.name
            }
        }
        let current = Self.counterMap(from: samples)
        let deltas = TrafficMath.deltas(previous: previousCounters, current: current, categories: categories)
        store.record(deltas)
        wifiRate = deltas[.wifi] ?? .zero
        iphoneRate = deltas[.iphone] ?? .zero
        previousCounters = current
        let total = deltas.values.reduce(CategoryDelta.zero) {
            CategoryDelta(rx: $0.rx + $1.rx, tx: $0.tx + $1.tx)
        }
        history.push(RateSample(rx: total.rx, tx: total.tx))
        notifyObservers()
    }

    /// 重置指定类别（nil = 全部）的累计并重新开始计时
    func reset(_ category: InterfaceCategory? = nil) {
        store.reset(category)
        if category == nil {
            wifiRate = .zero
            iphoneRate = .zero
            history.clear()
        }
        onReset?()
    }

    private static func counterMap(from samples: [ClassifiedSample]) -> [String: InterfaceCounters] {
        Dictionary(samples.map { ($0.name, $0.counters) }, uniquingKeysWith: { first, _ in first })
    }
}
