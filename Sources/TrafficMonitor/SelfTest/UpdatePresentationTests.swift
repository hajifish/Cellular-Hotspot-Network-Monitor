import Foundation

@MainActor
enum UpdatePresentationTests {
    static func all() {
        menuContentPerState()
        cardContentPerState()
    }

    static func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlUrl: "https://example.com/r/\(tag)",
                    body: "修复若干问题", assets: [])
    }

    static func menuContentPerState() {
        let idle = UpdatePresentation.menuContent(for: .idle, currentVersion: "0.2.0")
        TestRun.expectEqual(idle.info, "版本 0.2.0", "idle info")
        TestRun.expectEqual(idle.primary, "检查更新…", "idle primary")

        let available = UpdatePresentation.menuContent(for: .available(release("v0.3.0")), currentVersion: "0.2.0")
        TestRun.expect(available.infoBold, "available info bold")
        TestRun.expect(available.info.contains("0.3.0"), "info carries tag")
        TestRun.expectEqual(available.primary, "下载并更新", "available primary")
        TestRun.expectEqual(available.secondary, "查看更新内容", "available secondary")

        let downloading = UpdatePresentation.menuContent(for: .downloading(0.45), currentVersion: "0.2.0")
        TestRun.expect(downloading.info.contains("45%"), "progress percent shown")
        TestRun.expectEqual(downloading.secondary, "取消下载", "cancel offered")

        let downloaded = UpdatePresentation.menuContent(for: .downloaded(release("v0.3.0")), currentVersion: "0.2.0")
        TestRun.expectEqual(downloaded.primary, "重启以完成更新", "restart action")

        let checking = UpdatePresentation.menuContent(for: .checking, currentVersion: "0.2.0")
        TestRun.expectEqual(checking.primary, nil, "no action while busy")

        let failed = UpdatePresentation.menuContent(for: .failed("网络不可用"), currentVersion: "0.2.0")
        TestRun.expectEqual(failed.primary, "重试检查", "retry offered")
    }

    static func cardContentPerState() {
        let upToDate = UpdatePresentation.cardContent(for: .upToDate, currentVersion: "0.2.0",
                                                      lastCheck: nil, errorText: nil)
        TestRun.expect(upToDate.status.contains("已是最新"), "upToDate status")
        TestRun.expect(upToDate.kind == .ok, "ok kind")

        let available = UpdatePresentation.cardContent(for: .available(release("v0.3.0")), currentVersion: "0.2.0",
                                                       lastCheck: nil, errorText: nil)
        TestRun.expect(available.notes.contains("修复若干问题"), "release notes excerpted")
        TestRun.expect(available.kind == .attention, "attention kind")
        TestRun.expectEqual(available.primary, "下载并更新", "primary action")
        TestRun.expectEqual(available.secondary, "打开发布页", "secondary action")

        let failed = UpdatePresentation.cardContent(for: .failed("x"), currentVersion: "0.2.0",
                                                    lastCheck: nil, errorText: "网络不可用或连接超时")
        TestRun.expectEqual(failed.notes, "网络不可用或连接超时", "error detail in notes")
        TestRun.expect(failed.kind == .error, "error kind")

        let downloading = UpdatePresentation.cardContent(for: .downloading(0.3), currentVersion: "0.2.0",
                                                         lastCheck: nil, errorText: nil)
        TestRun.expect(downloading.status.contains("30%"), "percent in status")
        TestRun.expectEqual(downloading.secondary, "取消下载", "cancel offered")
    }
}
