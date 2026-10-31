import AppKit

/// 滚动双折线速率图（下载=蓝、上传=橙；色值经 dataviz 校验，浅/深模式各自取色）
final class RateGraphView: NSView {
    var history: RateHistory? { didSet { needsDisplay = true } }
    var downloadLabel = "" { didSet { needsDisplay = true } }
    var uploadLabel = "" { didSet { needsDisplay = true } }

    static let downloadColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x39 / 255.0, green: 0x87 / 255.0, blue: 0xe5 / 255.0, alpha: 1) // #3987e5
            : NSColor(srgbRed: 0x2a / 255.0, green: 0x78 / 255.0, blue: 0xd6 / 255.0, alpha: 1) // #2a78d6
    }

    static let uploadColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xd9 / 255.0, green: 0x59 / 255.0, blue: 0x26 / 255.0, alpha: 1) // #d95926
            : NSColor(srgbRed: 0xeb / 255.0, green: 0x68 / 255.0, blue: 0x34 / 255.0, alpha: 1) // #eb6834
    }

    /// 量程向上取整到 1/2/5×10^n（纯函数，可测）
    static func niceMaximum(_ value: UInt64) -> UInt64 {
        guard value > 0 else { return 1 }
        var magnitude = 1
        while UInt64(magnitude) * 10 <= value { magnitude *= 10 }
        for multiplier in [1, 2, 5, 10] {
            let candidate = UInt64(multiplier) * UInt64(magnitude)
            if candidate >= value { return candidate }
        }
        return value
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let history else { return }
        // 顶部预留 34pt 标注带（两行速率值叠放），折线绘图区永远到不了
        let plot = NSRect(x: 8, y: 10, width: bounds.width - 16, height: bounds.height - 44)
        let samples = history.samples
        let maxRate = Self.niceMaximum(samples.map { max($0.rx, $0.tx) }.max() ?? 1)

        // 退隐网格：3 条水平细线
        NSColor.white.withAlphaComponent(0.08).setStroke()
        let grid = NSBezierPath()
        for fraction in [0.0, 0.5, 1.0] {
            let y = plot.minY + plot.height * CGFloat(fraction)
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        grid.lineWidth = 0.5
        grid.stroke()

        guard samples.count >= 2 else { return }
        let stepX = plot.width / CGFloat(history.capacity - 1)
        func point(_ index: Int, _ field: (RateSample) -> UInt64) -> NSPoint {
            NSPoint(x: plot.maxX - CGFloat(samples.count - 1 - index) * stepX,
                    y: plot.minY + CGFloat(field(samples[index])) / CGFloat(maxRate) * plot.height)
        }
        // 下载为主序列：线下加低透明面积填充；上传只画线（避免两块填充互相干扰）
        drawSeries(Self.downloadColor, samples, point, { $0.rx }, areaFill: true)
        drawSeries(Self.uploadColor, samples, point, { $0.tx }, areaFill: false)

        // 当前速率标注：两行叠放于右上角标注带内（下载在上、上传在下），与折线互不遮挡
        drawTopLabel(downloadLabel, color: Self.downloadColor, line: 0)
        drawTopLabel(uploadLabel, color: Self.uploadColor, line: 1)
    }

    private func drawSeries(_ color: NSColor, _ samples: [RateSample],
                            _ point: (Int, (RateSample) -> UInt64) -> NSPoint,
                            _ field: @escaping (RateSample) -> UInt64,
                            areaFill: Bool) {
        let path = NSBezierPath()
        path.move(to: point(0, field))
        for i in 1..<samples.count { path.line(to: point(i, field)) }
        if areaFill {
            let fill = path.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: point(samples.count - 1, field).x, y: bounds.minY + 4))
            fill.line(to: NSPoint(x: point(0, field).x, y: bounds.minY + 4))
            fill.close()
            color.withAlphaComponent(0.14).setFill()
            fill.fill()
        }
        color.setStroke()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// 顶部标注带内右上角叠放标注（line 0 = 第一行）；带在绘图区之外，折线不可达
    private func drawTopLabel(_ text: String, color: NSColor, line: Int) {
        guard !text.isEmpty else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let lineHeight = size.height + 2
        let x = bounds.maxX - size.width - 4
        let y = bounds.maxY - size.height - 3 - CGFloat(line) * lineHeight
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }
}
