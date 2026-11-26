import AppKit
import Foundation

/// 状态栏显示偏好（三个独立开关：累计/实时/剩余；都关闭 = 只显示图标）
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

    static let showRemainingKey = "statusBarShowRemaining"
    static var showRemaining: Bool {
        get { UserDefaults.standard.object(forKey: showRemainingKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: showRemainingKey) }
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
    /// 状态栏富文本；三个开关都无内容时返回 nil（只显示图标）。
    ///
    /// 布局：累计流量在前、实时速率在后，各自是一组「↑上 / ↓下」两行竖排；
    /// 同开时两组并排（列间两个空格）。8pt 紧行距，保证不超出菜单栏高度。
    /// 告警剩余百分比是第三列，只追加在第一行行尾：gauge 仪表盘符号（9pt，
    /// 与文字同一分档色）+ 9pt semibold 百分比，基线下移 3.5pt 使其视觉上
    /// 跨两行居中；开关关闭或未设置告警（percent 为 nil）时不占位。
    ///
    /// textColor 需由调用方按菜单栏明暗传入显式色（位图渲染中语义色解析不可靠）。
    ///
    /// ```text
    /// ↑3.9MB   ↑5.1KB/s  ⏲ 75%
    /// ↓1.2MB   ↓9.2KB/s
    /// ```
    /// （⏲ 即 gauge 符号位图 attachment；plain string 中表现为 U+FFFC）
    ///
    /// 实测：三列位图约 103×29pt（两列 80×24pt）；baselineOffset 会被 TextKit
    /// 计入首行 descent、整体行高变大，百分比视觉略高于两行墨迹中心；
    /// 菜单栏对超高位图约 0.9× 等比缩小。
    static func attributed(showRates: Bool, showTotals: Bool, showRemaining: Bool,
                           remainingPercent: Int?, textColor: NSColor,
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
        let remaining: (text: String, color: NSColor)? = showRemaining
            ? remainingPercent.map { ("\($0)%", remainingColor(percent: $0, textColor: textColor)) }
            : nil
        guard !columns.isEmpty || remaining != nil else { return nil }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.lineHeightMultiple = 0.9
        paragraph.alignment = .left

        let result = NSMutableAttributedString()

        // 仅剩剩余列（rates/totals 全关）：单行输出，无分隔
        if columns.isEmpty, let remaining {
            result.append(remainingSegment(text: remaining.text, color: remaining.color,
                                           baselineOffset: 0))
            return result
        }

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
            if row == 0, let remaining {
                result.append(NSAttributedString(string: "  ", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
                    .paragraphStyle: paragraph,
                ]))
                result.append(remainingSegment(text: remaining.text, color: remaining.color,
                                               baselineOffset: -3.5))
            }
        }
        return result
    }

    /// 告警剩余百分比（0-100 四舍五入）；未设置/阈值为 0 → nil；已触发或进度≥阈值 → 0
    static func remainingPercent(threshold: UInt64?, fired: Bool, progressBytes: UInt64) -> Int? {
        guard let threshold, threshold > 0 else { return nil }
        guard !fired, progressBytes < threshold else { return 0 }
        return Int((Double(threshold - progressBytes) / Double(threshold) * 100).rounded())
    }

    /// 剩余列富片段：gauge 仪表盘符号 + 百分比，同一分档色；
    /// 图标经 attachment.bounds.y 与文字 baselineOffset 同步下沉（视觉跨两行居中时不断开）。
    /// 图标缺失（理论不存在，macOS 14 起 gauge 恒可用）时优雅退化为纯文字。
    private static func remainingSegment(text: String, color: NSColor,
                                         baselineOffset: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let icon = MenuTextBuilder.tintedSymbol("gauge", color: color, size: 9) {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = NSRect(x: 0, y: baselineOffset - 1, width: 9, height: 9)
            result.append(NSAttributedString(attachment: attachment))
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: color,
        ]
        if baselineOffset != 0 { attributes[.baselineOffset] = baselineOffset }
        result.append(NSAttributedString(string: " \(text)", attributes: attributes))
        return result
    }

    /// 剩余分档色：>20% 传入色（白）；≤20% 橙；0% 红（与主页汇总条 armed/fired 语义一致）
    static func remainingColor(percent: Int, textColor: NSColor) -> NSColor {
        if percent <= 0 { return .systemRed }
        if percent <= 20 { return .systemOrange }
        return textColor
    }

    /// 纯图标模式（三个展示开关全关）`↑↓` 兜底图标的着色：告警未设置（或阈值为 0）
    /// → 传入色；已设置 → 按剩余分档与 remainingColor 同口径。
    /// 与 showRemaining 开关无关——这是告警状态指示，不是数据列。
    static func iconFallbackColor(threshold: UInt64?, fired: Bool,
                                  progressBytes: UInt64, textColor: NSColor) -> NSColor {
        guard let threshold, threshold > 0 else { return textColor }
        return remainingColor(percent: remainingPercent(threshold: threshold, fired: fired,
                                                        progressBytes: progressBytes) ?? 0,
                              textColor: textColor)
    }
}
