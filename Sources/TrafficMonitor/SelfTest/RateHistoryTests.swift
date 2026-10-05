@MainActor
enum RateHistoryTests {
    static func all() {
        pushKeepsCapacity()
        averageOverWindow()
        averageWithFewerSamples()
        clearEmpties()
        monitorFeedsHistory()
    }

    static func pushKeepsCapacity() {
        let history = RateHistory(capacity: 3)
        for i in 1...5 { history.push(RateSample(rx: UInt64(i), tx: 0)) }
        TestRun.expectEqual(history.samples.count, 3, "capacity kept")
        TestRun.expectEqual(history.samples.map(\.rx), [UInt64(3), 4, 5], "oldest dropped")
    }

    static func averageOverWindow() {
        let history = RateHistory(capacity: 10)
        for v in [UInt64(1_000), 2_000, 3_000, 4_000] { history.push(RateSample(rx: v, tx: 0)) }
        TestRun.expectEqual(history.averageRX(window: 2), UInt64(3_500), "avg last 2")
        TestRun.expectEqual(history.averageRX(window: 10), UInt64(2_500), "avg all 4")
    }

    static func averageWithFewerSamples() {
        let history = RateHistory()
        history.push(RateSample(rx: 900, tx: 0))
        TestRun.expectEqual(history.averageRX(window: 60), UInt64(900), "single-sample avg rx")
        TestRun.expectEqual(history.averageTX(window: 60), UInt64(0), "empty tx zero")
    }

    static func clearEmpties() {
        let history = RateHistory()
        history.push(RateSample(rx: 1, tx: 1))
        history.clear()
        TestRun.expect(history.samples.isEmpty, "cleared")
    }

    static func monitorFeedsHistory() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [ClassifiedSample(name: "en0", category: .wifi, counters: InterfaceCounters(rx: 0, tx: 0))])
        monitor.update(from: [ClassifiedSample(name: "en0", category: .wifi, counters: InterfaceCounters(rx: 500, tx: 250))])
        // 每个 tick 都入一条样本（空闲秒也记录，保证图表时间线连续）
        TestRun.expectEqual(monitor.history.samples.count, 2, "one sample per update")
        TestRun.expectEqual(monitor.history.samples.first, RateSample(rx: 0, tx: 0), "baseline tick is zero")
        TestRun.expectEqual(monitor.history.samples.last, RateSample(rx: 500, tx: 250), "total delta recorded")
    }
}
