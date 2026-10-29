enum HomePageTests {
    static func all() {
        niceMaximumRoundUp()
        durationTextFormatting()
        ratePartsSplit()
        alertStripFormatting()
    }

    static func alertStripFormatting() {
        let unset = HomePageController.alertStrip(threshold: nil, fired: false, totalBytes: 100)
        TestRun.expectEqual(unset.text, "未设置", "unset text")
        TestRun.expect(unset.state == .unset, "unset state")

        let armed = HomePageController.alertStrip(threshold: 1_000, fired: false, totalBytes: 250)
        TestRun.expectEqual(armed.text, "剩 750B · 已用 25%", "armed shows remaining and percent")
        TestRun.expect(armed.state == .armed, "armed state")

        let fired = HomePageController.alertStrip(threshold: 1_000, fired: true, totalBytes: 5_000)
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
