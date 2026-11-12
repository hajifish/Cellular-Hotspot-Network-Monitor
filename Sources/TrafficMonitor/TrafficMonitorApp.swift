import AppKit
import Foundation
import os

@MainActor
private final class AlertResetDialog: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 390, height: 340),
                   styleMask: [.titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(buttonType)?.isHidden = true
        }
        let content = NSView()
        contentView = content

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        let title = NSTextField(labelWithString: "如何开始计算新的流量告警？")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .boldSystemFont(ofSize: 16)
        content.addSubview(title)

        let cancelButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill",
                           accessibilityDescription: "取消")!,
            target: self,
            action: #selector(cancel)
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.isBordered = false
        cancelButton.setAccessibilityLabel("取消")
        cancelButton.keyEquivalent = "\u{1b}"
        content.addSubview(cancelButton)

        let details = NSTextField(wrappingLabelWithString:
            "「仅调整告警」会保留所有模块当前的累计流量和计时，并将现有累计计入新告警进度；弹窗期间产生的流量也会计入。\n\n「归零重置」会清空所有模块的累计流量、重新开始计时，并清除速率曲线和里程碑进度；新告警从 0 开始计算。此操作不可撤销。"
        )
        details.translatesAutoresizingMaskIntoConstraints = false
        details.maximumNumberOfLines = 0
        content.addSubview(details)

        let keepButton = NSButton(title: "仅调整告警", target: self, action: #selector(choose(_:)))
        keepButton.translatesAutoresizingMaskIntoConstraints = false
        keepButton.bezelStyle = .rounded
        keepButton.tag = 1
        content.addSubview(keepButton)

        let resetButton = NSButton(title: "归零重置", target: self, action: #selector(choose(_:)))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.bezelStyle = .rounded
        resetButton.bezelColor = .controlAccentColor
        resetButton.contentTintColor = .white
        resetButton.keyEquivalent = "\r"
        resetButton.tag = 2
        content.addSubview(resetButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -8),
            cancelButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            cancelButton.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),
            details.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            details.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            details.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 20),
            details.bottomAnchor.constraint(lessThanOrEqualTo: keepButton.topAnchor, constant: -20),
            keepButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            keepButton.trailingAnchor.constraint(equalTo: resetButton.leadingAnchor, constant: -12),
            keepButton.widthAnchor.constraint(equalTo: resetButton.widthAnchor),
            resetButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            keepButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            resetButton.bottomAnchor.constraint(equalTo: keepButton.bottomAnchor),
            keepButton.heightAnchor.constraint(equalToConstant: 32),
            resetButton.heightAnchor.constraint(equalTo: keepButton.heightAnchor),
        ])
    }

    @objc private func choose(_ sender: NSButton) {
        finish(sender.tag == 1 ? .alertFirstButtonReturn : .alertSecondButtonReturn)
    }

    @objc private func cancel() {
        finish(.abort)
    }

    private func finish(_ response: NSApplication.ModalResponse) {
        NSApp.stopModal(withCode: response)
        orderOut(nil)
    }
}

@main
struct Main {
    static func main() {
        if ProcessInfo.processInfo.environment["TRAFFICMONITOR_SELFTEST"] == "1" {
            MainActor.assumeIsolated { SelfTest.run() }
        }
        MainActor.assumeIsolated { MenuBarController.run() }
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let gigabyte: UInt64 = 1_000_000_000
    static let megabyte: UInt64 = 1_000_000
    static let alertDefaultsKey = "alertThresholdBytes"
    /// 首次启动已展示过主页的标记（此后启动不再自动弹出）
    static let firstLaunchHomeKey = "didShowHomeOnFirstLaunch"
    static private(set) var shared: MenuBarController!

    private let monitor = TrafficMonitor()
    private let updateService: UpdateService
    private let homeController: HomePageController
    private let alert = TrafficAlert()
    private let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "alert")
    private var statusItem: NSStatusItem!
    private var startTimeItem: NSMenuItem!
    private var wifiItem: NSMenuItem!
    private var iphoneItem: NSMenuItem!
    private var totalItem: NSMenuItem!
    private var alertMenu: NSMenu!
    private var alertItem: NSMenuItem!
    private var checkUpdateItem: NSMenuItem!
    private var milestoneTracker = MilestoneTracker()
    private var changeObserverID: UUID?

