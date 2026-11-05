import Foundation
import os
import TMNotify

/// 系统通知统一出口：经 TMNotify 桥走 NSUserNotification 老接口。
/// 老接口通知按应用 bundle 归属、横幅自带应用图标（无证书要求；UNUserNotificationCenter
/// 对 ad-hoc 签名应用只给占位图标）。机制与 mac-notification-sys（Token Usage 同链路）
/// 一致，2026-11-05 探针实验目检证实。取舍：deliverNotification 无失败回调，投递失败
/// 不可检测（告警的 NSSound "Tink" 与菜单栏状态是必达兜底）。
enum SystemNotifier {
    private static let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "notify")

    /// 测试注入点：默认实现经桥投递（自测注入 no-op，避免测试二进制弹真通知）
    static var deliver: (String, String, String, Bool) -> Void = { title, body, identifier, sound in
        tm_post_notification(title, body, identifier, sound)
    }

    /// 投递系统通知；老接口运行时缺失（Apple 未来移除）时记日志后静默丢弃
    static func post(title: String, body: String, identifier: String, sound: Bool = true) {
        guard tm_notification_available() else {
            logger.error("legacy notification API unavailable, dropped: \(title, privacy: .public)")
            return
        }
        deliver(title, body, identifier, sound)
    }

    /// 点击路由表（C 回调无法捕获上下文，经静态表转发）
    private static var activationRouter: ((String) -> Void)?

    /// 注册点击路由并挂接桥回调。AppKit 保证回调在主线程；防御性再兜一次主队列。
    static func configureActivation(router: @escaping (String) -> Void) {
        activationRouter = router
        tm_set_activation_handler { identifier, _ in
            let id = identifier.map { String(cString: $0) } ?? ""
            if Thread.isMainThread {
                SystemNotifier.handleActivation(identifier: id)
            } else {
                DispatchQueue.main.async {
                    SystemNotifier.handleActivation(identifier: id)
                }
            }
        }
    }

    /// 桥回调落点（internal 供自测直接驱动）
    static func handleActivation(identifier: String) {
        activationRouter?(identifier)
    }
}
