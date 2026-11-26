import Foundation
import os
import UserNotifications

/// 系统通知统一出口：UNUserNotificationCenter。
/// 必须走 UN、不能回老接口（NSUserNotification）：usernoted 按 bundle id 永久标记
/// 客户端类型，用过 UN 的 bundle 走老接口投递一律被拒（"You can't mix modern clients
/// with legacy clients"），标记存于受保护数据库、清 LS 注册与重启 usernoted 均无效；
/// 0.10.0 切老接口导致 0.9.x 升级用户通知全灭，0.10.1 回退（详见 CHANGELOG）。
enum SystemNotifier {
    private static let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "notify")

    /// 测试注入点：默认实现走 UN center（自测裸二进制无 bundle，UN center 访问即抛
    /// 异常——注入 no-op 既防真通知也防异常）
    static var deliver: (String, String, String, Bool, Bool, ((Error) -> Void)?) -> Void = {
        title, body, identifier, sound, timeSensitive, onFailure in
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        // 仅告警显式时间敏感级；false 时不设置该属性，维持系统默认 active、payload 最小。
        // 降级现状（2026-11-26 终审实测）：ad-hoc 签名缺少受限 entitlement
        // com.apple.developer.usernotifications.time-sensitive（挂上即被 AMFI 拒启，
        // ad-hoc 无法携带），usernoted 报 "Reducing interruption level ... missing
        // authorization" 后系统把时间敏感降为普通级投递；本请求保留——未来换
        // Developer ID + provisioning 签名后自动生效。全屏兜底由应用内浮窗
        // （AlertBannerPanel）承担，不受此降级影响
        if timeSensitive { content.interruptionLevel = .timeSensitive }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            logger.error("notification delivery failed (\(identifier, privacy: .public)): \(String(describing: error), privacy: .public)")
            guard let onFailure else { return }
            DispatchQueue.main.async { onFailure(error) }
        }
    }

    /// 投递系统通知；投递失败（UN add 回调 error）在记日志后回调 onFailure
    /// （主线程派发），供调用方做应用内兜底。
    /// timeSensitive 仅流量告警使用（时间敏感级在专注模式/通知摘要下仍可触达；
    /// 当前 ad-hoc 签名缺受限 entitlement，系统实际降为普通级投递——请求保留，
    /// Developer ID + provisioning 签名下自动生效）；
    /// 其余通知一律缺省 false，维持普通级
    static func post(title: String, body: String, identifier: String, sound: Bool = true,
                     timeSensitive: Bool = false, onFailure: ((Error) -> Void)? = nil) {
        deliver(title, body, identifier, sound, timeSensitive, onFailure)
    }

    /// 点击通知是否打开主页（纯函数，可测）。默认所有应用通知点击都聚焦应用窗口：
    /// LSUIElement 应用被系统激活却无窗口可显示，用户会被晾在一个「空白的地方」
    /// （2026-11-13 修复：流量告警/预告的通知此前完全没有路由）。唯一例外
    /// "uptodate-check"——「已是最新」无详情可看，点击不弹窗（2026-11-01 决策）
    static func activationOpensHome(identifier: String) -> Bool {
        identifier != "uptodate-check"
    }

    /// 点击路由表
    private static var activationRouter: ((String) -> Void)?

    /// UN center.delegate 是弱引用，delegate 对象须自行强持有
    private static let centerDelegate = CenterDelegate()

    /// 注册点击路由并挂 UN delegate；同时请求通知授权（fire-and-forget，已授权则
    /// 静默返回——0.9.x 授权语义，勿在别处重复请求）。
    /// `.timeSensitive` 授权选项保留（实测 ad-hoc 签名下 usernoted 不认——级仍降为
    /// 普通；换 Developer ID + provisioning 签名后自动生效）。
    /// 裸二进制（自测）无 bundle，访问 UN center 即抛异常——只注册路由，跳过接线。
    static func configureActivation(router: @escaping (String) -> Void) {
        activationRouter = router
        guard AppVersion.isBundledApp else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = centerDelegate
        // .timeSensitive 保留在授权请求里（ad-hoc 下系统不认、Developer ID 签名后生效）
        center.requestAuthorization(options: [.alert, .sound, .timeSensitive]) { _, error in
            if let error {
                logger.error("notification auth error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// UN 点击回调落点（internal 供自测直接驱动）。delegate 回调线程无主线程保证，
    /// 防御性兜主队列（路由闭包是 MainActor 侧注册的）
    static func handleActivation(identifier: String) {
        if Thread.isMainThread {
            activationRouter?(identifier)
            return
        }
        DispatchQueue.main.async {
            SystemNotifier.handleActivation(identifier: identifier)
        }
    }
}

private final class CenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// 点击按 identifier 转发路由（"update-" 前缀 → 主页，语义在调用点）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        SystemNotifier.handleActivation(identifier: response.notification.request.identifier)
        completionHandler()
    }

    /// 应用前台时横幅照常显示并出声（0.9.x 语义）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
