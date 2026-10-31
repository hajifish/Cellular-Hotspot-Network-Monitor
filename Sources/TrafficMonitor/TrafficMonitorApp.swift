import AppKit
import Foundation
import os
import UserNotifications

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
final class MenuBarController: NSObject, NSMenuDelegate, UNUserNotificationCenterDelegate {
    static let gigabyte: UInt64 = 1_000_000_000
    static let megabyte: UInt64 = 1_000_000
    static let alertDefaultsKey = "alertThresholdBytes"
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
        // 里程碑与告警都依赖系统通知，首次启动请求授权（已授权则静默返回）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // 任一模块重置后，告警基线挪到新的总量（进度清零并重新武装），里程碑对齐
        monitor.onReset = { [weak self] in
            guard let self else { return }
            let total = self.currentMeteredTotal()
            self.alert.reset(baselineBytes: total)
            self.milestoneTracker.resync(totalBytes: total)
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
        UNUserNotificationCenter.current().delegate = self
        updateService.startAutomaticChecks()
        monitor.start()
        refresh()
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
        // 诊断/验证用：启动即设一个极低阈值（如 TRAFFICMONITOR_ALERT_MB=1）
        if let debugMB = ProcessInfo.processInfo.environment["TRAFFICMONITOR_ALERT_MB"],
           let value = Double(debugMB), value > 0 {
            alert.setThreshold(UInt64(value * Double(Self.megabyte)), baselineBytes: 0)
            return
        }
        let stored = UserDefaults.standard.object(forKey: Self.alertDefaultsKey) as? Int64
        alert.setThreshold(stored.map { UInt64(max(0, $0)) }, baselineBytes: 0)
    }

    private func currentMeteredTotal() -> UInt64 {
        Self.meteredTotal(of: monitor)
    }

    /// 各模块收/发累计之和（模块集合见 InterfaceCategory）：告警与里程碑的合并流量口径
    static func meteredTotal(of monitor: TrafficMonitor) -> UInt64 {
        let store = monitor.store
        return store.wifi.rx + store.wifi.tx + store.iphone.rx + store.iphone.tx
    }

    /// 应用告警阈值的编排核心（静态编排函数：不依赖 UI/持久化，会修改传入的 monitor/alert，自测直接调用）：
    /// 实际阈值 + 同步重置 → 先补一拍结算（模态弹窗期间采样停摆），再清零全部累计、以 0 为告警基线；
    /// bytes 为 nil（切「关闭」）时无论 syncReset 为何都不得动累计（守卫）。
    static func applyAlertThreshold(_ bytes: UInt64?, syncReset: Bool,
                                    monitor: TrafficMonitor, alert: TrafficAlert) {
        if bytes != nil {
            // 调用前可能经历了 runModal 模态（采样定时器停摆）；
            // 先补一拍把这段时间的流量结算进旧周期，再重置/读基线
            monitor.tick()
        }
        if let bytes, syncReset {
            monitor.reset(nil)
        }
        alert.setThreshold(bytes, baselineBytes: meteredTotal(of: monitor))
    }

    private func applyAlertThreshold(_ bytes: UInt64?, persist: Bool) {
        // 设置实际阈值时询问是否同步清零全部累计、重新计量（切「关闭」不问）
        let syncReset = bytes != nil && askSyncReset() // && 短路：仅设实际阈值时弹窗
        Self.applyAlertThreshold(bytes, syncReset: syncReset, monitor: monitor, alert: alert)
        if persist {
            if let bytes {
                UserDefaults.standard.set(Int64(bytes), forKey: Self.alertDefaultsKey)
                requestNotificationAuthorization()
            } else {
                UserDefaults.standard.removeObject(forKey: Self.alertDefaultsKey)
            }
        }
        refreshAlertMenuStates()
    }

    /// 设置新告警阈值时询问是否同步重置所有累计流量并重新计量。
    /// 注意：runModal() 进入模态 run loop——激活本应用、阻塞调用点直到用户作答，
    /// 期间采样定时器停摆（编排函数 applyAlertThreshold 会先补一拍结算）。
    /// - Returns: true 表示用户选择「同步重置」；false 表示「仅设置告警」/取消（Esc）
    private func askSyncReset() -> Bool {
        let dialog = NSAlert()
        dialog.messageText = "是否同步重置累计流量？"
        dialog.informativeText = "将清零所有模块的累计流量并重新开始计时，速率曲线与里程碑同步归零，告警进度从 0 起算。此操作不可撤销。\n选择「仅设置告警」则保留现有累计与计时，告警进度从当前时刻起算。"
        dialog.addButton(withTitle: "同步重置")
        dialog.addButton(withTitle: "仅设置告警")
        NSApp.activate(ignoringOtherApps: true)
        return dialog.runModal() == .alertFirstButtonReturn
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

    /// 每 1 GB 里程碑：自上次重置起累计每满 1 GB 提醒一条
    private func checkMilestone() {
        let totalBytes = currentMeteredTotal()
        guard let reached = milestoneTracker.update(totalBytes: totalBytes) else { return }
        let gb = reached / MenuBarController.gigabyte
        logger.info("milestone reached: \(gb, privacy: .public) GB, total=\(ByteFormat.string(totalBytes), privacy: .public)")
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 流量里程碑"
        content.body = "累计已用 \(ByteFormat.string(totalBytes))。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            _ = error // 通知不可用时静默：里程碑仅为提示性质
        }
    }

    private func fireAlert(usedBytes: UInt64) {
        let used = ByteFormat.string(usedBytes)
        let limit = ByteFormat.string(alert.threshold ?? 0)
        logger.info("alert fired: used=\(used, privacy: .public) threshold=\(limit, privacy: .public)")
        NSSound(named: "Tink")?.play() // 简单的"滴"一声，无论通知权限如何都会响
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 流量告警"
        content.body = "已用 \(used)，达到 \(limit)。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.showFallbackAlert(used: used, limit: limit) }
            }
        }
    }

    /// 通知不可用时的兜底：应用内弹窗
    private func showFallbackAlert(used: String, limit: String) {
        let dialog = NSAlert()
        dialog.alertStyle = .warning
        dialog.messageText = "流量告警"
        dialog.informativeText = "自开始计时已使用 \(used)，达到设定的 \(limit)。"
        dialog.addButton(withTitle: "好的")
        NSApp.activate(ignoringOtherApps: true)
        dialog.runModal()
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Task { @MainActor in
                    self.logger.error("notification auth error: \(String(describing: error), privacy: .public)")
                }
            } else if !granted {
                Task { @MainActor in
                    self.logger.info("notification auth denied; will use in-app dialog")
                }
            }
        }
    }

    // MARK: - 软件更新（主页卡片是唯一更新入口，菜单栏不展示更新内容）

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

    /// 「检查更新」：已知有新版本（手动或自动检测到）→ 直达主页升级界面；
    /// 否则发起一次检查，发现新版本后条目文字追加「有新版本」（refresh 驱动）
    @objc private func checkUpdatesAction() {
        if UpdatePresentation.wantsCard(for: updateService.state) {
            openHome()
        } else {
            updateService.checkNow()
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

extension MenuBarController {
    /// 点击更新通知 → 打开主页更新卡片
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("update-") {
            openHome()
        }
        completionHandler()
    }

    /// 应用前台时通知横幅也显示（对既有告警/里程碑通知同为改善）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
