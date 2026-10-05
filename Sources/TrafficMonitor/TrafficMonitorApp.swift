import AppKit
import Foundation

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
    static private(set) var shared: MenuBarController!

    private let monitor = TrafficMonitor()
    private let homeController: HomePageController
    private var statusItem: NSStatusItem!
    private var startTimeItem: NSMenuItem!
    private var wifiItem: NSMenuItem!
    private var iphoneItem: NSMenuItem!
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

        menu.addItem(startTimeItem)
        menu.addItem(.separator())
        menu.addItem(wifiItem)
        menu.addItem(iphoneItem)
        menu.addItem(.separator())
        menu.addItem(openHome)
        menu.addItem(reset)
        menu.addItem(.separator())
        menu.addItem(quit)

        statusItem.menu = menu
        changeObserverID = monitor.addObserver { [weak self] in self?.refresh() }
        monitor.start()
        refresh()
        // 诊断/验证用：启动即打开主页
        if ProcessInfo.processInfo.environment["TRAFFICMONITOR_SHOWHOME"] == "1" {
            homeController.show()
        }
    }

    @objc private func openHome() {
        homeController.show()
    }

    @objc private func resetCounters() {
        monitor.reset()
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        statusItem.button?.title = monitor.menuBarTitle
        startTimeItem.title = "开始于 \(monitor.store.startTime.formatted(date: .omitted, time: .shortened))"
        startTimeItem.isEnabled = false
        wifiItem.title = Self.row("Wi-Fi",
                                  rx: monitor.store.wifiRX, tx: monitor.store.wifiTX,
                                  rate: monitor.wifiRate)
        wifiItem.isEnabled = false
        iphoneItem.title = Self.row("iPhone",
                                    rx: monitor.store.iphoneRX, tx: monitor.store.iphoneTX,
                                    rate: monitor.iphoneRate)
        iphoneItem.isEnabled = false
    }

    private static func row(_ name: String, rx: UInt64, tx: UInt64, rate: CategoryDelta) -> String {
        "\(name)  ↑\(ByteFormat.string(tx)) ↓\(ByteFormat.string(rx))   \(ByteFormat.rate(rate.rx + rate.tx))"
    }
}
