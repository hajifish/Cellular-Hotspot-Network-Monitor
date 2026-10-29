enum MilestoneTrackerTests {
    static func all() {
        silentBelowOneGB()
        firesAtOneGBThenTwoGB()
        reportsFirstCrossedWhenJumping()
        resyncAfterReset()
    }

    private static let gb = UInt64(1_000_000_000)

    static func silentBelowOneGB() {
        var tracker = MilestoneTracker()
        TestRun.expect(tracker.update(totalBytes: gb - 1) == nil, "below 1GB silent")
    }

    static func firesAtOneGBThenTwoGB() {
        var tracker = MilestoneTracker()
        TestRun.expectEqual(tracker.update(totalBytes: gb), gb, "1GB milestone")
        TestRun.expect(tracker.update(totalBytes: gb + 500_000_000) == nil, "between milestones silent")
        TestRun.expectEqual(tracker.update(totalBytes: 2 * gb), 2 * gb, "2GB milestone")
    }

    static func reportsFirstCrossedWhenJumping() {
        var tracker = MilestoneTracker()
        TestRun.expectEqual(tracker.update(totalBytes: 2 * gb + 500_000_000), gb, "first crossed reported")
        TestRun.expectEqual(tracker.update(totalBytes: 2 * gb + 500_000_000), 2 * gb, "second crossed next tick")
        TestRun.expect(tracker.update(totalBytes: 2 * gb + 500_000_000) == nil, "all caught up")
    }

    static func resyncAfterReset() {
        var tracker = MilestoneTracker()
        _ = tracker.update(totalBytes: 3 * gb)
        tracker.resync(totalBytes: 500_000_000) // 模块重置后总量回落
        TestRun.expect(tracker.update(totalBytes: 900_000_000) == nil, "below new boundary silent")
        TestRun.expectEqual(tracker.update(totalBytes: gb), gb, "next boundary after resync")
    }
}
