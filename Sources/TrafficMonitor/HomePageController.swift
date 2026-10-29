import AppKit

/// 主页窗口：深色玻璃仪表盘，接口卡片（含独立重置）+ 会话汇总条 + 120 秒滚动速率图
@MainActor
final class HomePageController {
    private let monitor: TrafficMonitor
    private let window: NSWindow
    private let graphView = RateGraphView()
    private var cards: [InterfaceCategory: (rate: NSTextField, total: NSTextField, title: NSTextField)] = [:]
    private var summaryValues: [NSTextField] = []
    private var legendLabel: NSTextField!
    private var ratesToggle: NSButton!
    private var ratesLabel: NSTextField!
    private var totalsToggle: NSButton!
    private var totalsLabel: NSTextField!
    private var observerID: UUID?

    static let downloadAccent = RateGraphView.downloadColor
    static let uploadAccent = RateGraphView.uploadColor

    init(monitor: TrafficMonitor) {
        self.monitor = monitor
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 428),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Traffic Monitor"
        window.appearance = NSAppearance(named: .darkAqua) // 仪表盘恒为深色玻璃
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
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

    /// 汇总条里的告警状态文案（纯函数，可测）
    nonisolated static func alertStripText(threshold: UInt64?, totalBytes: UInt64) -> String {
        guard let threshold, threshold > 0 else { return "未设置" }
        let percent = min(100, Int(Double(totalBytes) / Double(threshold) * 100))
        return "\(ByteFormat.string(threshold)) · 已用 \(percent)%"
    }

    // MARK: - UI 构建

