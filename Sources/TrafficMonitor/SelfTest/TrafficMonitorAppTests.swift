import AppKit
import Foundation

/// MenuBarController 静态编排函数的自测（控制器本体自测环境不可实例化）
@MainActor
enum TrafficMonitorAppTests {
    static func all() {
        applyAlertThresholdKeepsTotalsWhenDecliningReset()
        applyAlertThresholdCountsExistingUsageWhenDecliningReset()
        applyAlertThresholdSyncResetZeroesTotalsAndBaseline()
        applyAlertThresholdKeepsTotalsWhenDisabling()
        applyAlertThresholdSettlesDialogTrafficBeforeReset()
        alertResetRequiresExplicitConfirmation()
        milestoneReachedSilentAndFrozenWithoutThreshold()
        milestoneReachedReportsCrossingsWhenArmed()
        applyAlertThresholdResyncsMilestoneOnArm()
        applyAlertThresholdSyncResetRestartsMilestoneFromOneGB()
        applyAlertThresholdLeavesMilestoneWhenDisabling()
        milestoneDoesNotBackfillGbConsumedWhileDisabled()
    }

    static func alertResetRequiresExplicitConfirmation() {
        TestRun.expect(!MenuBarController.shouldResetAlert(modalResponse: .alertFirstButtonReturn),
                       "keep totals does not reset")
        TestRun.expect(MenuBarController.shouldResetAlert(modalResponse: .alertSecondButtonReturn),
                       "explicit reset button resets")
        TestRun.expect(!MenuBarController.shouldResetAlert(modalResponse: .abort),
                       "close button does not reset")
    }

