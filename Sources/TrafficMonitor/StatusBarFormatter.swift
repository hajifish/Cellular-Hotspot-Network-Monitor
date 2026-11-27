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
    /// 状态栏「累计 / 实时」列富文本（两行竖排，同开并排，列间两个空格）。
    ///
    /// 告警剩余百分比（第三列）由 `remainingAttributed` 单独产出，由调用方在
    /// 位图合成阶段水平拼接、垂直居中——同串内用 baselineOffset 跨行居中会
    /// 被 TextKit 计入行高导致列几何被撑歪（v0.14.0 实测），故拆两块绘制。
    ///
    /// 全部为空（两开关关且不取剩余片段）时返回 nil（只显示图标）。
    ///
    /// ```text
    /// ↑3.9MB   ↑5.1KB/s
    /// ↓1.2MB   ↓9.2KB/s
    /// ```
    ///
    /// textColor 需由调用方按菜单栏明暗传入显式色（位图渲染中语义色解析不可靠）。
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
        paragraph.lineHeightMultiple = 0.9 // 紧行距：两行墨迹不超出菜单栏高度
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

    /// 告警剩余百分比片段：应用标志性 `↑↓` 箭头符号 + 14pt semibold 百分比，
    /// 同一分档色，单行、无行高/基线技巧（跨行垂直居中由调用方位图合成完成）。
    /// 百分比字号独立于列字号——10pt 反馈小一半、20pt 过大、16pt/14.4pt/12pt
    /// 逐步收敛定档 14pt（2026-11-27）。
    static func remainingAttributed(percent: Int, textColor: NSColor) -> NSAttributedString {
        let color = remainingColor(percent: percent, textColor: textColor)
        let result = NSMutableAttributedString()
        if let icon = MenuTextBuilder.tintedSymbol("arrow.up.arrow.down", color: color, size: 14) {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = NSRect(x: 0, y: -2.1, width: 14, height: 14)
            result.append(NSAttributedString(attachment: attachment))
        }
        result.append(NSAttributedString(string: " \(percent)%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color,
        ]))
        return result
    }

    /// 告警剩余百分比（0-100 四舍五入）；未设置/阈值为 0 → nil；已触发或进度≥阈值 → 0
    static func remainingPercent(threshold: UInt64?, fired: Bool, progressBytes: UInt64) -> Int? {
        guard let threshold, threshold > 0 else { return nil }
        guard !fired, progressBytes < threshold else { return 0 }
        return Int((Double(threshold - progressBytes) / Double(threshold) * 100).rounded())
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
