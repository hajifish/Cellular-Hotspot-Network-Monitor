import AppKit

/// 主页窗口：深色玻璃仪表盘，Hero 总速率 + 接口卡片 + 120 秒滚动速率图
@MainActor
final class HomePageController {
    private let monitor: TrafficMonitor
    private let window: NSWindow
    private let graphView = RateGraphView()
    private var heroDownload: NSTextField!
    private var heroUpload: NSTextField!
    private var cards: [InterfaceCategory: (rate: NSTextField, total: NSTextField, title: NSTextField, meta: NSTextField)] = [:]
    private var legendLabel: NSTextField!
    private var observerID: UUID?

    static let downloadAccent = RateGraphView.downloadColor
    static let uploadAccent = RateGraphView.uploadColor

    init(monitor: TrafficMonitor) {
        self.monitor = monitor
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 522),
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

    // MARK: - UI 构建

    private func buildUI() {
        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 720, height: 522))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        window.contentView = visual
        let content = visual

        // 顶部：状态栏显示开关（两个独立选择；都关 = 状态栏只显示图标）
        let toggleLabel = makeLabel(size: 12, color: .secondaryLabelColor, weight: .medium)
        toggleLabel.stringValue = "状态栏显示"
        toggleLabel.frame = NSRect(x: 24, y: 456, width: 90, height: 20)
        content.addSubview(toggleLabel)
        ratesToggle = pillToggle(title: "实时速率", action: #selector(toggleRates))
        ratesToggle.frame = NSRect(x: 122, y: 452, width: 100, height: 26)
        content.addSubview(ratesToggle)
        totalsToggle = pillToggle(title: "累计流量", action: #selector(toggleTotals))
        totalsToggle.frame = NSRect(x: 230, y: 452, width: 100, height: 26)
        content.addSubview(totalsToggle)
        refreshToggles()

        // Hero 总速率
        let hero = roundedCard(frame: NSRect(x: 24, y: 330, width: 672, height: 100))
        content.addSubview(hero)
        heroDownload = bigRateLabel()
        heroDownload.frame = NSRect(x: 28, y: 22, width: 320, height: 52)
        hero.contentView?.addSubview(heroDownload)
        heroUpload = bigRateLabel()
        heroUpload.frame = NSRect(x: 364, y: 22, width: 300, height: 52)
        hero.contentView?.addSubview(heroUpload)

        // 接口卡片（每个计量模块内含自己的开始时间与已运行时长）
        let cardSpecs: [(InterfaceCategory, CGFloat)] = [
            (.wifi, 24),
            (.iphone, 376),
        ]
        for (category, x) in cardSpecs {
            let card = roundedCard(frame: NSRect(x: x, y: 192, width: 320, height: 122))
            content.addSubview(card)

            let title = makeLabel(size: 13, color: .labelColor, weight: .semibold)
            title.frame = NSRect(x: 18, y: 88, width: 284, height: 18)
            let rate = makeLabel(size: 12, color: .labelColor, weight: .regular)
            rate.frame = NSRect(x: 18, y: 50, width: 284, height: 32)
            let total = makeLabel(size: 12, color: .secondaryLabelColor, weight: .regular)
            total.frame = NSRect(x: 18, y: 30, width: 284, height: 20)
            let meta = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
            meta.frame = NSRect(x: 18, y: 10, width: 284, height: 16)
            for label in [title, rate, total, meta] {
                card.contentView?.addSubview(label)
            }
            cards[category] = (rate, total, title, meta)
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

    // MARK: - 状态栏显示开关

    private var ratesToggle: NSButton!
    private var totalsToggle: NSButton!

    private func pillToggle(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 13
        return button
    }

    private func refreshToggles() {
        stylePill(ratesToggle, on: StatusBarPrefs.showRates)
        stylePill(totalsToggle, on: StatusBarPrefs.showTotals)
    }

    /// 胶囊样式：选中=验证过的深色蓝底白字；未选=描边灰字
    private func stylePill(_ button: NSButton?, on: Bool) {
        guard let button, let layer = button.layer else { return }
        layer.cornerRadius = 13
        layer.borderWidth = 1
        if on {
            layer.backgroundColor = NSColor(srgbRed: 0x39 / 255.0, green: 0x87 / 255.0,
                                            blue: 0xe5 / 255.0, alpha: 1).cgColor // #3987e5
            layer.borderColor = NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
        } else {
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
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
        label.textColor = color == .clear ? .labelColor : color
        label.lineBreakMode = .byWordWrapping
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        return label
    }

    private func bigRateLabel() -> NSTextField {
        let label = makeLabel(size: 30, color: .labelColor, weight: .semibold)
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        return label
    }

    /// 大号速率文本：彩色箭头 + 等宽数字 + 缩小单位
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
        let seconds = max(0, Int(Date().timeIntervalSince(store.startTime)))
        let startTime = store.startTime.formatted(.dateTime.hour().minute())
        let metaText = "开始 \(startTime) · 已运行 \(Self.durationText(seconds))"

        let total = monitor.totalRate
        let downParts = ByteFormat.rateParts(total.rx)
        let upParts = ByteFormat.rateParts(total.tx)
        heroDownload.attributedStringValue = Self.attributedRate(
            arrow: "↓", accent: Self.downloadAccent,
            value: downParts.value, unit: downParts.unit,
            numberSize: 32, unitSize: 15)
        heroUpload.attributedStringValue = Self.attributedRate(
            arrow: "↑", accent: Self.uploadAccent,
            value: upParts.value, unit: upParts.unit,
            numberSize: 32, unitSize: 15)

        for (category, labels) in cards {
            let name = category.displayName
            let rx = category == .wifi ? store.wifiRX : store.iphoneRX
            let tx = category == .wifi ? store.wifiTX : store.iphoneTX
            let rate = category == .wifi ? monitor.wifiRate : monitor.iphoneRate
            let interface = monitor.interfaceByCategory[category].map { "  ·  \($0)" } ?? ""
            labels.title.stringValue = "\(name)\(interface)"
            let down = ByteFormat.rateParts(rate.rx)
            let up = ByteFormat.rateParts(rate.tx)
            let rateText = NSMutableAttributedString(attributedString: Self.attributedRate(
                arrow: "↓", accent: Self.downloadAccent,
                value: down.value, unit: down.unit, numberSize: 19, unitSize: 11))
            rateText.append(Self.spacer(width: 18))
            rateText.append(Self.attributedRate(
                arrow: "↑", accent: Self.uploadAccent,
                value: up.value, unit: up.unit, numberSize: 19, unitSize: 11))
            labels.rate.attributedStringValue = rateText
            labels.total.stringValue = "累计  ↑ \(ByteFormat.string(tx))    ↓ \(ByteFormat.string(rx))"
            labels.meta.stringValue = metaText
        }

        graphView.history = monitor.history
        graphView.downloadLabel = "↓\(ByteFormat.rate(total.rx))"
        graphView.uploadLabel = "↑\(ByteFormat.rate(total.tx))"
    }

    private static func spacer(width: CGFloat) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [.kern: width])
    }
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
