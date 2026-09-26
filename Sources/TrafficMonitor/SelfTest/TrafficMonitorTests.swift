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
        menuBarTitleShowsRates()
        updateAccumulatesTotalsAndRates()
        resetZeroesRatesAndStore()
        firstSampleIsBaselineNotCounted()
    }

    static func menuBarTitleShowsRates() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 50)])
        monitor.update(from: [sample("en0", .wifi, rx: 1_100, tx: 1_050)])
        // wifi 速率 rx=1000 tx=1000，无 iphone
        TestRun.expectEqual(monitor.menuBarTitle, "↑1.0 KB/s ↓1.0 KB/s", "menubar title")
    }

    static func updateAccumulatesTotalsAndRates() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0), sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 2_000_000, tx: 1_000_000),
                              sample("en5", .iphone, rx: 500_000, tx: 250_000)])
        TestRun.expectEqual(monitor.store.wifiRX, UInt64(2_000_000), "wifi rx total")
        TestRun.expectEqual(monitor.store.wifiTX, UInt64(1_000_000), "wifi tx total")
        TestRun.expectEqual(monitor.store.iphoneRX, UInt64(500_000), "iphone rx total")
        TestRun.expectEqual(monitor.store.iphoneTX, UInt64(250_000), "iphone tx total")
        TestRun.expectEqual(monitor.wifiRate, CategoryDelta(rx: 2_000_000, tx: 1_000_000), "wifi rate")
        TestRun.expectEqual(monitor.iphoneRate, CategoryDelta(rx: 500_000, tx: 250_000), "iphone rate")
    }

    static func resetZeroesRatesAndStore() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 100)])
        monitor.reset()
        TestRun.expectEqual(monitor.store.wifiRX, UInt64(0), "reset store")
        TestRun.expectEqual(monitor.wifiRate, CategoryDelta.zero, "reset rate")
    }

    static func firstSampleIsBaselineNotCounted() {
        // 构造时采到的"开机以来累计量"不应被计入
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: [sample("en0", .wifi, rx: 999_999_999, tx: 999_999_999)]))
        TestRun.expectEqual(monitor.store.wifiRX, UInt64(0), "baseline rx not counted")
        TestRun.expectEqual(monitor.store.wifiTX, UInt64(0), "baseline tx not counted")
    }
}