    private func buildUI() {
        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 720, height: 428))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        window.contentView = visual
        let content = visual

        // 顶部右侧：状态栏显示开关（累计流量在前、实时速率在后；都关 = 状态栏只显示图标）
        totalsToggle = sphereToggle(action: #selector(toggleTotals))
        totalsToggle.frame = NSRect(x: 538, y: 384, width: 18, height: 18)
        content.addSubview(totalsToggle)
        totalsLabel = makeLabel(size: 11, color: .labelColor, weight: .medium)
        totalsLabel.stringValue = "累计流量"
        totalsLabel.frame = NSRect(x: 560, y: 386, width: 56, height: 16)
        content.addSubview(totalsLabel)
        ratesToggle = sphereToggle(action: #selector(toggleRates))
        ratesToggle.frame = NSRect(x: 628, y: 384, width: 18, height: 18)
        content.addSubview(ratesToggle)
        ratesLabel = makeLabel(size: 11, color: .labelColor, weight: .medium)
        ratesLabel.stringValue = "实时速率"
        ratesLabel.frame = NSRect(x: 650, y: 386, width: 56, height: 16)
        content.addSubview(ratesLabel)
        refreshToggles()

        // 接口卡片（右上角可独立重置；开始/已运行移入下方会话汇总条）
        let cardSpecs: [(InterfaceCategory, CGFloat)] = [
            (.wifi, 24),
            (.iphone, 376),
        ]
        for (category, x) in cardSpecs {
            let card = roundedCard(frame: NSRect(x: x, y: 254, width: 320, height: 116))
            content.addSubview(card)

            let title = makeLabel(size: 13, color: .labelColor, weight: .semibold)
            title.frame = NSRect(x: 18, y: 80, width: 180, height: 18)
            let reset = NSButton(title: "重置计量", target: self, action: #selector(resetCategory(_:)))
            reset.isBordered = false
            reset.setFrameOrigin(NSPoint(x: 320 - 74, y: 80))
            reset.font = .systemFont(ofSize: 10, weight: .medium)
            reset.contentTintColor = .secondaryLabelColor
            reset.identifier = NSUserInterfaceItemIdentifier(category == .wifi ? "wifi" : "iphone")
            card.contentView?.addSubview(reset)

            let rate = makeLabel(size: 12, color: .labelColor, weight: .regular)
            rate.frame = NSRect(x: 18, y: 42, width: 284, height: 34)
            let total = makeLabel(size: 12, color: .secondaryLabelColor, weight: .regular)
            total.frame = NSRect(x: 18, y: 14, width: 284, height: 20)
            for label in [title, rate, total] {
                card.contentView?.addSubview(label)
            }
            cards[category] = (rate, total, title)
        }

        // 会话汇总条：开始/已运行、总上传、总下载、总速率、告警状态
        let strip = roundedCard(frame: NSRect(x: 24, y: 196, width: 672, height: 48))
        content.addSubview(strip)
        let summarySpecs: [(String, CGFloat)] = [
            ("会话", 18), ("总上传", 170), ("总下载", 300), ("总速率", 428), ("流量告警", 566),
        ]
        for (caption, x) in summarySpecs {
            let captionLabel = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
            captionLabel.stringValue = caption
            captionLabel.frame = NSRect(x: x, y: 28, width: 120, height: 12)
            strip.contentView?.addSubview(captionLabel)
            let value = makeLabel(size: 12, color: .labelColor, weight: .semibold)
            value.frame = NSRect(x: x, y: 8, width: 130, height: 18)
            value.lineBreakMode = .byClipping
            strip.contentView?.addSubview(value)
            summaryValues.append(value)
        }

        let sectionLabel = makeLabel(size: 11, color: .secondaryLabelColor, weight: .medium)
        sectionLabel.stringValue = "实时速率 · 近 120 秒"
        sectionLabel.frame = NSRect(x: 24, y: 160, width: 672, height: 16)
        content.addSubview(sectionLabel)

        graphView.frame = NSRect(x: 24, y: 36, width: 672, height: 118)
        content.addSubview(graphView)

        legendLabel = makeLabel(size: 11, color: .secondaryLabelColor, weight: .regular)
        legendLabel.frame = NSRect(x: 24, y: 12, width: 672, height: 18)
        content.addSubview(legendLabel)
        updateLegend()
    }

    private func roundedCard(frame: NSRect) -> NSBox {
        let card = NSBox(frame: frame)
        card.boxType = .custom
        card.fillColor = NSColor.white.withAlphaComponent(0.06)
        card.borderColor = NSColor.white.withAlphaComponent(0.10)
        card.borderWidth = 1
        card.cornerRadius = 12
        card.contentViewMargins = .zero
        return card
    }

    private func makeLabel(size: CGFloat, color: NSColor, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }

    /// 小圆球开关：选中=白色实心球，未选=空心环
    private func sphereToggle(action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.title = ""
        return button
    }

    private func styleSphere(_ button: NSButton?, on: Bool) {
        guard let button, let layer = button.layer else { return }
        layer.cornerRadius = 9
        if on {
            layer.backgroundColor = NSColor.white.cgColor
            layer.borderWidth = 0
        } else {
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 1.5
            layer.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        }
    }

    @objc private func toggleRates() {
        StatusBarPrefs.showRates.toggle()
        refreshToggles()
    }

    @objc private func toggleTotals() {
        StatusBarPrefs.showTotals.toggle()
        refreshToggles()
    }

    private func refreshToggles() {
        styleSphere(ratesToggle, on: StatusBarPrefs.showRates)
        styleSphere(totalsToggle, on: StatusBarPrefs.showTotals)
        // 文字常驻，仅用颜色深浅区分选中态
        ratesLabel.textColor = StatusBarPrefs.showRates ? .labelColor : .secondaryLabelColor
        totalsLabel.textColor = StatusBarPrefs.showTotals ? .labelColor : .secondaryLabelColor
    }

    // MARK: - 按模块重置

    @objc private func resetCategory(_ sender: NSButton) {
        let category: InterfaceCategory = sender.identifier?.rawValue == "wifi" ? .wifi : .iphone
        let name = category.displayName
        let dialog = NSAlert()
        dialog.messageText = "重置\(name)计量？"
        dialog.informativeText = "将清零 \(name) 模块的累计流量并重新开始计时，此操作不可撤销。"
        dialog.addButton(withTitle: "确认重置")
        dialog.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        monitor.reset(category)
    }

    /// 卡片速率行：彩色箭头 + 等宽数字 + 缩小单位
    private static func attributedRate(arrow: String, accent: NSColor,
                                       value: String, unit: String,
                                       numberSize: CGFloat, unitSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: arrow + " ", attributes: [
            .font: NSFont.systemFont(ofSize: numberSize * 0.78, weight: .bold),
            .foregroundColor: accent,
        ]))
        result.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: numberSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        result.append(NSAttributedString(string: " " + unit, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: unitSize, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return result
    }

    /// 图例：色点 + 文字（身份不靠颜色单独承载；文字用文本色）
    private func updateLegend() {
        let upload = Self.dotAttachment(color: Self.uploadAccent)
        let download = Self.dotAttachment(color: Self.downloadAccent)
        legendLabel.attributedStringValue = NSMutableAttributedString(attributedString: download)
            .appending(" 下载    ")
            .appending(upload)
            .appending(" 上传")
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

        for (category, labels) in cards {
            let usage = store.usage(for: category)
            let name = category.displayName
            let rate = category == .wifi ? monitor.wifiRate : monitor.iphoneRate
            let interface = monitor.interfaceByCategory[category].map { "  ·  \($0)" } ?? ""
            labels.title.stringValue = "\(name)\(interface)"
            let down = ByteFormat.rateParts(rate.rx)
            let up = ByteFormat.rateParts(rate.tx)
            let rateText = NSMutableAttributedString(attributedString: Self.attributedRate(
                arrow: "↓", accent: Self.downloadAccent,
                value: down.value, unit: down.unit, numberSize: 19, unitSize: 11))
            rateText.append(NSAttributedString(string: "   "))
            rateText.append(Self.attributedRate(
                arrow: "↑", accent: Self.uploadAccent,
                value: up.value, unit: up.unit, numberSize: 19, unitSize: 11))
            labels.rate.attributedStringValue = rateText
            labels.total.stringValue = "累计  ↑ \(ByteFormat.string(usage.tx))    ↓ \(ByteFormat.string(usage.rx))"
        }

        // 会话汇总条
        let sessionStart = store.sessionStart
        let totalRX = store.wifi.rx + store.iphone.rx
        let totalTX = store.wifi.tx + store.iphone.tx
        let total = monitor.totalRate
        let seconds = max(0, Int(Date().timeIntervalSince(sessionStart)))
        let alertThreshold = alertThresholdProvider?()
        summaryValues[0].stringValue = "\(sessionStart.formatted(date: .omitted, time: .shortened)) · \(Self.durationText(seconds))"
        summaryValues[1].stringValue = "↑ \(ByteFormat.string(totalTX))"
        summaryValues[2].stringValue = "↓ \(ByteFormat.string(totalRX))"
        summaryValues[3].stringValue = "↓\(ByteFormat.rate(total.rx, compact: true)) ↑\(ByteFormat.rate(total.tx, compact: true))"
        summaryValues[4].stringValue = Self.alertStripText(threshold: alertThreshold, totalBytes: totalRX + totalTX)

        graphView.history = monitor.history
        graphView.downloadLabel = "↓\(ByteFormat.rate(total.rx))"
        graphView.uploadLabel = "↑\(ByteFormat.rate(total.tx))"
    }

    /// 告警阈值由 MenuBarController 持有，经此闭包读取
    var alertThresholdProvider: (() -> UInt64?)?
}

private extension NSMutableAttributedString {
    func appending(_ attachment: NSAttributedString) -> NSMutableAttributedString {
        append(attachment)
        return self
    }

    func appending(_ string: String) -> NSMutableAttributedString {
        append(NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return self
    }
}
