enum StatusBarFormatterTests {
    private static let rate = CategoryDelta(rx: 1_200, tx: 300)

    static func all() {
        ratesOnlyContainsRates()
        totalsOnlyContainsTotals()
        bothContainsBoth()
        iconOnlyIsNil()
    }

    static func ratesOnlyContainsRates() {
        let text = StatusBarFormatter.text(for: .ratesOnly, totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expectEqual(text, "↑300 B/s ↓1.2 KB/s", "rates only")
    }

    static func totalsOnlyContainsTotals() {
        let text = StatusBarFormatter.text(for: .totalsOnly, totalRate: rate,
                                           totalRX: 8_100_000_000, totalTX: 2_300_000_000)
        TestRun.expectEqual(text, "↑2.3 GB ↓8.1 GB", "totals only")
    }

    static func bothContainsBoth() {
        let text = StatusBarFormatter.text(for: .both, totalRate: rate,
                                           totalRX: 8_100_000_000, totalTX: 2_300_000_000)
        TestRun.expect(text?.contains("↑2.3 GB") == true, "both has up total")
        TestRun.expect(text?.contains("↓8.1 GB") == true, "both has down total")
        TestRun.expect(text?.contains("300 B/s") == true, "both has up rate")
        TestRun.expect(text?.contains("1.2 KB/s") == true, "both has down rate")
    }

    static func iconOnlyIsNil() {
        let text = StatusBarFormatter.text(for: .iconOnly, totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expect(text == nil, "iconOnly hides text")
    }
}