    /// 基线态：wifi 100/50 + iphone 20/10，合并总量 180
    static func makeMonitor() -> TrafficMonitor {
        let monitor = makeTestTrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 0, tx: 0),
                              TrafficMonitorTests.sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 100, tx: 50),
                              TrafficMonitorTests.sample("en5", .iphone, rx: 20, tx: 10)])
        return monitor
    }

    static func applyAlertThresholdKeepsTotalsWhenDecliningReset() {
        // 「仅设置告警」：累计保留并计入新告警进度
        let monitor = makeMonitor()
        let alert = TrafficAlert()
                MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: false,
                                              monitor: monitor, alert: alert, milestone: MilestoneTracker())
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(180), "totals kept")
        TestRun.expectEqual(alert.baselineBytes, UInt64(0), "baseline includes existing total")
        TestRun.expectEqual(alert.progress(totalBytes: 280), UInt64(280), "progress includes existing total")
        TestRun.expect(alert.threshold == MenuBarController.gigabyte, "threshold applied")
    }

    static func applyAlertThresholdCountsExistingUsageWhenDecliningReset() {
        let monitor = makeTestTrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 0, tx: 0)])
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi,
                                                          rx: MenuBarController.gigabyte, tx: 0)])
        let alert = TrafficAlert()
        let threshold = 3 * MenuBarController.gigabyte
                MenuBarController.applyAlertThreshold(threshold, syncReset: false,
                                              monitor: monitor, alert: alert, milestone: MilestoneTracker())
        let status = HomePageController.alertStrip(threshold: alert.threshold, fired: alert.fired,
                                                   progressBytes: alert.progress(totalBytes:
                                                       MenuBarController.meteredTotal(of: monitor)))
        TestRun.expectEqual(alert.threshold, threshold, "3 GB threshold stays unchanged")
        TestRun.expectEqual(alert.progress(totalBytes: MenuBarController.meteredTotal(of: monitor)),
                            MenuBarController.gigabyte, "existing 1 GB counts toward alert")
        TestRun.expectEqual(status.text, "剩 2.0GB · 已用 33%", "3 GB alert shows 1 GB used and 2 GB remaining")
    }

    static func applyAlertThresholdSyncResetZeroesTotalsAndBaseline() {
        // 「同步重置」：四项清零、基线 0，告警进度从 0 起算；
        // 速率曲线与 onReset（里程碑对齐入口）也必须同步归零
        let monitor = makeMonitor()
        let alert = TrafficAlert()
        var resetCalls = 0
        monitor.onReset = { resetCalls += 1 }
                MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                              monitor: monitor, alert: alert, milestone: MilestoneTracker())
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
                                              monitor: monitor, alert: alert, milestone: MilestoneTracker())
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(180), "totals survive disable")
        TestRun.expect(alert.threshold == nil, "threshold cleared")
    }

    static func applyAlertThresholdSettlesDialogTrafficBeforeReset() {
        // 模态弹窗期间采样定时器停摆：编排函数须先补一拍结算再重置，
        // 否则弹窗期流量会在重置后的下一拍追溯计入新周期（Issue #10）
        let sampler = FakeSampler(samples: [])
        let monitor = makeTestTrafficMonitor(sampler: sampler)
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 0, tx: 0)])
        sampler.samples = [TrafficMonitorTests.sample("en0", .wifi, rx: 90, tx: 0)] // 弹窗期 +90
        let alert = TrafficAlert()
                MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                              monitor: monitor, alert: alert, milestone: MilestoneTracker())
        sampler.samples = [TrafficMonitorTests.sample("en0", .wifi, rx: 108, tx: 0)] // 新周期 +18
        monitor.tick()
        TestRun.expectEqual(MenuBarController.meteredTotal(of: monitor), UInt64(18),
                            "dialog-period traffic settled before reset")
    }

    /// 告警未设置：越过边界也不提示，且 tracker 冻结（next 不推进）
    static func milestoneReachedSilentAndFrozenWithoutThreshold() {
        var tracker = MilestoneTracker()
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 2_500_000_000,
                                                          alertThreshold: nil,
                                                          tracker: &tracker) == nil,
                       "no threshold → milestone silent")
        TestRun.expectEqual(tracker.next, MilestoneTracker.step, "tracker frozen while alert off")
    }

    /// 告警已设置：照常按 1 GB 边界报告
    static func milestoneReachedReportsCrossingsWhenArmed() {
        var tracker = MilestoneTracker()
        tracker.resync(totalBytes: 2_500_000_000) // 对齐到 3 GB 边界
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 3_000_000_000,
                                                          alertThreshold: 10 * MenuBarController.gigabyte,
                                                          tracker: &tracker) == 3 * MenuBarController.gigabyte,
                       "armed → 3GB boundary reported")
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 3_400_000_000,
                                                          alertThreshold: 10 * MenuBarController.gigabyte,
                                                          tracker: &tracker) == nil,
                       "between boundaries silent")
    }

    /// 设置阈值（不重置）：返回的里程碑对齐到当前总量之上的第一个整 GB
    static func applyAlertThresholdResyncsMilestoneOnArm() {
        let monitor = makeMonitor() // 基线总量 180 字节
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 2_600_000_000, tx: 0)])
        var milestone = MilestoneTracker()
        _ = milestone.update(totalBytes: 1_200_000_000) // 旧状态停在 next = 2 GB
        let alert = TrafficAlert()
        guard let aligned = MenuBarController.applyAlertThreshold(5 * MenuBarController.gigabyte, syncReset: false,
                                                                  monitor: monitor, alert: alert,
                                                                  milestone: milestone) else {
            TestRun.expect(false, "arm returns aligned tracker")
            return
        }
        TestRun.expectEqual(aligned.next, 3 * MilestoneTracker.step,
                            "armed resyncs to first full GB above total")
    }

    /// 设置阈值 + 同步重置：返回的里程碑从 1 GB 重新起步
    /// （monitor 须带 GB 级旧总量：若对齐误用 reset 前旧总量，next = 3 GB，测试即挂）
    static func applyAlertThresholdSyncResetRestartsMilestoneFromOneGB() {
        let monitor = makeTestTrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 0, tx: 0)])
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 2_600_000_000, tx: 0)]) // 旧周期 2.6 GB
        var milestone = MilestoneTracker()
        milestone.resync(totalBytes: 2_600_000_000) // 旧周期已对齐：next = 3 GB
        let alert = TrafficAlert()
        guard let aligned = MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                                                  monitor: monitor, alert: alert,
                                                                  milestone: milestone) else {
            TestRun.expect(false, "sync reset returns aligned tracker")
            return
        }
        TestRun.expectEqual(aligned.next, MilestoneTracker.step, "sync reset → 1GB restart from zeroed total")
    }

    /// 关闭期间消耗的 GB 不补发：重新武装后越过旧边界静默，自新边界起恢复
    static func milestoneDoesNotBackfillGbConsumedWhileDisabled() {
        var tracker = MilestoneTracker()
        _ = tracker.update(totalBytes: 1_200_000_000) // next = 2 GB
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 5_400_000_000,
                                                          alertThreshold: nil,
                                                          tracker: &tracker) == nil,
                       "silent while disabled")
        tracker.resync(totalBytes: 5_400_000_000) // 模拟重新设置告警时的对齐 → next = 6 GB
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 5_400_000_000,
                                                          alertThreshold: MenuBarController.gigabyte,
                                                          tracker: &tracker) == nil,
                       "GB consumed while disabled not backfilled")
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 6_000_000_000,
                                                          alertThreshold: MenuBarController.gigabyte,
                                                          tracker: &tracker) == 6 * MenuBarController.gigabyte,
                       "reporting resumes at next full GB")
    }

    /// 切「关闭」：返回 nil——实例侧里程碑保持不动（observer 期间的推进不回卷）
    static func applyAlertThresholdLeavesMilestoneWhenDisabling() {
        let monitor = makeMonitor()
        var milestone = MilestoneTracker()
        milestone.resync(totalBytes: 5_500_000_000) // next = 6 GB
        let alert = TrafficAlert()
        alert.setThreshold(MenuBarController.gigabyte, baselineBytes: 0)
        let aligned = MenuBarController.applyAlertThreshold(nil, syncReset: false,
                                                            monitor: monitor, alert: alert,
                                                            milestone: milestone)
        TestRun.expect(aligned == nil, "disable returns nil (milestone untouched)")
    }
}
