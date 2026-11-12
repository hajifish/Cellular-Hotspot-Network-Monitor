enum MilestoneTrackerTests {
    static func all() {
        checkpointTiersMatchTable()
        updateSequenceReportsEachCheckpointOnce()
        jumpCatchesUpOneCheckpointPerTick()
        crossingThresholdSilencesRemainingCheckpoints()
        armSkipsPassedCheckpointsWithoutBackfill()
        armFromZeroReportsFirstCheckpoint()
    }

    /// 冲线收官：一拍直接冲过阈值（小阈值 + 快链路常态）时剩余检查点不得补发
    /// 过期倒计时；冲线前的多检查点追平不受影响
    static func crossingThresholdSilencesRemainingCheckpoints() {
        var tracker = MilestoneTracker()
        tracker.arm(thresholdBytes: 20 * gb, progressBytes: 0)
        TestRun.expect(tracker.update(progressBytes: 21 * gb) == nil,
                       "jump past threshold in one tick → no stale countdown")
        TestRun.expect(tracker.next == nil, "remaining checkpoints exhausted at cap")

        var catching = MilestoneTracker()
        catching.arm(thresholdBytes: 20 * gb, progressBytes: 0)
        TestRun.expectEqual(catching.update(progressBytes: 19_500 * mb), 16 * gb,
                            "below cap catch-up still reports")
        TestRun.expect(catching.update(progressBytes: 21 * gb) == nil,
                       "cap crossed later → remaining 18/19/19.8G swallowed")
        TestRun.expect(catching.next == nil, "nothing left after cap")
    }

    private static let gb = UInt64(1_000_000_000)
    private static let mb = UInt64(1_000_000)

    /// 档位表：期望值由三档规格手工推得（比例 × 阈值四舍五入），不用被测代码现算
    static func checkpointTiersMatchTable() {
        TestRun.expectEqual(MilestoneTracker.checkpoints(forThreshold: 500 * mb),
                            [250 * mb, 450 * mb], "T < 1GB → 50%/90%")
        TestRun.expectEqual(MilestoneTracker.checkpoints(forThreshold: gb),
                            [500 * mb, 800 * mb, 950 * mb], "1GB ≤ T < 5GB → 50/80/95%")
        TestRun.expectEqual(MilestoneTracker.checkpoints(forThreshold: 3 * gb),
                            [1_500 * mb, 2_400 * mb, 2_850 * mb], "3GB → 1.5G/2.4G/2.85G")
        TestRun.expectEqual(MilestoneTracker.checkpoints(forThreshold: 5 * gb),
                            [4 * gb, 4_500 * mb, 4_750 * mb, 4_950 * mb], "T ≥ 5GB → 80/90/95/99%")
        TestRun.expectEqual(MilestoneTracker.checkpoints(forThreshold: 20 * gb),
                            [16 * gb, 18 * gb, 19 * gb, 19_800 * mb], "20GB → 16G/18G/19G/19.8G")
        TestRun.expectEqual(MilestoneTracker.checkpoints(forThreshold: 300 * mb),
                            [150 * mb, 270 * mb], "自定义 300MB → 50%/90%")
    }

    /// 20GB 阈值逐点越过：16G 报、16.5G 静、18G 报、19G 报、19.8G 报、20G 及以后静
    /// （100% 不在检查点表内，到阈值那一下归 TrafficAlert）
    static func updateSequenceReportsEachCheckpointOnce() {
        var tracker = MilestoneTracker()
        tracker.arm(thresholdBytes: 20 * gb, progressBytes: 0)
        TestRun.expectEqual(tracker.update(progressBytes: 16 * gb), 16 * gb, "80% checkpoint reported")
        TestRun.expect(tracker.update(progressBytes: 16_500 * mb) == nil, "between checkpoints silent")
        TestRun.expectEqual(tracker.update(progressBytes: 18 * gb), 18 * gb, "90% checkpoint reported")
        TestRun.expectEqual(tracker.update(progressBytes: 19 * gb), 19 * gb, "95% checkpoint reported")
        TestRun.expectEqual(tracker.update(progressBytes: 19_800 * mb), 19_800 * mb, "99% checkpoint reported")
        TestRun.expect(tracker.update(progressBytes: 20 * gb) == nil, "at threshold silent")
        TestRun.expect(tracker.update(progressBytes: 25 * gb) == nil, "beyond threshold silent")
        TestRun.expect(tracker.next == nil, "exhausted → next nil")
    }

    /// 一拍跳到 19.5G 连跨 16G/18G/19G：首拍报 16G，后续拍逐个追平；19.8G 未到则止于 19G
    static func jumpCatchesUpOneCheckpointPerTick() {
        var tracker = MilestoneTracker()
        tracker.arm(thresholdBytes: 20 * gb, progressBytes: 0)
        TestRun.expectEqual(tracker.update(progressBytes: 19_500 * mb), 16 * gb, "first crossed reported")
        TestRun.expectEqual(tracker.update(progressBytes: 19_500 * mb), 18 * gb, "second crossed next tick")
        TestRun.expectEqual(tracker.update(progressBytes: 19_500 * mb), 19 * gb, "third crossed next tick")
        TestRun.expect(tracker.update(progressBytes: 19_500 * mb) == nil,
                       "caught up: 19.8G not reached at 19.5G")
    }

    /// arm 不补发：20GB 阈值从 17G 武装 → 已过的 16G 被跳过、未到的 18G 仍在，
    /// 之后逐个报告（17G 时 18G 尚未越过，不得提前跳过）
    static func armSkipsPassedCheckpointsWithoutBackfill() {
        var tracker = MilestoneTracker()
        tracker.arm(thresholdBytes: 20 * gb, progressBytes: 17 * gb)
        TestRun.expectEqual(tracker.next, 18 * gb, "arm skips only passed checkpoints")
        TestRun.expect(tracker.update(progressBytes: 17_500 * mb) == nil, "below next checkpoint silent")
        TestRun.expectEqual(tracker.update(progressBytes: 18 * gb), 18 * gb, "first unpassed checkpoint reported")
        TestRun.expectEqual(tracker.update(progressBytes: 19 * gb), 19 * gb, "reporting continues")
    }

    /// arm 自 0：无已过检查点，首个检查点正常报告
    static func armFromZeroReportsFirstCheckpoint() {
        var tracker = MilestoneTracker()
        tracker.arm(thresholdBytes: 3 * gb, progressBytes: 0)
        TestRun.expectEqual(tracker.next, 1_500 * mb, "next is 50% checkpoint")
        TestRun.expectEqual(tracker.update(progressBytes: 1_500 * mb), 1_500 * mb, "first checkpoint reported")
    }
}
