import Foundation
import Observation
import os

@Observable
@MainActor
final class TrafficMonitor {
    let store = UsageStore()
    private let sampler: InterfaceSampling
    private let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "tick")
    private var previousCounters: [String: InterfaceCounters] = [:]
    private(set) var wifiRate = CategoryDelta.zero
    private(set) var iphoneRate = CategoryDelta.zero
    /// 状态变化回调（UI 刷新用）
    var onChange: (() -> Void)?
    private var timer: Timer?

    init(sampler: InterfaceSampling = InterfaceSampler()) {
        self.sampler = sampler
        // 首次采样作为基线：接口计数器是"开机以来累计"，不能直接计入
        previousCounters = Self.counterMap(from: sampler.sample())
    }

    /// 菜单栏标题：总实时速率 ↑tx ↓rx
    var menuBarTitle: String {
        let tx = wifiRate.tx + iphoneRate.tx
        let rx = wifiRate.rx + iphoneRate.rx
        return "↑\(ByteFormat.rate(tx)) ↓\(ByteFormat.rate(rx))"
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        update(from: sampler.sample())
        logger.debug("wifiRx=\(self.store.wifiRX, format: .decimal) wifiTx=\(self.store.wifiTX, format: .decimal) iphoneRx=\(self.store.iphoneRX, format: .decimal) iphoneTx=\(self.store.iphoneTX, format: .decimal)")
    }

    /// 用一份新采样推进状态（测试可直接调用）
    func update(from samples: [ClassifiedSample]) {
        var categories: [String: InterfaceCategory] = [:]
        for s in samples {
            if let c = s.category { categories[s.name] = c }
        }
        let current = Self.counterMap(from: samples)
        let deltas = TrafficMath.deltas(previous: previousCounters, current: current, categories: categories)
        store.record(deltas)
        wifiRate = deltas[.wifi] ?? .zero
        iphoneRate = deltas[.iphone] ?? .zero
        previousCounters = current
        onChange?()
    }

    func reset() {
        store.reset()
        wifiRate = .zero
        iphoneRate = .zero
        onChange?()
    }

    private static func counterMap(from samples: [ClassifiedSample]) -> [String: InterfaceCounters] {
        Dictionary(samples.map { ($0.name, $0.counters) }, uniquingKeysWith: { first, _ in first })
    }
}
