import AppKit

/// 主页窗口：深色玻璃仪表盘，接口卡片（含独立重置与独立计时）+ 会话/告警汇总条 + 120 秒滚动速率图
@MainActor
final class HomePageController {
    /// 告警汇总的展示状态
    enum AlertStripState {
        case unset  // 未设置：白色
        case armed  // 已设置：橙色，倒计时感（剩余量 + 已用百分比）
        case fired  // 已触发：红色
    }

    /// 告警阈值与触发进度由 MenuBarController 持有，经此闭包读取
    var alertStateProvider: (() -> (threshold: UInt64?, fired: Bool, progressBytes: UInt64))?

    private let monitor: TrafficMonitor
    private let updateService: UpdateService
    private let window: NSWindow
    private let graphView = RateGraphView()
    private var cards: [InterfaceCategory: (rate: NSTextField, total: NSTextField, title: NSTextField, meta: NSTextField)] = [:]
    private var summaryValues: [NSTextField] = []
    private var alertValueLabel: NSTextField!
    private var legendLabel: NSTextField!
    private var ratesToggle: NSButton!
    private var ratesLabel: NSTextField!
    private var totalsToggle: NSButton!
    private var totalsLabel: NSTextField!
    private var updateStatusLabel: NSTextField!
    private var updateNotesLabel: NSTextField!
    private var updatePrimaryButton: NSButton!
    private var updateSecondaryButton: NSButton!
    private var updateProgress: NSProgressIndicator!
    private var updateCardBox: NSBox!
    private var updateVersionLabel: NSTextField!
    /// 收起/展开卡片时需要整体平移的基础视图（图例、图表、卡片等）
    private var updateBaseViews: [NSView] = []
    private var updateCardVisible = false
    private var observerID: UUID?

    static let downloadAccent = RateGraphView.downloadColor
    static let uploadAccent = RateGraphView.uploadColor

