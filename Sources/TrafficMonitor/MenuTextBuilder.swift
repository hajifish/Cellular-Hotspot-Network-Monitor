import AppKit

/// 列布局常量：前导缩进与列间距（tab 位按内容实测计算，面板随内容自然加宽）
enum RowLayout {
    static let leadingIndent: CGFloat = 4
    static let columnGap: CGFloat = 20
}

/// 一组行共享的两个 tab 位：first = 累计列（↑tx ↓rx）起点，total = 合并列起点
struct ColumnStops: Equatable {
    let first: CGFloat
    let total: CGFloat
}

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

    /// 行数据：名称 + 各向累计（tab 位测量与行排版共用）
    struct InterfaceRowSpec {
        let name: String
        let rx: UInt64
        let tx: UInt64
    }

    /// 按各行文本实测宽度（与渲染同字体）计算共享 tab 位，保证列对齐且永不折行。
    /// 名称与数值均按最重字重（semibold，合计行）测量，普通行必有余量。
    static func columnStops(forRows rows: [InterfaceRowSpec]) -> ColumnStops {
        let nameWidth = rows.map { measuredNameWidth($0.name) }.max() ?? 0
        let first = RowLayout.leadingIndent + ceil(nameWidth) + RowLayout.columnGap
        let midWidth = rows.map {
            measuredMidWidth(tx: ByteFormat.string($0.tx), rx: ByteFormat.string($0.rx))
        }.max() ?? 0
        return ColumnStops(first: first, total: first + ceil(midWidth) + RowLayout.columnGap)
    }

    /// 名称实测宽度（供布局不变式测试复用）
    static func measuredNameWidth(_ name: String) -> CGFloat {
        (name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ]).width
    }

    /// 「↑tx ↓rx」段实测宽度（供布局不变式测试复用）
    static func measuredMidWidth(tx: String, rx: String) -> CGFloat {
        midSegment(tx: tx, rx: rx, valueWeight: .semibold).size().width
    }

    /// 接口行：名称 | 累计（彩色箭头 + 等宽数字）| 合并（上行 + 下行，semibold）。
    /// tab 位由 columnStops 按全组行实测得出，列对齐且不折行；emphasized（合计行）整行加重
    static func interfaceRow(name: String, rx: UInt64, tx: UInt64,
                             stops: ColumnStops, emphasized: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        // 单行行：firstLineHeadIndent 才作用于首行（headIndent 只管续行）
        paragraph.firstLineHeadIndent = RowLayout.leadingIndent
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: stops.first),
                              NSTextTab(textAlignment: .left, location: stops.total)]
        let weight: NSFont.Weight = emphasized ? .semibold : .regular

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: name, attributes:
            attributes(size: 13, color: .labelColor, weight: emphasized ? .semibold : .regular)))
        text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))
        text.append(midSegment(tx: ByteFormat.string(tx), rx: ByteFormat.string(rx), valueWeight: weight))
        text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))
        text.append(NSAttributedString(string: ByteFormat.string(rx + tx),
                                       attributes: attributes(size: 13, color: .labelColor, weight: .semibold, mono: true)))
        return text
    }

    /// 中段「↑tx ↓rx」：排版与测量共用同一构建，宽度口径一致
    private static func midSegment(tx: String, rx: String, valueWeight: NSFont.Weight) -> NSAttributedString {
        let text = NSMutableAttributedString()
        text.append(arrow("↑", uploadAccent))
        text.append(NSAttributedString(string: "\(tx) ", attributes:
            attributes(size: 13, color: .labelColor, weight: valueWeight, mono: true)))
        text.append(arrow("↓", downloadAccent))
        text.append(NSAttributedString(string: rx, attributes:
            attributes(size: 13, color: .labelColor, weight: valueWeight, mono: true)))
        return text
    }

    /// 「流量告警」配置项标记：已设置时变橙并附剩余量，触发后变红；未设置返回 nil（普通样式）
    static func alertHeader(armed: Bool, fired: Bool, detail: String = "") -> NSAttributedString? {
        guard armed else { return nil }
        let color = fired ? NSColor.systemRed : NSColor.systemOrange
        var text = "● 流量告警"
        if !detail.isEmpty { text += " · " + detail }
        return NSAttributedString(string: text, attributes:
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
