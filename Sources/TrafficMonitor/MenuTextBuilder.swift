import AppKit

/// 菜单条目的富文本样式：彩色箭头（与主页一致）、等宽数字、tab 对齐
enum MenuTextBuilder {
    private static let downloadAccent = RateGraphView.downloadColor
    private static let uploadAccent = RateGraphView.uploadColor

    private static func attributes(size: CGFloat, color: NSColor,
                                   weight: NSFont.Weight = .regular, mono: Bool = false) -> [NSAttributedString.Key: Any] {
        let font = mono
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        return [.font: font, .foregroundColor: color]
    }

    private static func arrow(_ glyph: String, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: glyph, attributes:
            attributes(size: 13, color: color, weight: .bold))
    }

    /// 头部行：开始时间（显眼）+ 已运行时长
    static func startTimeRow(startDate: Date, elapsedSeconds: Int) -> NSAttributedString {
        let time = startDate.formatted(.dateTime.hour().minute())
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "开始时间  ", attributes: attributes(size: 12, color: .secondaryLabelColor)))
        text.append(NSAttributedString(string: time, attributes: attributes(size: 13, color: .labelColor, weight: .medium, mono: true)))
        text.append(NSAttributedString(string: "   ·   已运行 \(HomePageController.durationText(max(0, elapsedSeconds)))",
                                       attributes: attributes(size: 12, color: .secondaryLabelColor)))
        return text
    }

    /// 接口行：名称 | 累计（彩色箭头 + 等宽数字）| 当前速率
    static func interfaceRow(name: String, rx: UInt64, tx: UInt64, rate: CategoryDelta) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 96),
                              NSTextTab(textAlignment: .left, location: 196)]

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: name, attributes: attributes(size: 13, color: .labelColor)))
        text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))

        text.append(arrow("↑", uploadAccent))
        text.append(NSAttributedString(string: "\(ByteFormat.string(tx)) ", attributes: attributes(size: 13, color: .labelColor, mono: true)))
        text.append(arrow("↓", downloadAccent))
        text.append(NSAttributedString(string: ByteFormat.string(rx), attributes: attributes(size: 13, color: .labelColor, mono: true)))

        text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))
        text.append(NSAttributedString(string: ByteFormat.rate(rate.rx + rate.tx),
                                       attributes: attributes(size: 12, color: .secondaryLabelColor, mono: true)))
        return text
    }

    /// 「流量告警」配置项标记：已设置时变橙、触发后变红；未设置返回 nil（普通样式）
    static func alertHeader(armed: Bool, fired: Bool) -> NSAttributedString? {
        guard armed else { return nil }
        let color = fired ? NSColor.systemRed : NSColor.systemOrange
        return NSAttributedString(string: "● 流量告警", attributes:
            attributes(size: 13, color: color, weight: .semibold))
    }

    /// 用 sourceAtop 给模板符号图着色
    static func tintedSymbol(_ name: String, color: NSColor, size: CGFloat) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configured = symbol.withSymbolConfiguration(.init(pointSize: size, weight: .medium)) ?? symbol
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()
        configured.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        color.set()
        NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }
}
