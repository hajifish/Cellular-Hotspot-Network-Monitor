import Foundation

/// AlertBannerPanel 的等价可测断言。
/// 自测环境裁定（控制者）：裸二进制进程不构造真 NSPanel / 真计时器——
/// 面板真身（真弹真消失、真悬停、真淡出）由打包目检（Task 4）覆盖；
/// 此处测组件与实现共用同一份的纯逻辑：
/// ① bannerFrame 布局纯函数（顶部居中 + 屏幕顶边下方 30pt，避开菜单栏）
/// ② displayDuration 常量
/// ③ 计时器编排指令映射（show 无条件重置旧计时器 / 悬停暂停 / 移出恢复 / 关闭清理）
/// ④ 可见性状态机（show → 可见、dismiss → 隐藏、二次 show 状态完整重置）
@MainActor
enum AlertBannerPanelTests {
    static func all() {
        bannerFrameCentersHorizontallyBelowTopEdge()
        bannerFrameHandlesOffOriginScreen()
        displayDurationIsTenSeconds()
        showAlwaysRestartsCountdown()
        hoverPausesAndResumesCountdown()
        dismissalClearsTimer()
        visibilityResetsFullyOnReshow()
        visibilityFadeOutAndIdempotency()
    }

    // MARK: - ① bannerFrame 纯函数

    static func bannerFrameCentersHorizontallyBelowTopEdge() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 360, height: 76)
        let frame = AlertBannerPanel.bannerFrame(screenFrame: screen, bannerSize: size)
        TestRun.expectEqual(frame.midX, screen.midX, "bannerFrame 水平居中")
        TestRun.expectEqual(frame.maxY, screen.maxY - AlertBannerPanel.topGap,
                            "顶边 = 屏幕顶边 − 30（菜单栏下方不遮挡）")
        TestRun.expectEqual(frame.origin.y, screen.maxY - 30 - 76, "y = screenFrame.maxY − 30 − height")
        TestRun.expectEqual(frame.size, size, "尺寸原样保留")
    }

    static func bannerFrameHandlesOffOriginScreen() {
        // 副屏 / 负坐标系：公式与坐标系原点无关
        let screen = NSRect(x: -1920, y: -400, width: 3840, height: 2160)
        let size = NSSize(width: 480, height: 92)
        let frame = AlertBannerPanel.bannerFrame(screenFrame: screen, bannerSize: size)
        TestRun.expectEqual(frame.midX, screen.midX, "负坐标系屏幕仍水平居中")
        TestRun.expectEqual(frame.origin.y, screen.maxY - 30 - 92, "y 公式在负坐标系下不变")
    }

    // MARK: - ② 常量

    static func displayDurationIsTenSeconds() {
        TestRun.expectEqual(AlertBannerPanel.displayDuration, TimeInterval(10), "10 秒自动淡出")
    }

    // MARK: - ③ 计时器编排指令映射

    static func showAlwaysRestartsCountdown() {
        TestRun.expectEqual(
            AlertBannerPanel.timerDirective(for: .show, hasLiveTimer: false),
            .restart(AlertBannerPanel.displayDuration),
            "首次 show 起倒计时")
        // 关键回归点：连续两次告警不得泄漏 / 双计时——show 无条件重启（restart 语义含先取消旧计时器）
        TestRun.expectEqual(
            AlertBannerPanel.timerDirective(for: .show, hasLiveTimer: true),
            .restart(AlertBannerPanel.displayDuration),
            "二次 show 无条件重置旧计时器")
    }

    static func hoverPausesAndResumesCountdown() {
        TestRun.expectEqual(AlertBannerPanel.timerDirective(for: .hoverStarted, hasLiveTimer: true),
                            .invalidate, "悬停暂停倒计时（取消计时器）")
        TestRun.expectEqual(AlertBannerPanel.timerDirective(for: .hoverStarted, hasLiveTimer: false),
                            .none, "无计时器时悬停不产生指令")
        TestRun.expectEqual(AlertBannerPanel.timerDirective(for: .hoverEnded, hasLiveTimer: true),
                            .restart(AlertBannerPanel.displayDuration), "移出重新调度倒计时")
        // 真实时序：悬停恢复时计时器已被 hoverStarted 暂停取消（hasLiveTimer == false），
        // 故 hoverEnded 无论现状如何都必须 restart（restart 语义含先取消，防御双计时）
        TestRun.expectEqual(AlertBannerPanel.timerDirective(for: .hoverEnded, hasLiveTimer: false),
                            .restart(AlertBannerPanel.displayDuration), "悬停恢复恒为 restart（此时计时器已被暂停取消）")
    }

    static func dismissalClearsTimer() {
        TestRun.expectEqual(AlertBannerPanel.timerDirective(for: .dismissed, hasLiveTimer: true),
                            .invalidate, "关闭清理计时器")
        TestRun.expectEqual(AlertBannerPanel.timerDirective(for: .dismissed, hasLiveTimer: false),
                            .none, "重复关闭不产生指令")
    }

    // MARK: - ④ 可见性状态机（isPanelVisible 语义）

    static func visibilityResetsFullyOnReshow() {
        var state = AlertBannerVisibility()
        TestRun.expect(!state.isPanelVisible, "初始隐藏")
        TestRun.expect(!state.acceptsHoverPause, "隐藏时不接受悬停暂停")

        state.show()
        TestRun.expect(state.isPanelVisible, "show 后可见")
        TestRun.expect(state.acceptsHoverPause, "展示中接受悬停暂停")

        state.finishDismiss()
        TestRun.expect(!state.isPanelVisible, "dismiss 后隐藏")

        // 二次 show：状态完整重置（show → dismiss → show）
        state.show()
        TestRun.expect(state.isPanelVisible, "show → dismiss → show 后仍可见")
        TestRun.expect(state.acceptsHoverPause, "二次 show 恢复悬停暂停资格")
        TestRun.expectEqual(state.phase, .shown, "二次 show 相位回到 shown")
    }

    static func visibilityFadeOutAndIdempotency() {
        var state = AlertBannerVisibility()
        state.finishDismiss() // hidden 上重复 dismiss：幂等
        TestRun.expectEqual(state.phase, .hidden, "hidden 上 dismiss 幂等")

        state.show()
        state.beginFadeOut()
        TestRun.expectEqual(state.phase, .fadingOut, "淡出中相位")
        TestRun.expect(state.isPanelVisible, "淡出中仍算可见（orderOut 未发生）")
        TestRun.expect(!state.acceptsHoverPause, "淡出中不再接受悬停暂停")

        state.beginFadeOut()
        TestRun.expectEqual(state.phase, .fadingOut, "重复 beginFadeOut 不回退相位")

        state.show()
        TestRun.expectEqual(state.phase, .shown, "淡出中重新 show 直接回到 shown（配面板代际守卫）")

        state.beginFadeOut()
        state.finishDismiss()
        TestRun.expectEqual(state.phase, .hidden, "淡出完成收起")
    }
}
