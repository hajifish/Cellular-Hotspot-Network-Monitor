import AppKit

/// 主页窗口：总览时长、两张接口卡片、120 秒滚动速率图
@MainActor
final class HomePageController {
    private let monitor: TrafficMonitor
    private let window: NSWindow
    private let graphView = RateGraphView()
    private var durationLabel: NSTextField!
    private var legendLabel: NSTextField!
    private var cards: [InterfaceCategory: (rate: NSTextField, total: NSTextField, title: NSTextField)] = [:]
    private var observerID: UUID?

    init(monitor: TrafficMonitor) {
        self.monitor = monitor
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Traffic Monitor"
        window.isReleasedWhenClosed = false
        buildUI()
        observerID = monitor.addObserver { [weak self] in self?.refresh() }
        refresh()
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// "1h 2m" / "1m 30s" / "45s"（纯函数，可测）
    nonisolated static func durationText(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    // MARK: - UI 构建

    private func buildUI() {
        guard let content = window.contentView else { return }

        durationLabel = makeLabel(size: 12, color: .secondaryLabelColor)
        durationLabel.frame = NSRect(x: 20, y: 288, width: 420, height: 18)
        content.addSubview(durationLabel)

        let cardSpecs: [(InterfaceCategory, String, CGFloat)] = [
            (.wifi, "Wi-Fi", 20),
            (.iphone, "iPhone", 235),
        ]
        for (category, name, x) in cardSpecs {
            let box = NSBox(frame: NSRect(x: x, y: 158, width: 205, height: 126))
            box.title = name
            box.titleFont = .systemFont(ofSize: 12, weight: .semibold)
            content.addSubview(box)

            let title = makeLabel(size: 10, color: .tertiaryLabelColor)
            title.frame = NSRect(x: 14, y: 84, width: 177, height: 14)
            let rate = makeLabel(size: 14, color: .labelColor)
            rate.frame = NSRect(x: 14, y: 46, width: 177, height: 38)
            let total = makeLabel(size: 11, color: .secondaryLabelColor)
            total.frame = NSRect(x: 14, y: 12, width: 177, height: 36)
            for label in [title, rate, total] {
                box.contentView?.addSubview(label)
            }
            cards[category] = (rate, total, title)
        }

        let sectionLabel = makeLabel(size: 11, color: .secondaryLabelColor)
        sectionLabel.stringValue = "实时速率（近 120 秒）"
        sectionLabel.frame = NSRect(x: 20, y: 138, width: 420, height: 16)
        content.addSubview(sectionLabel)

        graphView.frame = NSRect(x: 20, y: 36, width: 420, height: 96)
        content.addSubview(graphView)

        legendLabel = makeLabel(size: 10, color: .secondaryLabelColor)
        legendLabel.frame = NSRect(x: 20, y: 14, width: 420, height: 16)
        content.addSubview(legendLabel)
        updateLegendDot()
    }

    private func makeLabel(size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }

    /// 图例：色点 + 文字（身份不靠颜色单独承载；文字用文本色）
    private func updateLegendDot() {
        let upload = Self.dotAttachment(color: RateGraphView.uploadColor)
        let download = Self.dotAttachment(color: RateGraphView.downloadColor)
        legendLabel.attributedStringValue = NSMutableAttributedString(attributedString: upload)
            .appending(" 上传    ")
            .appending(download)
            .appending(" 下载")
    }

    private static func dotAttachment(color: NSColor) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.bounds = NSRect(x: 0, y: -1, width: 8, height: 8)
        attachment.image = coloredDot(color)
        return NSAttributedString(attachment: attachment)
    }

    private static func coloredDot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - 刷新

    private func refresh() {
        let store = monitor.store
        let seconds = Int(Date().timeIntervalSince(store.startTime))
        durationLabel.stringValue = "开始于 \(store.startTime.formatted(date: .omitted, time: .shortened)) · 已运行 \(Self.durationText(max(0, seconds)))"

        for (category, labels) in cards {
            let name = category == .wifi ? "Wi-Fi" : "iPhone"
            let rx = category == .wifi ? store.wifiRX : store.iphoneRX
            let tx = category == .wifi ? store.wifiTX : store.iphoneTX
            let rate = category == .wifi ? monitor.wifiRate : monitor.iphoneRate
            let interface = monitor.interfaceByCategory[category].map { " (\($0))" } ?? ""
            labels.title.stringValue = "\(name)\(interface)"
            labels.rate.stringValue = "↑ \(ByteFormat.rate(rate.tx))   ↓ \(ByteFormat.rate(rate.rx))"
            labels.total.stringValue = "累计 ↑ \(ByteFormat.string(tx))\n↓ \(ByteFormat.string(rx))"
        }

        graphView.history = monitor.history
        graphView.downloadLabel = "↓\(ByteFormat.rate(monitor.totalRate.rx))"
        graphView.uploadLabel = "↑\(ByteFormat.rate(monitor.totalRate.tx))"
    }
}

private extension NSMutableAttributedString {
    func appending(_ attachment: NSAttributedString) -> NSMutableAttributedString {
        append(attachment)
        return self
    }

    func appending(_ string: String) -> NSMutableAttributedString {
        append(NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return self
    }
}
