import Foundation

final class FakeSampler: InterfaceSampling {
    var samples: [ClassifiedSample]
    init(samples: [ClassifiedSample]) { self.samples = samples }
    func sample() -> [ClassifiedSample] { samples }
}

@MainActor
enum TrafficMonitorTests {
    static func sample(_ name: String, _ category: InterfaceCategory?, rx: UInt64, tx: UInt64) -> ClassifiedSample {
        ClassifiedSample(name: name, category: category, counters: InterfaceCounters(rx: rx, tx: tx))
    }

    static func all() {
        totalRateSumsCategories()
        updateAccumulatesTotalsAndRates()
        resetZeroesRatesAndStore()
        resetCategoryKeepsOtherCategory()
        firstSampleIsBaselineNotCounted()
        emptySampleSkipsTickKeepingBaseline()
        sleepGapKeepsTotalsButRebasesRate()
    }

    static func totalRateSumsCategories() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0), sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 1_000, tx: 500),
                              sample("en5", .iphone, rx: 200, tx: 100)])
        TestRun.expectEqual(monitor.totalRate, CategoryDelta(rx: 1_200, tx: 600), "totalRate")
    }

    static func updateAccumulatesTotalsAndRates() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0), sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 2_000_000, tx: 1_000_000),
                              sample("en5", .iphone, rx: 500_000, tx: 250_000)])
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(2_000_000), "wifi rx total")
        TestRun.expectEqual(monitor.store.wifi.tx, UInt64(1_000_000), "wifi tx total")
        TestRun.expectEqual(monitor.store.iphone.rx, UInt64(500_000), "iphone rx total")
        TestRun.expectEqual(monitor.store.iphone.tx, UInt64(250_000), "iphone tx total")
        TestRun.expectEqual(monitor.wifiRate, CategoryDelta(rx: 2_000_000, tx: 1_000_000), "wifi rate")
        TestRun.expectEqual(monitor.iphoneRate, CategoryDelta(rx: 500_000, tx: 250_000), "iphone rate")
    }

    static func resetZeroesRatesAndStore() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 100)])
        monitor.reset()
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(0), "reset store")
        TestRun.expectEqual(monitor.wifiRate, CategoryDelta.zero, "reset rate")
    }

    static func resetCategoryKeepsOtherCategory() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0), sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 100),
                              sample("en5", .iphone, rx: 7000, tx: 300)])
        var resetCalls = 0
        monitor.onReset = { resetCalls += 1 }
        monitor.reset(.wifi)
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(0), "wifi reset")
        TestRun.expectEqual(monitor.store.iphone.rx, UInt64(7000), "iphone kept")
        TestRun.expectEqual(resetCalls, 1, "onReset notified")
    }

    static func firstSampleIsBaselineNotCounted() {
        // 构造时采到的"开机以来累计量"不应被计入
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: [sample("en0", .wifi, rx: 999_999_999, tx: 999_999_999)]))
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(0), "baseline rx not counted")
        TestRun.expectEqual(monitor.store.wifi.tx, UInt64(0), "baseline tx not counted")
    }

    static func emptySampleSkipsTickKeepingBaseline() {
        // 采样失败（空结果）：该拍整体跳过，基线保留，下一拍照常计差
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 100)])
        monitor.update(from: []) // 采样失败
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(100), "totals frozen during failure")
        monitor.update(from: [sample("en0", .wifi, rx: 300, tx: 300)])
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(300), "delta counted vs pre-failure baseline")
        TestRun.expectEqual(monitor.wifiRate, CategoryDelta(rx: 200, tx: 200), "rate resumes normally")
    }

    static func sleepGapKeepsTotalsButRebasesRate() {
        // 休眠/唤醒：跨大间隔的一拍把休眠期真实流量计入累计，但速率按重新基线记 0（避免假尖峰）
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0)], at: Date())
        monitor.update(from: [sample("en0", .wifi, rx: 5_000_000, tx: 0)], at: Date().addingTimeInterval(1))
        monitor.update(from: [sample("en0", .wifi, rx: 6_000_000, tx: 0)], at: Date().addingTimeInterval(60))
        TestRun.expectEqual(monitor.store.wifi.rx, UInt64(6_000_000), "totals include sleep-period traffic")
        TestRun.expectEqual(monitor.wifiRate, CategoryDelta.zero, "rate rebased after gap")
        TestRun.expectEqual(monitor.history.samples.last, RateSample(rx: 0, tx: 0), "history rebased")
    }
}
