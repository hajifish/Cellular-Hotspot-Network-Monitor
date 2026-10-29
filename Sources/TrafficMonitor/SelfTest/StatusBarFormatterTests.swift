enum StatusBarFormatterTests {
    private static let rate = CategoryDelta(rx: 1_200, tx: 300)

    static func all() {
        ratesOnlyIsVerticalGroup()
        totalsOnlyIsVerticalGroup()
        bothIsTwoSideBySideGroups()
        bothOffIsNil()
    }

    static func ratesOnlyIsVerticalGroup() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: false,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)?.string
        TestRun.expectEqual(text, "↑300B/s\n↓1.2KB/s", "rates vertical group")
    }

    static func totalsOnlyIsVerticalGroup() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: true,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑2.3GB\n↓8.1GB", "totals vertical group")
    }

    static func bothIsTwoSideBySideGroups() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: true,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑300B/s  ↑2.3GB\n↓1.2KB/s  ↓8.1GB", "two groups side by side")
    }

    static func bothOffIsNil() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: false,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expect(text == nil, "both off hides text")
    }
}
