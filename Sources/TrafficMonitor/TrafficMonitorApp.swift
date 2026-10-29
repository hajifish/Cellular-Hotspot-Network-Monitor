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
final class MenuBarController: NSObject, NSMenuDelegate {
    static let gigabyte: UInt64 = 1_000_000_000
    static let megabyte: UInt64 = 1_000_000
    static let alertDefaultsKey = "alertThresholdBytes"
    static private(set) var shared: MenuBarController!

    private let monitor = TrafficMonitor()
    private let homeController: HomePageController
    private let alert = TrafficAlert()
    private let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "alert")
    private var statusItem: NSStatusItem!
    private var startTimeItem: NSMenuItem!
    private var wifiItem: NSMenuItem!
    private var iphoneItem: NSMenuItem!
    private var alertMenu: NSMenu!
    private var alertItem: NSMenuItem!
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
        homeController = HomePageController(monitor: monitor)
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
        menu.addItem(.separator())
        menu.addItem(openHome)
        menu.addItem(alertItem)
        menu.addItem(.separator())
        menu.addItem(quit)

        statusItem.menu = menu
        changeObserverID = monitor.addObserver { [weak self] in
            self?.refresh()
            self?.checkAlert()
        }
        // 任一模块重置后重新武装告警（总流量变小，需要重新越线才会再提醒）
        monitor.onReset = { [weak self] in self?.alert.reset() }
        homeController.alertStateProvider = { [weak self] in
            guard let self else { return (threshold: nil, fired: false) }
            return (threshold: self.alert.threshold, fired: self.alert.fired)
        }
        monitor.start()
        refresh()
        // 诊断/验证用：启动即打开主页
        if ProcessInfo.processInfo.environment["TRAFFICMONITOR_SHOWHOME"] == "1" {
            homeController.show()
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

    private func buildAlertMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let presets: [(String, UInt64?)] = [
            ("关闭", nil),
            ("1 GB", 1 * Self.gigabyte),
            ("2 GB", 2 * Self.gigabyte),
            ("5 GB", 5 * Self.gigabyte),
            ("10 GB", 10 * Self.gigabyte),
            ("20 GB", 20 * Self.gigabyte),
        ]
        for (title, bytes) in presets {
            let item = NSMenuItem(title: title, action: #selector(selectAlertPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bytes.map { NSNumber(value: $0) }
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let custom = NSMenuItem(title: "自定义…", action: #selector(showCustomAlertThreshold), keyEquivalent: "")
        custom.target = self
        submenu.addItem(custom)
        return submenu
    }

    private func restoreAlertThreshold() {
        // 诊断/验证用：启动即设一个极低阈值（如 TRAFFICMONITOR_ALERT_MB=1）
        if let debugMB = ProcessInfo.processInfo.environment["TRAFFICMONITOR_ALERT_MB"],
           let value = Double(debugMB), value > 0 {
            alert.setThreshold(UInt64(value * Double(Self.megabyte)))
            return
        }
        let stored = UserDefaults.standard.object(forKey: Self.alertDefaultsKey) as? Int64
        alert.setThreshold(stored.map { UInt64(max(0, $0)) })
    }

    private func applyAlertThreshold(_ bytes: UInt64?, persist: Bool) {
        alert.setThreshold(bytes)
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

    @objc private func selectAlertPreset(_ sender: NSMenuItem) {
        let bytes = (sender.representedObject as? NSNumber)?.uint64Value
        applyAlertThreshold(bytes, persist: bytes != nil)
    }

    @objc private func showCustomAlertThreshold() {
        let dialog = NSAlert()
        dialog.messageText = "自定义流量告警阈值"
        dialog.informativeText = "总流量（上行+下行）达到该值时提醒一次。示例：5 GB、500 MB。"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "5 GB"
        dialog.accessoryView = input
        dialog.addButton(withTitle: "确定")
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
        for item in alertMenu.items where item.action == #selector(selectAlertPreset(_:)) {
            let bytes = (item.representedObject as? NSNumber)?.uint64Value
            item.state = bytes == alert.threshold ? .on : .off
        }
        // 自定义阈值时清除预设勾选
        if let threshold = alert.threshold,
           !alertMenu.items.contains(where: {
               $0.action == #selector(selectAlertPreset(_:)) &&
               ($0.representedObject as? NSNumber)?.uint64Value == threshold
           }) {
            // 保持预设全部不勾选即可，无需额外操作
        }
    }

    /// 每秒检查：越过阈值则触发一次
    private func checkAlert() {
        let totalBytes = monitor.store.wifi.rx + monitor.store.wifi.tx
            + monitor.store.iphone.rx + monitor.store.iphone.tx
        if alert.threshold != nil {
            logger.debug("checkAlert total=\(totalBytes, privacy: .public) threshold=\(self.alert.threshold ?? 0, privacy: .public) fired=\(self.alert.fired, privacy: .public)")
        }
        guard alert.check(totalBytes: totalBytes) else { return }
        fireAlert(usedBytes: totalBytes)
    }

    private func fireAlert(usedBytes: UInt64) {
        let used = ByteFormat.string(usedBytes)
        let limit = ByteFormat.string(alert.threshold ?? 0)
        logger.info("alert fired: used=\(used, privacy: .public) threshold=\(limit, privacy: .public)")
        NSSound(named: "Tink")?.play() // 简单的"滴"一声，无论通知权限如何都会响
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 流量告警"
        content.body = "自开始计时已使用 \(used)，达到设定的 \(limit)。"
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

    @objc private func openHome() {
        homeController.show()
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
        wifiItem.attributedTitle = MenuTextBuilder.interfaceRow(
            name: InterfaceCategory.wifi.displayName,
            rx: store.wifi.rx, tx: store.wifi.tx, rate: monitor.wifiRate)
        iphoneItem.attributedTitle = MenuTextBuilder.interfaceRow(
            name: InterfaceCategory.iphone.displayName,
            rx: store.iphone.rx, tx: store.iphone.tx, rate: monitor.iphoneRate)
        alertItem.attributedTitle = MenuTextBuilder.alertHeader(
            armed: alert.threshold != nil, fired: alert.fired)
    }

    private static func row(_ name: String, rx: UInt64, tx: UInt64, rate: CategoryDelta) -> String {
        "\(name)  ↑\(ByteFormat.string(tx)) ↓\(ByteFormat.string(rx))   \(ByteFormat.rate(rate.rx + rate.tx))"
    }
}
