enum HomePageTests {
    static func all() {
        niceMaximumRoundUp()
        durationTextFormatting()
        ratePartsSplit()
        alertStripFormatting()
        moduleRunningState()
        totalLinesFormat()
    }

    static func totalLinesFormat() {
        let lines = HomePageController.totalLines(tx: 123_400_000, rx: 567_800_000)
        TestRun.expectEqual(lines.up, "↑ 123.4 MB", "total up line")
        TestRun.expectEqual(lines.down, "↓ 567.8 MB", "total down line")
    }

    static func moduleRunningState() {
        // 运行中 = 接口在线且已有计量流量
        TestRun.expect(HomePageController.isRunning(present: true, rx: 1, tx: 0), "present with traffic runs")
        TestRun.expect(!HomePageController.isRunning(present: true, rx: 0, tx: 0), "present but zero traffic idle")
        TestRun.expect(!HomePageController.isRunning(present: false, rx: 1, tx: 1), "absent interface not running")
    }

    static func alertStripFormatting() {
        let unset = HomePageController.alertStrip(threshold: nil, fired: false, progressBytes: 100)
        TestRun.expectEqual(unset.text, "告警未设置", "unset text")
        TestRun.expect(unset.state == .unset, "unset state")

        let armed = HomePageController.alertStrip(threshold: 1_000, fired: false, progressBytes: 250)
        TestRun.expectEqual(armed.text, "剩 750B · 已用 25%", "armed shows remaining and percent")
        TestRun.expect(armed.state == .armed, "armed state")

        let fired = HomePageController.alertStrip(threshold: 1_000, fired: true, progressBytes: 5_000)
        TestRun.expectEqual(fired.text, "已触发 · 已用 100%", "fired text")
        TestRun.expect(fired.state == .fired, "fired state")
    }

    static func ratePartsSplit() {
        let parts = ByteFormat.rateParts(1_200_000)
        TestRun.expectEqual(parts.value, "1.2", "rate value part")
        TestRun.expectEqual(parts.unit, "MB/s", "rate unit part")
        let zero = ByteFormat.rateParts(0)
        TestRun.expectEqual(zero.value, "0", "zero value part")
        TestRun.expectEqual(zero.unit, "B/s", "zero unit part")
    }

    static func niceMaximumRoundUp() {
        TestRun.expectEqual(RateGraphView.niceMaximum(0), UInt64(1), "zero clamps to 1")
        TestRun.expectEqual(RateGraphView.niceMaximum(1), UInt64(1), "1 stays 1")
        TestRun.expectEqual(RateGraphView.niceMaximum(999), UInt64(1_000), "999 -> 1000")
        TestRun.expectEqual(RateGraphView.niceMaximum(1_000), UInt64(1_000), "exact stays")
        TestRun.expectEqual(RateGraphView.niceMaximum(1_001), UInt64(2_000), "1001 -> 2000")
        TestRun.expectEqual(RateGraphView.niceMaximum(5_100), UInt64(10_000), "5100 -> 10000")
    }

    static func durationTextFormatting() {
        TestRun.expectEqual(HomePageController.durationText(0), "0s", "zero seconds")
        TestRun.expectEqual(HomePageController.durationText(45), "45s", "45s")
        TestRun.expectEqual(HomePageController.durationText(90), "1m 30s", "90s")
        TestRun.expectEqual(HomePageController.durationText(3_725), "1h 2m", "3725s")
    }
}
