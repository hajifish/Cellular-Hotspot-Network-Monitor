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
    /// 速率+累计同开时上下两行（速率在上、累计在下），单位紧凑、箭头着色。
    static func attributed(showRates: Bool, showTotals: Bool,
                           totalRate: CategoryDelta, totalRX: UInt64, totalTX: UInt64) -> NSAttributedString? {
        switch (showRates, showTotals) {
        case (false, false):
            return nil
        case (true, false):
            return line(ratesLine(totalRate), fontSize: 11)
        case (false, true):
            return line(totalsLine(totalRX, totalTX), fontSize: 11)
        case (true, true):
            let stacked = NSMutableAttributedString()
            stacked.append(line(ratesLine(totalRate), fontSize: 9))
            stacked.append(NSAttributedString(string: "\n", attributes: lineBreakAttributes))
            stacked.append(line(totalsLine(totalRX, totalTX), fontSize: 9))
            return stacked
        }
    }

    // MARK: - 行构造

    private static func ratesLine(_ rate: CategoryDelta) -> String {
        "↑\(ByteFormat.rate(rate.tx, compact: true)) ↓\(ByteFormat.rate(rate.rx, compact: true))"
    }

    private static func totalsLine(_ rx: UInt64, _ tx: UInt64) -> String {
        "↑\(ByteFormat.string(tx, compact: true)) ↓\(ByteFormat.string(rx, compact: true))"
    }

    /// 单行构造：彩色箭头 + 等宽数字
    private static func line(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize <= 9 ? 0 : 1
        let result = NSMutableAttributedString()
        for (index, part) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: " ", attributes: commonAttributes(fontSize, paragraph)))
            }
            let piece = String(part)
            if piece.hasPrefix("↑") {
                result.append(NSAttributedString(string: "↑", attributes: arrowAttributes(fontSize)))
                result.append(NSAttributedString(string: String(piece.dropFirst()),
                                                 attributes: commonAttributes(fontSize, paragraph)))
            } else if piece.hasPrefix("↓") {
                result.append(NSAttributedString(string: "↓", attributes: arrowAttributesDown(fontSize)))
                result.append(NSAttributedString(string: String(piece.dropFirst()),
                                                 attributes: commonAttributes(fontSize, paragraph)))
            } else {
                result.append(NSAttributedString(string: piece, attributes: commonAttributes(fontSize, paragraph)))
            }
        }
        return result
    }

    private static var lineBreakAttributes: [NSAttributedString.Key: Any] {
        [NSAttributedString.Key.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)]
    }

    private static func commonAttributes(_ size: CGFloat, _ paragraph: NSMutableParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
         .foregroundColor: NSColor.labelColor,
         .paragraphStyle: paragraph]
    }

    private static func arrowAttributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold),
         .foregroundColor: RateGraphView.uploadColor]
    }

    private static func arrowAttributesDown(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold),
         .foregroundColor: RateGraphView.downloadColor]
    }
}
