import AppKit

/// 合并总流量圆环仪表：轨道环常驻，告警进度弧（进行中=橙、已触发=红），
/// 环心为合并总流量大数字。口径 = 所有模块累计上行 + 下行，与告警一致。
final class RingGaugeView: NSView {
    /// 告警弧比例（0…1）；nil = 未设置告警（只画素环）
    var arcFraction: Double? { didSet { needsDisplay = true } }
    var fired = false { didSet { needsDisplay = true } }
    var centerValue = "" { didSet { needsDisplay = true } }
    var centerUnit = "" { didSet { needsDisplay = true } }

    /// 告警弧比例（纯函数，可测）：未设置 → nil；已触发 → 1；其余按比例钳位 0…1
    static func arcFraction(threshold: UInt64?, fired: Bool,
                            progressBytes: UInt64) -> Double? {
        guard let threshold, threshold > 0 else { return nil }
        guard !fired else { return 1 }
        let ratio = Double(progressBytes) / Double(threshold)
        return min(1, max(0, ratio))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let lineWidth: CGFloat = 9
        let diameter = max(0, min(bounds.width, bounds.height) - lineWidth)
        guard diameter > 0 else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = diameter / 2

        // 轨道环常驻
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius,
                        startAngle: 0, endAngle: 360, clockwise: true)
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.10).setStroke()
        track.stroke()

        // 告警进度弧：从 12 点钟起顺时针；进行中橙色，已触发红色整环
        if let fraction = arcFraction {
            (fired ? NSColor.systemRed : NSColor.systemOrange).setStroke()
            let arc = NSBezierPath()
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * CGFloat(fraction),
                          clockwise: true)
            arc.stroke()
        }

        // 环心：合并总流量大数字（等宽）+ 单位小字
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let valueSize = (centerValue as NSString).size(withAttributes: valueAttributes)
        let unitSize = (centerUnit as NSString).size(withAttributes: unitAttributes)
        (centerValue as NSString).draw(
            at: NSPoint(x: center.x - valueSize.width / 2, y: center.y + 1),
            withAttributes: valueAttributes)
        (centerUnit as NSString).draw(
            at: NSPoint(x: center.x - unitSize.width / 2, y: center.y - unitSize.height - 5),
            withAttributes: unitAttributes)
    }
}
