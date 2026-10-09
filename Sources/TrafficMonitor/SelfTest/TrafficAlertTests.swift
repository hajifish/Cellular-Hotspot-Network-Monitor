enum TrafficAlertTests {
    static func all() {
        offNeverFires()
        firesOnceAtThreshold()
        setThresholdRearms()
        resetRearms()
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

    static func setThresholdRearms() {
        let alert = TrafficAlert(threshold: 1_000)
        _ = alert.check(totalBytes: 1_100)
        alert.setThreshold(2_000)
        TestRun.expect(alert.check(totalBytes: 2_100), "new threshold rearms")
        TestRun.expect(!alert.check(totalBytes: 3_000), "still once per threshold")
    }

    static func resetRearms() {
        let alert = TrafficAlert(threshold: 500)
        _ = alert.check(totalBytes: 600)
        alert.reset()
        TestRun.expect(alert.check(totalBytes: 700), "reset rearms")
    }

    static func boundaryEqualityFires() {
        let alert = TrafficAlert(threshold: 1_000)
        TestRun.expect(alert.check(totalBytes: 1_000), "equal counts as reached")
    }
}
