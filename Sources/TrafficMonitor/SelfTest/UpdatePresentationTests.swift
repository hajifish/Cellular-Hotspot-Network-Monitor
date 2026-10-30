import Foundation

@MainActor
enum UpdatePresentationTests {
    static func all() {
        wantsCardOnlyForActiveStates()
        cardAvailableShowsUpdateActions()
        cardProgressAndRestartStates()
        menuCheckTitleReflectsState()
    }

    static func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlUrl: "https://example.com/r/\(tag)",
                    body: "修复若干问题", assets: [])
    }

    /// 只有真正有更新进行时才出现卡片框架；无更新（含检查失败）一律收起
    static func wantsCardOnlyForActiveStates() {
        TestRun.expect(UpdatePresentation.wantsCard(for: .available(release("v0.3.0"))), "available → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .downloading(0.5)), "downloading → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .downloaded(release("v0.3.0"))), "downloaded → card")
        TestRun.expect(UpdatePresentation.wantsCard(for: .installing), "installing → card")
        for state in [UpdateState.idle, .checking, .upToDate, .failed("x")] {
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

    /// 菜单「检查更新」条目文字：检测到新版本（手动或自动）追加「有新版本」
    static func menuCheckTitleReflectsState() {
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .idle), "检查更新", "idle plain")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .upToDate), "检查更新", "upToDate plain")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .failed("x")), "检查更新", "failed plain")
        TestRun.expectEqual(UpdatePresentation.menuCheckTitle(for: .checking), "正在检查更新…", "checking feedback")
        TestRun.expect(UpdatePresentation.menuCheckTitle(for: .available(release("v0.3.0"))).hasSuffix("有新版本"),
                       "available badge")
        TestRun.expect(UpdatePresentation.menuCheckTitle(for: .downloading(0.5)).hasSuffix("有新版本"),
                       "downloading badge")
        TestRun.expect(UpdatePresentation.menuCheckTitle(for: .downloaded(release("v0.3.0"))).hasSuffix("有新版本"),
                       "downloaded badge")
    }
}
