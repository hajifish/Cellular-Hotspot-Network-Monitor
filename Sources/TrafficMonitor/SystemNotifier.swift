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
    static var deliver: (String, String, String, Bool, ((Error) -> Void)?) -> Void = {
        title, body, identifier, sound, onFailure in
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            logger.error("notification delivery failed (\(identifier, privacy: .public)): \(String(describing: error), privacy: .public)")
            guard let onFailure else { return }
            DispatchQueue.main.async { onFailure(error) }
        }
    }

    /// 投递系统通知；投递失败（UN add 回调 error）在记日志后回调 onFailure
    /// （主线程派发），供调用方做应用内兜底
    static func post(title: String, body: String, identifier: String, sound: Bool = true,
                     onFailure: ((Error) -> Void)? = nil) {
        deliver(title, body, identifier, sound, onFailure)
    }

    /// 点击路由表
    private static var activationRouter: ((String) -> Void)?

    /// UN center.delegate 是弱引用，delegate 对象须自行强持有
    private static let centerDelegate = CenterDelegate()

    /// 注册点击路由并挂 UN delegate；同时请求通知授权（fire-and-forget，已授权则
    /// 静默返回——0.9.x 授权语义，勿在别处重复请求）。
    /// 裸二进制（自测）无 bundle，访问 UN center 即抛异常——只注册路由，跳过接线。
    static func configureActivation(router: @escaping (String) -> Void) {
        activationRouter = router
        guard AppVersion.isBundledApp else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = centerDelegate
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
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
