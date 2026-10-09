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
    }

    private func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        startTimeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        wifiItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        iphoneItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        let reset = NSMenuItem(title: "重置计数", action: #selector(resetCounters), keyEquivalent: "r")
        reset.target = self
        let openHome = NSMenuItem(title: "打开主页", action: #selector(openHome), keyEquivalent: "0")
        openHome.target = self
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let alertItem = NSMenuItem(title: "流量告警", action: nil, keyEquivalent: "")
        alertMenu = buildAlertMenu()
        alertItem.submenu = alertMenu

        menu.addItem(startTimeItem)
        menu.addItem(.separator())
        menu.addItem(wifiItem)
        menu.addItem(iphoneItem)
        menu.addItem(.separator())
        menu.addItem(openHome)
        menu.addItem(alertItem)
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(quit)

        statusItem.menu = menu
        changeObserverID = monitor.addObserver { [weak self] in
            self?.refresh()
            self?.checkAlert()
        }
        monitor.start()
        refresh()
        // 诊断/验证用：启动即打开主页
        if ProcessInfo.processInfo.environment["TRAFFICMONITOR_SHOWHOME"] == "1" {
            homeController.show()
        }
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
        let totalBytes = monitor.store.wifiRX + monitor.store.wifiTX
            + monitor.store.iphoneRX + monitor.store.iphoneTX
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
        NSSound(named: "Glass")?.play() // 柔和钟声，无论通知权限如何都会响
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 流量告警"
        content.body = "自开始计时已使用 \(used)，达到设定的 \(limit)。"
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

    @objc private func resetCounters() {
        monitor.reset()
        alert.reset()
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        refreshAlertMenuStates()
    }

    private func refresh() {
        statusItem.button?.title = monitor.menuBarTitle
        startTimeItem.title = "开始于 \(monitor.store.startTime.formatted(date: .omitted, time: .shortened))"
        startTimeItem.isEnabled = false
        wifiItem.title = Self.row(InterfaceCategory.wifi.displayName,
                                  rx: monitor.store.wifiRX, tx: monitor.store.wifiTX,
                                  rate: monitor.wifiRate)
        wifiItem.isEnabled = false
        iphoneItem.title = Self.row(InterfaceCategory.iphone.displayName,
                                    rx: monitor.store.iphoneRX, tx: monitor.store.iphoneTX,
                                    rate: monitor.iphoneRate)
        iphoneItem.isEnabled = false
    }

    private static func row(_ name: String, rx: UInt64, tx: UInt64, rate: CategoryDelta) -> String {
        "\(name)  ↑\(ByteFormat.string(tx)) ↓\(ByteFormat.string(rx))   \(ByteFormat.rate(rate.rx + rate.tx))"
    }
}