    init(monitor: TrafficMonitor, updateService: UpdateService) {
        self.monitor = monitor
        self.updateService = updateService
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

    /// 汇总条告警文案与状态（纯函数，可测）：
    /// 未设置 → 白色；已设置 → 橙色倒计时（剩余量 + 已用百分比）；已触发 → 红色
    nonisolated static func alertStrip(threshold: UInt64?, fired: Bool,
                                       progressBytes: UInt64) -> (text: String, state: AlertStripState) {
        guard let threshold, threshold > 0 else { return ("未设置", .unset) }
        if fired {
            return ("已触发 · 已用 100%", .fired)
        }
        let percent = min(100, Int(Double(progressBytes) / Double(threshold) * 100))
        let remaining = threshold > progressBytes ? threshold - progressBytes : 0
        return ("剩 \(ByteFormat.string(remaining, compact: true)) · 已用 \(percent)%", .armed)
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
        updateBaseViews.append(contentsOf: [totalsToggle, totalsLabel, ratesToggle, ratesLabel])

        // 接口卡片（右上角独立重置；每卡展示自己的开始时间与已运行时长）
        let cardSpecs: [(InterfaceCategory, CGFloat)] = [
            (.wifi, 24),
            (.iphone, 376),
        ]
        for (category, x) in cardSpecs {
            let card = roundedCard(frame: NSRect(x: x, y: 180, width: 320, height: 126))
            content.addSubview(card)
            updateBaseViews.append(card)

            let title = makeLabel(size: 13, color: .labelColor, weight: .semibold)
            title.frame = NSRect(x: 18, y: 94, width: 200, height: 18)
            if let resetIcon = NSImage(systemSymbolName: "arrow.counterclockwise",
                                       accessibilityDescription: "重置计量") {
                let reset = NSButton(image: resetIcon, target: self, action: #selector(resetCategory(_:)))
                reset.isBordered = false
                reset.contentTintColor = .secondaryLabelColor
                reset.setFrameOrigin(NSPoint(x: 320 - 34, y: 92))
                reset.toolTip = "重置计量"
                reset.identifier = NSUserInterfaceItemIdentifier(category == .wifi ? "wifi" : "iphone")
                card.contentView?.addSubview(reset)
            }

            let rate = makeLabel(size: 12, color: .labelColor, weight: .regular)
            rate.frame = NSRect(x: 18, y: 52, width: 284, height: 34)
            let total = makeLabel(size: 12, color: .secondaryLabelColor, weight: .regular)
            total.frame = NSRect(x: 18, y: 30, width: 284, height: 20)
            let meta = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
            meta.frame = NSRect(x: 18, y: 8, width: 284, height: 16)
            for label in [title, rate, total, meta] {
                card.contentView?.addSubview(label)
            }
            cards[category] = (rate, total, title, meta)
        }

        // 会话/告警汇总条：会话、总上传、总下载 + 状态着色的放大告警项
        let strip = roundedCard(frame: NSRect(x: 24, y: 322, width: 672, height: 48))
        content.addSubview(strip)
        updateBaseViews.append(strip)
        let summarySpecs: [(String, CGFloat)] = [
            ("会话", 18), ("总上传", 170), ("总下载", 320),
        ]
        for (caption, x) in summarySpecs {
            let captionLabel = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
            captionLabel.stringValue = caption
            captionLabel.frame = NSRect(x: x, y: 28, width: 130, height: 12)
            strip.contentView?.addSubview(captionLabel)
            let value = makeLabel(size: 12, color: .labelColor, weight: .semibold)
            value.frame = NSRect(x: x, y: 8, width: 130, height: 18)
            value.lineBreakMode = .byClipping
            strip.contentView?.addSubview(value)
            summaryValues.append(value)
        }
        let alertCaption = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
        alertCaption.stringValue = "流量告警"
        alertCaption.frame = NSRect(x: 470, y: 28, width: 180, height: 12)
        strip.contentView?.addSubview(alertCaption)
        alertValueLabel = makeLabel(size: 14, color: .white, weight: .bold)
        alertValueLabel.frame = NSRect(x: 470, y: 6, width: 190, height: 22)
        alertValueLabel.lineBreakMode = .byClipping
        strip.contentView?.addSubview(alertValueLabel)

        let sectionLabel = makeLabel(size: 11, color: .secondaryLabelColor, weight: .medium)
        sectionLabel.stringValue = "实时速率 · 近 120 秒"
        sectionLabel.frame = NSRect(x: 24, y: 148, width: 672, height: 16)
        content.addSubview(sectionLabel)
        updateBaseViews.append(sectionLabel)

        graphView.frame = NSRect(x: 24, y: 36, width: 672, height: 106)
        content.addSubview(graphView)
        updateBaseViews.append(graphView)

        legendLabel = makeLabel(size: 11, color: .secondaryLabelColor, weight: .regular)
        legendLabel.frame = NSRect(x: 24, y: 12, width: 672, height: 18)
        content.addSubview(legendLabel)
        updateBaseViews.append(legendLabel)
        updateLegend()

        // 图例行右端的当前版本号小字（无更新时的唯一展示）
        updateVersionLabel = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
        updateVersionLabel.frame = NSRect(x: 520, y: 14, width: 176, height: 14)
        updateVersionLabel.alignment = .right
        updateVersionLabel.stringValue = "v\(AppVersion.current)"
        content.addSubview(updateVersionLabel)

        // 软件更新卡片：仅在有更新进行时展开（默认隐藏）
        let updateCard = roundedCard(frame: NSRect(x: 24, y: 8, width: 672, height: 76))
        content.addSubview(updateCard)
        updateCardBox = updateCard
        updateCardBox.isHidden = true
        let updateCaption = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
        updateCaption.stringValue = "软件更新"
        updateCaption.frame = NSRect(x: 18, y: 56, width: 200, height: 12)
        updateCard.contentView?.addSubview(updateCaption)
        updateStatusLabel = makeLabel(size: 12, color: .labelColor, weight: .semibold)
        updateStatusLabel.frame = NSRect(x: 18, y: 30, width: 390, height: 20)
        updateStatusLabel.lineBreakMode = .byClipping
        updateCard.contentView?.addSubview(updateStatusLabel)
        updateNotesLabel = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
        updateNotesLabel.frame = NSRect(x: 18, y: 8, width: 390, height: 20)
        updateNotesLabel.lineBreakMode = .byTruncatingTail
        updateCard.contentView?.addSubview(updateNotesLabel)
        updatePrimaryButton = NSButton(title: "检查更新", target: self, action: #selector(updatePrimaryAction))
        updatePrimaryButton.frame = NSRect(x: 420, y: 24, width: 118, height: 28)
        updatePrimaryButton.bezelStyle = .rounded
        updateCard.contentView?.addSubview(updatePrimaryButton)
        updateSecondaryButton = NSButton(title: "", target: self, action: #selector(updateSecondaryAction))
        updateSecondaryButton.frame = NSRect(x: 546, y: 24, width: 110, height: 28)
        updateSecondaryButton.bezelStyle = .rounded
        updateSecondaryButton.isHidden = true
        updateCard.contentView?.addSubview(updateSecondaryButton)
        updateProgress = NSProgressIndicator(frame: NSRect(x: 420, y: 10, width: 236, height: 8))
        updateProgress.isIndeterminate = false
        updateProgress.minValue = 0
        updateProgress.maxValue = 1
        updateProgress.isHidden = true
        updateCard.contentView?.addSubview(updateProgress)
        refreshUpdateCard()
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

    // MARK: - 软件更新卡片

    /// 服务状态变化与每秒刷新共用；只有真正有更新进行时才展开卡片框架，
    /// 否则窗口保持原高，仅图例行右端展示当前版本号小字
    func refreshUpdateCard() {
        updateVersionLabel.stringValue = "v\(AppVersion.current)"
        setUpdateCardVisible(UpdatePresentation.wantsCard(for: updateService.state))
        guard updateCardVisible else { return }
        let content = UpdatePresentation.cardContent(for: updateService.state,
                                                     currentVersion: AppVersion.current,
                                                     lastCheck: updateService.lastCheckDate,
                                                     errorText: updateService.lastError)
        updateStatusLabel.stringValue = content.status
        updateStatusLabel.textColor = color(for: content.kind)
        updateNotesLabel.stringValue = content.notes
        if case .downloading(let progress) = updateService.state {
            updateProgress.isHidden = false
            updateProgress.doubleValue = progress
        } else {
            updateProgress.isHidden = true
        }
        updatePrimaryButton.title = content.primary ?? ""
        updatePrimaryButton.isHidden = content.primary == nil
        updateSecondaryButton.title = content.secondary ?? ""
        updateSecondaryButton.isHidden = content.secondary == nil
    }

    /// 展开卡片时窗口向下扩 84pt（顶边不动），基础视图整体上移让出底部空间；
    /// 收起时反向还原
    private func setUpdateCardVisible(_ visible: Bool) {
        guard updateCardVisible != visible else { return }
        updateCardVisible = visible
        let dy: CGFloat = visible ? 84 : -84
        for view in updateBaseViews {
            view.frame.origin.y += dy
        }
        updateCardBox.isHidden = !visible
        updateVersionLabel.isHidden = visible
        var frame = window.frame
        if visible {
            frame.origin.y -= 84
            frame.size.height += 84
        } else {
            frame.origin.y += 84
            frame.size.height -= 84
        }
        window.setFrame(frame, display: true)
    }

    private func color(for kind: UpdatePresentation.CardKind) -> NSColor {
        switch kind {
        case .neutral: return .labelColor
        case .ok: return .systemGreen
        case .attention: return .systemOrange
        case .error: return .systemRed
        }
    }

    @objc private func updatePrimaryAction() {
        switch updateService.state {
        case .available: updateService.startDownload()
        case .downloaded: updateService.installNow()
        default: updateService.checkNow()
        }
    }

    @objc private func updateSecondaryAction() {
        switch updateService.state {
        case .available(let release):
            if let url = URL(string: release.htmlUrl) { NSWorkspace.shared.open(url) }
        case .downloaded: updateService.cancelStagedUpdate()
        case .downloading: updateService.cancelDownload()
        default: break
        }
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
            let interface = monitor.interfaceByCategory[category].map { "  ·  \($0)" } ?? ""
            let rate = category == .wifi ? monitor.wifiRate : monitor.iphoneRate
            let present = monitor.interfaceByCategory[category] != nil
            let running = Self.isRunning(present: present, rx: usage.rx, tx: usage.tx)

            if running {
                // 运行中：绿点 + 标题
                let titleText = NSMutableAttributedString()
                titleText.append(NSAttributedString(string: "● ", attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: NSColor.systemGreen,
                ]))
                titleText.append(NSAttributedString(string: "\(name)\(interface)", attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ]))
                labels.title.attributedStringValue = titleText
                let seconds = max(0, Int(Date().timeIntervalSince(usage.startTime)))
                labels.meta.stringValue = "开始 \(usage.startTime.formatted(date: .omitted, time: .shortened)) · 已运行 \(Self.durationText(seconds))"
                labels.meta.textColor = .tertiaryLabelColor
            } else {
                // 未启用：白灰标题 + 提示，不计时
                labels.title.attributedStringValue = NSAttributedString(string: "\(name)\(interface)", attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
                labels.meta.stringValue = "当前还没有启用"
                labels.meta.textColor = .tertiaryLabelColor
            }

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

        // 会话/告警汇总条
        let sessionStart = store.sessionStart
        let totalRX = store.wifi.rx + store.iphone.rx
        let totalTX = store.wifi.tx + store.iphone.tx
        let total = monitor.totalRate
        let seconds = max(0, Int(Date().timeIntervalSince(sessionStart)))
        summaryValues[0].stringValue = "\(sessionStart.formatted(date: .omitted, time: .shortened)) · \(Self.durationText(seconds))"
        summaryValues[1].stringValue = "↑ \(ByteFormat.string(totalTX))"
        summaryValues[2].stringValue = "↓ \(ByteFormat.string(totalRX))"

        let alertState = alertStateProvider?()
        let strip = Self.alertStrip(threshold: alertState?.threshold, fired: alertState?.fired ?? false,
                                    progressBytes: alertState?.progressBytes ?? 0)
        alertValueLabel.stringValue = strip.text
        switch strip.state {
        case .unset: alertValueLabel.textColor = .white
        case .armed: alertValueLabel.textColor = .systemOrange
        case .fired: alertValueLabel.textColor = .systemRed
        }

        graphView.history = monitor.history
        graphView.downloadLabel = "↓\(ByteFormat.rate(total.rx))"
        graphView.uploadLabel = "↑\(ByteFormat.rate(total.tx))"

        refreshUpdateCard()
    }

    /// 模块运行中 = 接口在线且已有计量流量（纯函数，可测）
    nonisolated static func isRunning(present: Bool, rx: UInt64, tx: UInt64) -> Bool {
        present && (rx > 0 || tx > 0)
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
