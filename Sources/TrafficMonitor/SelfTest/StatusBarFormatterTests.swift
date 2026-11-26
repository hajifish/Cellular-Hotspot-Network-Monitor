import AppKit

enum StatusBarFormatterTests {
    private static let rate = CategoryDelta(rx: 1_200, tx: 300)

    static func all() {
        ratesOnlyIsVerticalGroup()
        totalsOnlyIsVerticalGroup()
        bothIsTwoSideBySideGroups()
        bothOffIsNil()
        remainingPercentMath()
        remainingColorBands()
        showRemainingPrefDefaultsAndToggles()
        remainingToggleOffDoesNotRender()
        remainingColumnRenders()
        allThreeColumns()
        unsetAlertHidesColumn()
    }

    // ---- remainingPercent ----
    static func remainingPercentMath() {
        let gb = UInt64(1_000_000_000)
        TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 20 * gb, fired: false,
                           progressBytes: 15 * gb), 25, "20GB 用 15GB 剩 25%")
        TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: false,
                           progressBytes: 250), 75, "普通值")
        TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 3, fired: false,
                           progressBytes: 1), 67, "2/3 四舍五入 67")
        TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: false,
                           progressBytes: 1_000), 0, "进度=阈值 → 0")
        TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: false,
                           progressBytes: 5_000), 0, "进度超阈值 → 0")
        TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: true,
                           progressBytes: 100), 0, "已触发 → 0")
        TestRun.expect(StatusBarFormatter.remainingPercent(threshold: nil, fired: false,
                       progressBytes: 100) == nil, "未设置 → nil")
        TestRun.expect(StatusBarFormatter.remainingPercent(threshold: 0, fired: false,
                       progressBytes: 100) == nil, "阈值 0 → nil（防除零）")
    }

    // ---- remainingColor（sRGB 分量近似比较，避免 NSColor 相等性不可靠）----
    private static func rgbs(_ c: NSColor) -> (Double, Double, Double) {
        let s = c.usingColorSpace(.sRGB)!
        return (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
    }

    static func remainingColorBands() {
        func near(_ a: NSColor, _ b: NSColor) -> Bool {
            let (r1, g1, b1) = rgbs(a), (r2, g2, b2) = rgbs(b)
            return abs(r1 - r2) < 0.05 && abs(g1 - g2) < 0.05 && abs(b1 - b2) < 0.05
        }
        TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 100, textColor: .white), .white),
                       ">20% 用传入色")
        TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 21, textColor: .white), .white),
                       "21% 仍白")
        TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 20, textColor: .white), .systemOrange),
                       "≤20% 橙")
        TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 1, textColor: .white), .systemOrange),
                       "1% 橙")
        TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 0, textColor: .white), .systemRed),
                       "0% 红")
    }

    // ---- showRemaining 开关 ----
    static func showRemainingPrefDefaultsAndToggles() {
        let keyWasSet = UserDefaults.standard.object(forKey: StatusBarPrefs.showRemainingKey) != nil
        let original = StatusBarPrefs.showRemaining
        defer {
            if keyWasSet {
                StatusBarPrefs.showRemaining = original
            } else {
                UserDefaults.standard.removeObject(forKey: StatusBarPrefs.showRemainingKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: StatusBarPrefs.showRemainingKey)
        TestRun.expect(!StatusBarPrefs.showRemaining, "未设置时默认 false")
        StatusBarPrefs.showRemaining = true
        TestRun.expect(StatusBarPrefs.showRemaining, "写后读回 true")
    }

    static func ratesOnlyIsVerticalGroup() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: false, showRemaining: false,
                                                 remainingPercent: nil, textColor: .white,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)?.string
        TestRun.expectEqual(text, "↑300B/s\n↓1.2KB/s", "rates vertical group")
    }

    static func totalsOnlyIsVerticalGroup() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: true, showRemaining: false,
                                                 remainingPercent: nil, textColor: .white,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑2.3GB\n↓8.1GB", "totals vertical group")
    }

    static func bothIsTwoSideBySideGroups() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: true, showRemaining: false,
                                                 remainingPercent: nil, textColor: .white,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑2.3GB  ↑300B/s\n↓8.1GB  ↓1.2KB/s", "totals first, rates second")
    }

    static func bothOffIsNil() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: false, showRemaining: false,
                                                 remainingPercent: nil, textColor: .white,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expect(text == nil, "both off hides text")
    }

    // ---- attributed × 剩余列 ----
    // 开关关闭时不渲染剩余列；rates/totals 全关才可能 text == nil，
    // 故取全关真值表，验证有百分比在手、开关关也不占位。
    static func remainingToggleOffDoesNotRender() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: false, showRemaining: false,
                                                 remainingPercent: 25, textColor: .white,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expect(text == nil, "开关关 → 即使有百分比也不渲染")
    }

    static func remainingColumnRenders() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: false, showRemaining: true,
                                                 remainingPercent: 25, textColor: .white,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)?.string
        // 图标 attachment 在 plain string 里是 U+FFFC（object replacement）
        TestRun.expectEqual(text, "\u{FFFC} 25%", "仅剩余列单行：仪表图标 + 百分比")
    }

    static func allThreeColumns() {
        let text = StatusBarFormatter.attributed(showRates: true, showTotals: true, showRemaining: true,
                                                 remainingPercent: 25, textColor: .white,
                                                 totalRate: rate,
                                                 totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
        TestRun.expectEqual(text, "↑2.3GB  ↑300B/s  \u{FFFC} 25%\n↓8.1GB  ↓1.2KB/s",
                            "累计 → 实时 → 剩余（剩余列带图标、只在首行）")
    }

    static func unsetAlertHidesColumn() {
        let text = StatusBarFormatter.attributed(showRates: false, showTotals: false, showRemaining: true,
                                                 remainingPercent: nil, textColor: .white,
                                                 totalRate: rate, totalRX: 0, totalTX: 0)
        TestRun.expect(text == nil, "告警未设置 → 列不占位")
    }
}
