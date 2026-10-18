enum StatusBarFormatterTests {
    private static let rate = CategoryDelta(rx: 1_200, tx: 300)

    static func all() {
        ratesOnlyContainsCompactRates()
        totalsOnlyContainsCompactTotals()
        bothIsTwoLineStacked()
        bothOffIsNil()
    }

    static func ratesOnlyContainsCompactRates() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: false,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)?.string
        TestRun.expectEqual(text, "↑300B/s ↓1.2KB/s", "rates only compact")
    }

    static func totalsOnlyContainsCompactTotals() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: true,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑2.3GB ↓8.1GB", "totals only compact")
    }

    static func bothIsTwoLineStacked() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: true,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑300B/s ↓1.2KB/s\n↑2.3GB ↓8.1GB", "stacked two lines")
    }

    static func bothOffIsNil() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: false,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expect(text == nil, "both off hides text")
    }
}
