enum HomePageTests {
    static func all() {
        niceMaximumRoundUp()
        durationTextFormatting()
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
