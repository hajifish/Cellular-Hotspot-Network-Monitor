import Foundation

@MainActor
enum UpdatePresentationTests {
    static func all() {
        wantsCardOnlyForActiveStates()
        cardAvailableShowsUpdateActions()
        cardAvailableDegradedFallsBackToLastCheck()
        cardProgressAndRestartStates()
        cardFailedOffersRetry()
        menuCheckTitleReflectsState()
    }

    static func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlUrl: "https://example.com/r/\(tag)",
                    body: "修复若干问题", assets: [])
    }

    /// 只有真正有更新进行时才出现卡片框架；无更新时收起；
    /// 检查失败例外——展开显示原因与重试（2026-11-01 静默失败修复）
    static func wantsCardOnlyForActiveStates() {
        TestRun.expect(UpdatePresentation.wantsCard(for: .available(release("v0.3.0"))), "available → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .downloading(0.5)), "downloading → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .downloaded(release("v0.3.0"))), "downloaded → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .installing), "installing → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .failed("x")), "failed → card (reason visible)")
        for state in [UpdateState.idle, .checking, .upToDate] {
            TestRun.expect(!UpdatePresentation.wantsCard(for: state), "\(state) → no card")
        }
    }

    static func cardAvailableShowsUpdateActions() {
        let available = UpdatePresentation.cardContent(for: .available(release("v0.3.0")), currentVersion: "0.2.0",
                                                       lastCheck: nil, errorText: nil)
        TestRun.expect(available.status.contains("发现新版本"), "available status")
        TestRun.expect(available.notes.contains("修复若干问题"), "release notes excerpted")
        TestRun.expect(available.kind == .attention, "attention kind")
        TestRun.expectEqual(available.primary, "下载并更新", "primary action")
        TestRun.expectEqual(available.secondary, "打开发布页", "secondary action")
    }

    /// 降级通道构造的 ReleaseInfo（body = nil，发布说明不可得）：
    /// 卡片备注回退为「上次检查」时间，下载/发布页操作不受影响
    static func cardAvailableDegradedFallsBackToLastCheck() {
        let degraded = ReleaseInfo(tagName: "v0.6.0", htmlUrl: "https://example.com/r/v0.6.0",
                                   body: nil, assets: [])
        let available = UpdatePresentation.cardContent(for: .available(degraded), currentVersion: "0.5.0",
                                                       lastCheck: Date(timeIntervalSince1970: 1_767_225_600),
                                                       errorText: nil)
        TestRun.expect(available.notes.contains("上次检查"), "degraded release falls back to last-check note")
        TestRun.expectEqual(available.primary, "下载并更新", "degraded release keeps download action")
    }

    static func cardProgressAndRestartStates() {
        let downloading = UpdatePresentation.cardContent(for: .downloading(0.3), currentVersion: "0.2.0",
                                                         lastCheck: nil, errorText: nil)
        TestRun.expect(downloading.status.contains("30%"), "percent in status")
        TestRun.expectEqual(downloading.secondary, "取消下载", "cancel offered")

        let downloaded = UpdatePresentation.cardContent(for: .downloaded(release("v0.3.0")), currentVersion: "0.2.0",
                                                        lastCheck: nil, errorText: nil)
        TestRun.expectEqual(downloaded.primary, "重启以完成更新", "restart action")
        TestRun.expectEqual(downloaded.secondary, "取消更新", "cancel offered")
    }

    /// 失败卡片：展开显示原因 + 「重试」（主按钮 default 分支即 checkNow，零接线）
    static func cardFailedOffersRetry() {
        let failed = UpdatePresentation.cardContent(for: .failed("x"), currentVersion: "0.2.0",
                                                    lastCheck: nil, errorText: "GitHub 接口限流，请稍后再试")
        TestRun.expectEqual(failed.primary, "重试", "failed → retry action")
        TestRun.expect(failed.notes.contains("限流"), "failure reason visible")
        TestRun.expect(failed.kind == .error, "error kind")
    }

    /// 菜单「检查更新」条目文字：有新版本/失败/已是最新分别追加后缀（仅下拉时可见）
    static func menuCheckTitleReflectsState() {
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .idle), "检查更新", "idle plain")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .upToDate), "检查更新 · 已是最新", "upToDate badge")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .failed("x")), "检查更新 · 失败", "failed badge")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .checking), "正在检查更新…", "checking feedback")
        TestRun.expect(UpdatePresentation.menuCheckTitle(for: .available(release("v0.3.0"))).hasSuffix("有新版本"),
                       "available badge")
        TestRun.expect(UpdatePresentation.menuCheckTitle(for: .downloading(0.5)).hasSuffix("有新版本"),
                       "downloading badge")
        TestRun.expect(UpdatePresentation.menuCheckTitle(for: .downloaded(release("v0.3.0"))).hasSuffix("有新版本"),
                       "downloaded badge")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .installing), "检查更新 · 有新版本",
                            "installing badge")
    }
}