    static func run() {
        let app = NSApplication.shared
        let controller = MenuBarController()
        shared = controller
        controller.install()
        app.setActivationPolicy(.accessory) // 无 Dock 图标
        app.run()
    }

    override init() {
        updateService = UpdateService()
        homeController = HomePageController(monitor: monitor, updateService: updateService)
        super.init()
        restoreAlertThreshold()
        StatusBarPrefs.migrateLegacyMode()
    }

    private func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        startTimeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        wifiItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        iphoneItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        totalItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        let openHome = NSMenuItem(title: "打开主页", action: #selector(openHome), keyEquivalent: "0")
        openHome.target = self
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        alertItem = NSMenuItem(title: "流量告警", action: nil, keyEquivalent: "")
        alertMenu = buildAlertMenu()
        alertItem.submenu = alertMenu

        menu.addItem(startTimeItem)
        menu.addItem(.separator())
        menu.addItem(wifiItem)
        menu.addItem(iphoneItem)
        menu.addItem(totalItem)
        menu.addItem(.separator())
        menu.addItem(openHome)
        menu.addItem(alertItem)
        checkUpdateItem = NSMenuItem(title: "检查更新", action: #selector(checkUpdatesAction), keyEquivalent: "")
        checkUpdateItem.target = self
        menu.addItem(checkUpdateItem)
        menu.addItem(.separator())
        menu.addItem(quit)

        statusItem.menu = menu
        changeObserverID = monitor.addObserver { [weak self] in
            self?.refresh()
            self?.checkAlert()
            self?.checkMilestone()
        }
        // 任一模块重置后，告警基线挪到新的总量（进度清零并重新武装），预告从头开始
        monitor.onReset = { [weak self] in
            guard let self else { return }
            let total = self.currentMeteredTotal()
            self.alert.reset(baselineBytes: total)
            if let threshold = self.alert.threshold {
                self.milestoneTracker.arm(thresholdBytes: threshold, progressBytes: 0)
            }
        }
        homeController.alertStateProvider = { [weak self] in
            guard let self else { return (threshold: nil, fired: false, progressBytes: 0) }
            let total = self.currentMeteredTotal()
            return (threshold: self.alert.threshold,
                    fired: self.alert.fired,
                    progressBytes: self.alert.progress(totalBytes: total))
        }
        updateService.onStateChange = { [weak self] in
            self?.homeController.refreshUpdateCard()
        }
        updateService.confirmRestartHandler = { [weak self] release, completion in
            self?.showRestartConfirm(release: release, completion: completion)
        }
        // 通知点击路由 + 授权请求（UN delegate 接线与授权已收编在 SystemNotifier，勿另处重复请求）：
        // 更新类通知（"update-" 前缀）点击后打开主页（沿用 0.9.x 行为）
        SystemNotifier.configureActivation { [weak self] identifier in
            guard identifier.hasPrefix("update-") else { return }
            self?.openHome()
        }
        updateService.startAutomaticChecks()
        monitor.start()
        refresh()
        // 首次启动（装机后第一次运行）默认打开主页，让新用户发现仪表盘；此后不再自动弹出
        // （2026-11-05 需求；SHOWHOME 环境变量仍为诊断用强制开关）
        if !UserDefaults.standard.bool(forKey: Self.firstLaunchHomeKey) {
            UserDefaults.standard.set(true, forKey: Self.firstLaunchHomeKey)
            homeController.show()
        }
        // 诊断/验证用：启动即打开主页 / 弹出菜单（重截截图等验证场景）
        if ProcessInfo.processInfo.environment["TRAFFICMONITOR_SHOWHOME"] == "1" {
            homeController.show()
        }
        if ProcessInfo.processInfo.environment["TRAFFICMONITOR_SHOWMENU"] == "1" {
            statusItem.button?.performClick(nil)
        }
    }

    // MARK: - 状态栏内容

    /// 状态栏：内容渲染为整张图片交给按钮垂直居中（多行文字不会被贴顶裁切）；
    /// 仅图标模式显示软件 `↑↓` 符号；告警铃铛始终追加在内容之后。
    /// 菜单栏恒为深色底，文字与箭头统一用白色单色风。
    private func updateStatusBarContent() {
        guard let button = statusItem.button else { return }
        let store = monitor.store
        let textColor = NSColor.white

        var content = NSMutableAttributedString()
        if let attributed = StatusBarFormatter.attributed(showRates: StatusBarPrefs.showRates,
                                                          showTotals: StatusBarPrefs.showTotals,
                                                          textColor: textColor,
                                                          totalRate: monitor.totalRate,
                                                          totalRX: store.wifi.rx + store.iphone.rx,
                                                          totalTX: store.wifi.tx + store.iphone.tx) {
            content.append(attributed)
        } else if let icon = MenuTextBuilder.tintedSymbol("arrow.up.arrow.down",
                                                          color: textColor, size: 13) {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = NSRect(x: 0, y: -1, width: 13, height: 13)
            content.append(NSAttributedString(attachment: attachment))
        }

        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = renderedImage(of: content)
    }

    /// 把富文本渲染成位图（按钮对图片是垂直居中的，规避多行文本贴顶问题）。
    /// 文本已带显式颜色，无需外观解析。
    private func renderedImage(of text: NSAttributedString) -> NSImage {
        let bounds = text.boundingRect(with: NSSize(width: 400, height: 60),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let padding: CGFloat = 2
        let size = NSSize(width: ceil(bounds.width) + padding * 2,
                          height: ceil(bounds.height) + padding * 2)
        let image = NSImage(size: size)
        image.lockFocus()
        text.draw(at: NSPoint(x: padding, y: padding))
        image.unlockFocus()
        return image
    }

    // MARK: - 流量告警

    /// 预设档位（菜单展示与勾选判定共用）
    static let alertPresets: [(label: String, bytes: UInt64?)] = [
        ("关闭", nil),
        ("500 MB", 500 * MenuBarController.megabyte),
        ("1 GB", 1 * MenuBarController.gigabyte),
        ("2 GB", 2 * MenuBarController.gigabyte),
        ("3 GB", 3 * MenuBarController.gigabyte),
        ("5 GB", 5 * MenuBarController.gigabyte),
        ("10 GB", 10 * MenuBarController.gigabyte),
        ("20 GB", 20 * MenuBarController.gigabyte),
    ]
    private var customAlertItem: NSMenuItem!

    private func buildAlertMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let caption = NSMenuItem(title: "按所有模块累计上行 + 下行的合并流量提醒一次",
                                 action: nil, keyEquivalent: "")
        caption.isEnabled = false
        caption.attributedTitle = NSAttributedString(string: caption.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        submenu.addItem(caption)
        submenu.addItem(.separator())

        for preset in Self.alertPresets {
            let item = NSMenuItem(title: preset.label, action: #selector(selectAlertPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.bytes.map { NSNumber(value: $0) }
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let custom = NSMenuItem(title: "自定义…", action: #selector(showCustomAlertThreshold), keyEquivalent: "")
        custom.target = self
        customAlertItem = custom
        submenu.addItem(custom)
        return submenu
    }

    private func restoreAlertThreshold() {
        // 阈值来源：诊断/验证用环境变量（如 TRAFFICMONITOR_ALERT_MB=1）优先，否则取持久化值
        let threshold: UInt64?
        if let debugMB = ProcessInfo.processInfo.environment["TRAFFICMONITOR_ALERT_MB"],
           let value = Double(debugMB), value > 0 {
            threshold = UInt64(value * Double(Self.megabyte))
        } else {
            let stored = UserDefaults.standard.object(forKey: Self.alertDefaultsKey) as? Int64
            threshold = stored.map { UInt64(max(0, $0)) }
        }
        alert.setThreshold(threshold, baselineBytes: 0)
        // 启动恢复即视为「已设置」：预告按当前告警进度武装，不按旧量补发（2026-11-05）
        if let threshold {
            milestoneTracker.arm(thresholdBytes: threshold,
                                 progressBytes: alert.progress(totalBytes: currentMeteredTotal()))
        }
    }

    private func currentMeteredTotal() -> UInt64 {
        Self.meteredTotal(of: monitor)
    }

    /// 各模块收/发累计之和（模块集合见 InterfaceCategory）：告警与里程碑的合并流量口径
    static func meteredTotal(of monitor: TrafficMonitor) -> UInt64 {
        let store = monitor.store
        return store.wifi.rx + store.wifi.tx + store.iphone.rx + store.iphone.tx
    }

    /// 应用告警阈值的编排核心（静态编排函数：不依赖 UI/持久化，自测直接调用）：
    /// 实际阈值 + 同步重置 → 先补一拍结算（模态弹窗期间采样停摆），再清零全部累计、以 0 为告警基线；
    /// 仅设置告警 → 保留累计并将全部当前累计计入新告警进度；
    /// bytes 为 nil（切「关闭」）时无论 syncReset 为何都不得动累计（守卫）。
    /// 设置实际阈值时返回按当前告警进度武装后的预告（首个未过检查点起预告——
    /// 关闭期间越过的检查点不补发，2026-11-05 需求）；
    /// 关闭时返回 nil = 调用方实例侧里程碑保持不动（observer 期间的推进不回卷）。
    /// ⚠️ milestone 必须按值传入、以返回值带回，不能用 inout：tick/reset 会同步触发
    /// observer 重入 checkMilestone 的 &milestoneTracker，inout 的独占访问横跨重入
    /// 会触发 Swift 运行时独占检查 fatalError（v0.9.0/0.9.1「设置告警即崩」的根因）。
    @discardableResult
    static func applyAlertThreshold(_ bytes: UInt64?, syncReset: Bool,
                                    monitor: TrafficMonitor, alert: TrafficAlert,
                                    milestone: MilestoneTracker) -> MilestoneTracker? {
        if bytes != nil {
            // 调用前可能经历了 runModal 模态（采样定时器停摆）；
            // 先补一拍把这段时间的流量结算进旧周期，再重置/读基线
            monitor.tick()
        }
        if bytes != nil, syncReset {
            monitor.reset(nil)
        }
        alert.setThreshold(bytes, baselineBytes: syncReset ? meteredTotal(of: monitor) : 0)
        guard let bytes else { return nil }
        var milestone = milestone
        milestone.arm(thresholdBytes: bytes,
                      progressBytes: alert.progress(totalBytes: meteredTotal(of: monitor)))
        return milestone
    }

    private func applyAlertThreshold(_ bytes: UInt64?, persist: Bool) {
        // 设置实际阈值时询问是否同步清零全部累计、重新计量（切「关闭」不问）
        let syncReset = bytes != nil && askSyncReset() // && 短路：仅设实际阈值时弹窗
        if let aligned = Self.applyAlertThreshold(bytes, syncReset: syncReset, monitor: monitor,
                                                  alert: alert, milestone: milestoneTracker) {
            milestoneTracker = aligned
        }
        if persist {
            if let bytes {
                UserDefaults.standard.set(Int64(bytes), forKey: Self.alertDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.alertDefaultsKey)
            }
        }
        refreshAlertMenuStates()
    }

    static func shouldResetAlert(modalResponse: NSApplication.ModalResponse) -> Bool {
        modalResponse == .alertSecondButtonReturn
    }

    /// 设置新告警阈值时询问是否同步重置所有累计流量并重新计量。
    /// 注意：runModal() 进入模态 run loop——激活本应用、阻塞调用点直到用户作答，
    /// 期间采样定时器停摆（编排函数 applyAlertThreshold 会先补一拍结算）。
    /// - Returns: true 表示用户明确选择「归零重置」；关闭（包括 Esc）按 false 处理
    private func askSyncReset() -> Bool {
        let dialog = AlertResetDialog()
        NSApp.activate(ignoringOtherApps: true)
        dialog.center()
        let response = NSApp.runModal(for: dialog)
        dialog.orderOut(nil)
        return Self.shouldResetAlert(modalResponse: response)
    }

    @objc private func selectAlertPreset(_ sender: NSMenuItem) {
        let bytes = (sender.representedObject as? NSNumber)?.uint64Value
        guard bytes != alert.threshold else { return } // 与当前设置相同，无需动作
        applyAlertThreshold(bytes, persist: true)
    }

    @objc private func showCustomAlertThreshold() {
        let dialog = NSAlert()
        dialog.messageText = "自定义流量告警阈值"
        dialog.informativeText = "输入达到时提醒的合并流量（所有模块累计上行 + 下行）。示例：5 GB、500 MB。\n设置后提醒进度将重新计算，已触发的提醒状态会被清除。"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "5 GB"
        dialog.accessoryView = input
        dialog.addButton(withTitle: "设置")
        dialog.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .alertFirstButtonReturn,
              let bytes = Self.parseThreshold(input.stringValue) else { return }
        applyAlertThreshold(bytes, persist: true)
    }

    /// 解析 "5 GB"、"500 MB"、"2"（缺省 GB）为字节数；无效输入返回 nil
    static func parseThreshold(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        var numberPart = trimmed
        var multiplier: UInt64 = Self.gigabyte
        if trimmed.hasSuffix("MB") {
            numberPart = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
            multiplier = Self.megabyte
        } else if trimmed.hasSuffix("GB") {
            numberPart = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        guard let value = Double(numberPart), value > 0 else { return nil }
        return UInt64(value * Double(multiplier))
    }

    private func refreshAlertMenuStates() {
        let threshold = alert.threshold
        var matchedPreset = false
        for item in alertMenu.items where item.action == #selector(selectAlertPreset(_:)) {
            let bytes = (item.representedObject as? NSNumber)?.uint64Value
            let on = bytes == threshold
            item.state = on ? .on : .off
            matchedPreset = matchedPreset || on
        }
        // 自定义阈值：回显当前值并勾选
        if let threshold {
            customAlertItem.title = matchedPreset ? "自定义…" : "自定义 · \(ByteFormat.string(threshold))"
            customAlertItem.state = matchedPreset ? .off : .on
        } else {
            customAlertItem.title = "自定义…"
            customAlertItem.state = .off
        }
    }

    /// 每秒检查：告警进度（当前总量 − 基线）越过阈值则触发一次
    private func checkAlert() {
        let totalBytes = currentMeteredTotal()
        let progress = alert.progress(totalBytes: totalBytes)
        if alert.threshold != nil {
            logger.debug("checkAlert progress=\(progress, privacy: .public) threshold=\(self.alert.threshold ?? 0, privacy: .public) fired=\(self.alert.fired, privacy: .public)")
        }
        guard alert.check(totalBytes: totalBytes) else { return }
        fireAlert(usedBytes: progress)
    }

    /// 里程碑门控（静态编排）：告警未设置 → 整体静默且 tracker 冻结不推进；
    /// 已设置 → 透传 tracker.update（返回本次越过的检查点，无则 nil）
    static func milestoneReached(progressBytes: UInt64, alertThreshold: UInt64?,
                                 tracker: inout MilestoneTracker) -> UInt64? {
        guard alertThreshold != nil else { return nil }
        return tracker.update(progressBytes: progressBytes)
    }

    /// 阈值临近预告：按阈值三档检查点逐级提醒，口径为告警进度（总量 − 基线）——
    /// 预告是向额度倒计时，中途设阈值（不重置）时才与告警进度一致；
    /// 仅在设置了流量告警时启用（2026-11-05 需求），关闭告警即整体静默
    private func checkMilestone() {
        let progress = alert.progress(totalBytes: currentMeteredTotal())
        guard let reached = Self.milestoneReached(progressBytes: progress,
                                                  alertThreshold: alert.threshold,
                                                  tracker: &milestoneTracker),
              let threshold = alert.threshold else { return }
        let remainingPercent = Int(((1 - Double(reached) / Double(threshold)) * 100).rounded())
        logger.info("milestone preview: \(ByteFormat.string(reached), privacy: .public) / \(ByteFormat.string(threshold), privacy: .public), remaining=\(remainingPercent, privacy: .public)%")
        SystemNotifier.post(title: "Traffic Monitor 流量预告",
                            body: "已用 \(ByteFormat.string(reached)) / \(ByteFormat.string(threshold))，剩余约 \(remainingPercent)%。",
                            identifier: UUID().uuidString)
    }

    private func fireAlert(usedBytes: UInt64) {
        let used = ByteFormat.string(usedBytes)
        let limit = ByteFormat.string(alert.threshold ?? 0)
        logger.info("alert fired: used=\(used, privacy: .public) threshold=\(limit, privacy: .public)")
        NSSound(named: "Tink")?.play() // 简单的"滴"一声，无论通知权限如何都会响
        SystemNotifier.post(title: "Traffic Monitor 流量告警",
                            body: "已用 \(used)，达到 \(limit)。",
                            identifier: UUID().uuidString,
                            onFailure: { [weak self] _ in
                                // onFailure 已由 SystemNotifier 派发主线程；Task 只为静态跨 MainActor 隔离
                                Task { @MainActor in self?.showFallbackAlert(used: used, limit: limit) }
                            })
    }

    /// 通知投递失败时的兜底：应用内模态弹窗（0.9.1 语义）
    private func showFallbackAlert(used: String, limit: String) {
        let dialog = NSAlert()
        dialog.alertStyle = .warning
        dialog.messageText = "流量告警"
        dialog.informativeText = "自开始计时已使用 \(used)，达到设定的 \(limit)。"
        dialog.addButton(withTitle: "好的")
        NSApp.activate(ignoringOtherApps: true)
        dialog.runModal()
    }

    // MARK: - 软件更新（主页卡片是唯一升级操作入口；菜单条目仅以状态后缀提示）

    /// 下载完成后的确认弹窗（用户决策：确认后才换包重启）
    private func showRestartConfirm(release: ReleaseInfo, completion: @escaping (Bool) -> Void) {
        let dialog = NSAlert()
        dialog.messageText = "更新已就绪"
        dialog.informativeText = "新版本 \(release.tagName) 已下载并校验完成。立即重启以完成更新？"
        dialog.addButton(withTitle: "立即重启")
        dialog.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        completion(dialog.runModal() == .alertFirstButtonReturn)
    }

    @objc private func openHome() {
        homeController.show()
    }

    /// 「检查更新」路由与 `wantsCard` 耦合：`.available/.downloading/.downloaded/.installing/.failed`
    /// 这些有卡片态 → 直达主页（`.failed` 展示失败卡片，「重试」入口在卡片上，此处不发起检查）；
    /// `.idle/.checking/.upToDate` 才发起一次手动检查（得出「已是最新」时发通知，与自动轮询区分）
    @objc private func checkUpdatesAction() {
        if UpdatePresentation.wantsCard(for: updateService.state) {
            openHome()
        } else {
            updateService.checkNow(manual: true)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        refreshAlertMenuStates()
    }

    private func refresh() {
        updateStatusBarContent()

        let store = monitor.store
        let sessionStart = store.sessionStart
        startTimeItem.attributedTitle = MenuTextBuilder.startTimeRow(
            startDate: sessionStart,
            elapsedSeconds: Int(Date().timeIntervalSince(sessionStart)))
        let specs = [
            MenuTextBuilder.InterfaceRowSpec(name: InterfaceCategory.wifi.displayName,
                                             rx: store.wifi.rx, tx: store.wifi.tx),
            MenuTextBuilder.InterfaceRowSpec(name: InterfaceCategory.iphone.displayName,
                                             rx: store.iphone.rx, tx: store.iphone.tx),
            MenuTextBuilder.InterfaceRowSpec(name: "合计",
                                             rx: store.wifi.rx + store.iphone.rx,
                                             tx: store.wifi.tx + store.iphone.tx),
        ]
        let stops = MenuTextBuilder.columnStops(forRows: specs)
        wifiItem.attributedTitle = MenuTextBuilder.interfaceRow(name: specs[0].name, rx: specs[0].rx,
                                                                tx: specs[0].tx, stops: stops)
        iphoneItem.attributedTitle = MenuTextBuilder.interfaceRow(name: specs[1].name, rx: specs[1].rx,
                                                                  tx: specs[1].tx, stops: stops)
        totalItem.attributedTitle = MenuTextBuilder.interfaceRow(name: specs[2].name, rx: specs[2].rx,
                                                                 tx: specs[2].tx, stops: stops, emphasized: true)
        let totalBytesForAlert = currentMeteredTotal()
        let alertProgress = alert.progress(totalBytes: totalBytesForAlert)
        let strip = HomePageController.alertStrip(threshold: alert.threshold,
                                                  fired: alert.fired,
                                                  progressBytes: alertProgress)
        let detail: String
        switch strip.state {
        case .unset: detail = ""
        case .armed: detail = strip.text
        case .fired: detail = "已触发"
        }
        alertItem.attributedTitle = MenuTextBuilder.alertHeader(
            armed: alert.threshold != nil, fired: alert.fired, detail: detail)
        checkUpdateItem.title = UpdatePresentation.menuCheckTitle(for: updateService.state)
    }
}
