enum TrafficAlertTests {
    static func all() {
        offNeverFires()
        firesOnceAtThreshold()
        progressCountsFromBaseline()
        setThresholdRearmsFromNewBaseline()
        resetRebasesToCurrentTotal()
        boundaryEqualityFires()
    }

    static func offNeverFires() {
        let alert = TrafficAlert(threshold: nil)
        TestRun.expect(!alert.check(totalBytes: UInt64.max), "nil threshold never fires")
    }

    static func firesOnceAtThreshold() {
        let alert = TrafficAlert(threshold: 1_000)
        TestRun.expect(!alert.check(totalBytes: 999), "below threshold silent")
        TestRun.expect(alert.check(totalBytes: 1_200), "crossing fires")
        TestRun.expect(!alert.check(totalBytes: 5_000), "fires only once")
    }

    static func progressCountsFromBaseline() {
        let alert = TrafficAlert(threshold: 1_000, baselineBytes: 500)
        TestRun.expectEqual(alert.progress(totalBytes: 400), UInt64(0), "below baseline clamps to 0")
        TestRun.expectEqual(alert.progress(totalBytes: 1_500), UInt64(1_000), "progress = total - baseline")
    }

    static func setThresholdRearmsFromNewBaseline() {
        // 设置新阈值时从当刻流量重新起算：设置前已有的 500 不计入进度
        let alert = TrafficAlert(threshold: 1_000, baselineBytes: 500)
        TestRun.expect(!alert.check(totalBytes: 1_400), "progress 900, silent")
        alert.setThreshold(1_000, baselineBytes: 1_400)
        TestRun.expectEqual(alert.progress(totalBytes: 1_900), UInt64(500), "progress from new baseline")
        TestRun.expect(!alert.check(totalBytes: 1_900), "re-armed, below threshold")
        TestRun.expect(alert.check(totalBytes: 2_400), "crossing fires")
    }

    static func resetRebasesToCurrentTotal() {
        let alert = TrafficAlert(threshold: 1_000, baselineBytes: 0)
        _ = alert.check(totalBytes: 1_200) // 已触发
        alert.reset(baselineBytes: 1_500)
        TestRun.expectEqual(alert.progress(totalBytes: 1_500), UInt64(0), "reset re-baselines")
        TestRun.expect(!alert.check(totalBytes: 2_400), "not fired below new window")
        TestRun.expect(alert.check(totalBytes: 2_600), "fires after new progress")
    }

    static func boundaryEqualityFires() {
        let alert = TrafficAlert(threshold: 1_000)
        TestRun.expect(alert.check(totalBytes: 1_000), "equal counts as reached")
    }
}
