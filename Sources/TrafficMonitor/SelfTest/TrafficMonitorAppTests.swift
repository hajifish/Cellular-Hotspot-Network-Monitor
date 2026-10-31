import Foundation

/// MenuBarController 静态编排函数的自测（控制器本体自测环境不可实例化）
@MainActor
enum TrafficMonitorAppTests {
    static func all() {
        applyAlertThresholdKeepsTotalsWhenDecliningReset()
        applyAlertThresholdSyncResetZeroesTotalsAndBaseline()
        applyAlertThresholdKeepsTotalsWhenDisabling()
        applyAlertThresholdSettlesDialogTrafficBeforeReset()
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
        TestRun.expect(alert.threshold == MenuBarController.gigabyte, "threshold applied")
    }

    static func applyAlertThresholdSyncResetZeroesTotalsAndBaseline() {
        // 「同步重置」：四项清零、基线 0，告警进度从 0 起算；
        // 速率曲线与 onReset（里程碑对齐入口）也必须同步归零
        let monitor = makeMonitor()
        let alert = TrafficAlert()
        var resetCalls = 0
        monitor.onReset = { resetCalls += 1 }
        MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                              monitor: monitor, alert: alert)
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(0), "store zeroed")
        TestRun.expectEqual(alert.baselineBytes, UInt64(0), "baseline zero")
        TestRun.expectEqual(alert.progress(totalBytes: 280), UInt64(280), "progress from 0")
        TestRun.expect(monitor.history.samples.isEmpty, "sync reset clears rate history")
        TestRun.expectEqual(resetCalls, 1, "sync reset notifies onReset")
    }

    static func applyAlertThresholdKeepsTotalsWhenDisabling() {
        // 守卫回归保护：bytes = nil（切「关闭」）即使 syncReset 误传 true 也不得清零累计，
        // 且既有阈值必须被清除（从有阈值起步，避免「本为 nil」的自证断言）
        let monitor = makeMonitor()
        let alert = TrafficAlert(threshold: 1_000)
        MenuBarController.applyAlertThreshold(nil, syncReset: true,
                                              monitor: monitor, alert: alert)
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(180), "totals survive disable")
        TestRun.expect(alert.threshold == nil, "threshold cleared")
    }

    static func applyAlertThresholdSettlesDialogTrafficBeforeReset() {
        // 模态弹窗期间采样定时器停摆：编排函数须先补一拍结算再重置，
        // 否则弹窗期流量会在重置后的下一拍追溯计入新周期（Issue #10）
        let sampler = FakeSampler(samples: [])
        let monitor = TrafficMonitor(sampler: sampler)
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 0, tx: 0)])
        sampler.samples = [TrafficMonitorTests.sample("en0", .wifi, rx: 90, tx: 0)] // 弹窗期 +90
        let alert = TrafficAlert()
        MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                              monitor: monitor, alert: alert)
        sampler.samples = [TrafficMonitorTests.sample("en0", .wifi, rx: 108, tx: 0)] // 新周期 +18
        monitor.tick()
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(18),
                            "dialog-period traffic settled before reset")
    }
}
