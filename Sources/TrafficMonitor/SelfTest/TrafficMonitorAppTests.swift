import Foundation

/// MenuBarController 静态编排函数的自测（控制器本体自测环境不可实例化）
@MainActor
enum TrafficMonitorAppTests {
    static func all() {
        applyAlertThresholdKeepsTotalsWhenDecliningReset()
        applyAlertThresholdSyncResetZeroesTotalsAndBaseline()
        applyAlertThresholdKeepsTotalsWhenDisabling()
    }

    /// 基线态：wifi 100/50 + iphone 20/10，合并总量 180
    static func makeMonitor() -> TrafficMonitor {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 0, tx: 0),
                              TrafficMonitorTests.sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 100, tx: 50),
                              TrafficMonitorTests.sample("en5", .iphone, rx: 20, tx: 10)])
        return monitor
    }

    static func applyAlertThresholdKeepsTotalsWhenDecliningReset() {
        // 「仅设置告警」：累计保留，基线 = 原总量，进度从当前时刻起算
        let monitor = makeMonitor()
        let alert = TrafficAlert()
        MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: false,
                                              monitor: monitor, alert: alert)
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(180), "totals kept")
        TestRun.expectEqual(alert.baselineBytes, UInt64(180), "baseline = prior total")
        TestRun.expectEqual(alert.progress(totalBytes: 280), UInt64(100), "progress counts from baseline")
    }

    static func applyAlertThresholdSyncResetZeroesTotalsAndBaseline() {
        // 「同步重置」：四项清零、基线 0，告警进度从 0 起算
        let monitor = makeMonitor()
        let alert = TrafficAlert()
        MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                              monitor: monitor, alert: alert)
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(0), "store zeroed")
        TestRun.expectEqual(alert.baselineBytes, UInt64(0), "baseline zero")
        TestRun.expectEqual(alert.progress(totalBytes: 280), UInt64(280), "progress from 0")
    }

    static func applyAlertThresholdKeepsTotalsWhenDisabling() {
        // 守卫回归保护：bytes = nil（切「关闭」）即使 syncReset 误传 true 也不得清零累计
        let monitor = makeMonitor()
        let alert = TrafficAlert()
        MenuBarController.applyAlertThreshold(nil, syncReset: true,
                                              monitor: monitor, alert: alert)
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(180), "totals survive disable")
        TestRun.expect(alert.threshold == nil, "threshold cleared")
    }
}
