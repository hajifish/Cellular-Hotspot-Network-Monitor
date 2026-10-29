import AppKit
import Foundation

/// 状态栏显示偏好（两个独立开关；都关闭 = 只显示图标）
enum StatusBarPrefs {
    static let showRatesKey = "statusBarShowRates"
    static let showTotalsKey = "statusBarShowTotals"
    private static let legacyModeKey = "menuBarDisplayMode"

    static var showRates: Bool {
        get { UserDefaults.standard.object(forKey: showRatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showRatesKey) }
    }

    static var showTotals: Bool {
        get { UserDefaults.standard.object(forKey: showTotalsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: showTotalsKey) }
    }

    /// 一次性迁移旧的单选模式（ratesOnly/totalsOnly/both/iconOnly）
    static func migrateLegacyMode() {
        guard UserDefaults.standard.object(forKey: showRatesKey) == nil,
              let legacy = UserDefaults.standard.string(forKey: legacyModeKey) else { return }
        switch legacy {
        case "ratesOnly": showRates = true; showTotals = false
        case "totalsOnly": showRates = false; showTotals = true
        case "both": showRates = true; showTotals = true
        default: showRates = false; showTotals = false // iconOnly
        }
        UserDefaults.standard.removeObject(forKey: legacyModeKey)
    }
}

enum StatusBarFormatter {
    /// 状态栏富文本；两个开关都关时返回 nil（只显示图标）。
    ///
    /// 布局：累计流量在前、实时速率在后，各自是一组「↑上 / ↓下」两行竖排；
    /// 同开时两组并排（列间两个空格）。8pt 紧行距，保证不超出菜单栏高度。
    ///
    /// textColor 需由调用方按菜单栏明暗传入显式色（位图渲染中语义色解析不可靠）。
    ///
    /// ```text
    /// ↑3.9MB   ↑5.1KB/s
    /// ↓1.2MB   ↓9.2KB/s
    /// ```
    static func attributed(showRates: Bool, showTotals: Bool, textColor: NSColor,
                           totalRate: CategoryDelta, totalRX: UInt64, totalTX: UInt64) -> NSAttributedString? {
        struct Segment {
            let arrow: String
            let arrowColor: NSColor
            let value: String
        }

        var columns: [[Segment]] = []
        if showTotals {
            columns.append([
                Segment(arrow: "↑", arrowColor: textColor,
                        value: ByteFormat.string(totalTX, compact: true)),
                Segment(arrow: "↓", arrowColor: textColor,
                        value: ByteFormat.string(totalRX, compact: true)),
            ])
        }
        if showRates {
            columns.append([
                Segment(arrow: "↑", arrowColor: textColor,
                        value: ByteFormat.rate(totalRate.tx, compact: true)),
                Segment(arrow: "↓", arrowColor: textColor,
                        value: ByteFormat.rate(totalRate.rx, compact: true)),
            ])
        }
        guard !columns.isEmpty else { return nil }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.lineHeightMultiple = 0.9
        paragraph.alignment = .left

        let result = NSMutableAttributedString()
        let rowCount = columns[0].count
        for row in 0..<rowCount {
            if row > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                    .paragraphStyle: paragraph,
                ]))
            }
            for (columnIndex, column) in columns.enumerated() {
                if columnIndex > 0 {
                    result.append(NSAttributedString(string: "  ", attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                        .paragraphStyle: paragraph,
                    ]))
                }
                let segment = column[row]
                let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
                result.append(NSAttributedString(string: segment.arrow, attributes: [
                    .font: font, .foregroundColor: segment.arrowColor,
                ]))
                result.append(NSAttributedString(string: segment.value, attributes: [
                    .font: font, .foregroundColor: textColor,
                ]))
            }
        }
        return result
    }
}
