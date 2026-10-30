import Foundation

@MainActor
enum UpdatePresentationTests {
    static func all() {
        cardIdleAndUpToDateShowVersionOnly()
        cardAvailableShowsUpdateActions()
        cardTransientsAndFailure()
    }

    static func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlUrl: "https://example.com/r/\(tag)",
                    body: "修复若干问题", assets: [])
    }

    /// 无新版本（idle/upToDate）：只展示当前版本号，无任何操作按钮
    static func cardIdleAndUpToDateShowVersionOnly() {
        for state in [UpdateState.idle, .upToDate] {
            let content = UpdatePresentation.cardContent(for: state, currentVersion: "0.2.0",
                                                         lastCheck: nil, errorText: nil)
            TestRun.expectEqual(content.status, "当前版本 0.2.0", "\(state) shows version only")
            TestRun.expectEqual(content.notes, "", "\(state) no notes")
            TestRun.expectEqual(content.primary, nil, "\(state) no action")
            TestRun.expect(content.kind == .neutral, "\(state) neutral kind")
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

        let downloaded = UpdatePresentation.cardContent(for: .downloaded(release("v0.3.0")), currentVersion: "0.2.0",
                                                        lastCheck: nil, errorText: nil)
        TestRun.expectEqual(downloaded.primary, "重启以完成更新", "restart action")
        TestRun.expectEqual(downloaded.secondary, "取消更新", "cancel offered")
    }

    static func cardTransientsAndFailure() {
        let failed = UpdatePresentation.cardContent(for: .failed("x"), currentVersion: "0.2.0",
                                                    lastCheck: nil, errorText: "网络不可用或连接超时")
        TestRun.expectEqual(failed.status, "当前版本 0.2.0", "failed keeps version status")
        TestRun.expectEqual(failed.notes, "网络不可用或连接超时", "error detail in notes")
        TestRun.expect(failed.kind == .error, "error kind")
        TestRun.expectEqual(failed.primary, nil, "no retry button in menu-free UI")

        let downloading = UpdatePresentation.cardContent(for: .downloading(0.3), currentVersion: "0.2.0",
                                                         lastCheck: nil, errorText: nil)
        TestRun.expect(downloading.status.contains("30%"), "percent in status")
        TestRun.expectEqual(downloading.secondary, "取消下载", "cancel offered")
    }
}
