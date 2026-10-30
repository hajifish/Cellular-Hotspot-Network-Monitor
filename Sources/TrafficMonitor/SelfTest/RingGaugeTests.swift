enum RingGaugeTests {
    static func all() {
        arcFractionComputation()
    }

    /// 未设置 → nil；阈值 0 视同未设置；已触发 → 1；其余按比例并钳位 0…1
    static func arcFractionComputation() {
        TestRun.expect(RingGaugeView.arcFraction(threshold: nil, fired: false, progressBytes: 100) == nil,
                       "unset returns nil")
        TestRun.expect(RingGaugeView.arcFraction(threshold: 0, fired: false, progressBytes: 100) == nil,
                       "zero threshold treated as unset")
        TestRun.expectEqual(RingGaugeView.arcFraction(threshold: 1_000, fired: true, progressBytes: 10),
                            Double?(1), "fired draws full arc")
        TestRun.expectEqual(RingGaugeView.arcFraction(threshold: 1_000, fired: false, progressBytes: 250),
                            Double?(0.25), "quarter progress")
        TestRun.expectEqual(RingGaugeView.arcFraction(threshold: 1_000, fired: false, progressBytes: 5_000),
                            Double?(1), "over-progress clamps to 1")
    }
}
