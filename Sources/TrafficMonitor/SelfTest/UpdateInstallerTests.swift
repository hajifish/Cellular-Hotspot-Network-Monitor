import Foundation

@MainActor
enum UpdateInstallerTests {
    static func all() {
        scriptQuotesAllOperands()
        downloadStatusRejectsErrorPages()
        findVerifiedAppAcceptsMatchingVersion()
        findVerifiedAppRejectsMismatch()
        findVerifiedAppRejectsMissingApp()
    }

    /// 临时目录里造一个最小 .app（仅 Contents/Info.plist），返回 .app URL
    @discardableResult
    static func makeFixtureApp(version: String, in parent: URL,
                               name: String = "Traffic Monitor.app") throws -> URL {
        let contents = parent.appendingPathComponent(name).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
        </dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        return parent.appendingPathComponent(name)
    }

    static func scriptQuotesAllOperands() {
        let script = UpdateInstaller.scriptContents()
        TestRun.expect(script.hasPrefix("#!/bin/sh"), "shebang")
        TestRun.expect(script.contains(#"mv "$OLD_APP" "$OLD_APP.old-$STAMP""#), "backup rename quoted")
        TestRun.expect(script.contains(#"if mv "$NEW_APP" "$OLD_APP"; then"#), "swap-in quoted")
        TestRun.expect(script.contains(#"mv "$OLD_APP.old-$STAMP" "$OLD_APP""#), "rollback uses exact stamp (glob 会把多个备份 mv 进目录)")
        TestRun.expect(script.contains(#"open "$OLD_APP""#), "relaunch quoted")
        TestRun.expect(script.contains(#"kill -0 "$WAIT_PID""#), "waits for old process exit")
    }

    /// 下载完成回调不校验 HTTP 状态时，404 错误页会被当 zip 存盘（2026-11-12 实测：
    /// 空资产 release 的下载 URL 404，update.zip 内容为 "Not Found"）。状态判定是纯函数：
    /// 2xx 放行；404 = 安装包未就绪；其余非 2xx = 接口错误；非 HTTP 响应 = badResponse
    static func downloadStatusRejectsErrorPages() {
        func http(_ code: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com/x.zip")!, statusCode: code,
                            httpVersion: nil, headerFields: nil)!
        }
        TestRun.expect(UpdateInstaller.downloadStatusError(http(200)) == nil, "2xx accepted")
        TestRun.expect(UpdateInstaller.downloadStatusError(http(206)) == nil, "partial content accepted")
        TestRun.expectEqual(UpdateInstaller.downloadStatusError(http(404)) as? UpdateError,
                            .assetMissing, "404 = package not there")
        TestRun.expectEqual(UpdateInstaller.downloadStatusError(http(503)) as? UpdateError,
                            .apiError(503), "other non-2xx = api error")
        TestRun.expectEqual(UpdateInstaller.downloadStatusError(nil) as? UpdateError,
                            .badResponse, "non-HTTP response refused")
    }

    static func findVerifiedAppAcceptsMatchingVersion() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("umt-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try makeFixtureApp(version: "0.3.0", in: dir)
            let app = try UpdateInstaller.findVerifiedApp(in: dir, expectedVersion: "v0.3.0")
            TestRun.expectEqual(app.lastPathComponent, "Traffic Monitor.app", "located app")
        } catch {
            TestRun.expect(false, "unexpected error: \(error)")
        }
    }

    static func findVerifiedAppRejectsMismatch() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("umt-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try? makeFixtureApp(version: "0.2.9", in: dir)
        TestRun.expectError(try UpdateInstaller.findVerifiedApp(in: dir, expectedVersion: "v0.3.0"),
                            equals: UpdateError.versionMismatch, "version mismatch refused")
    }

    static func findVerifiedAppRejectsMissingApp() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("umt-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        TestRun.expectError(try UpdateInstaller.findVerifiedApp(in: dir, expectedVersion: "v0.3.0"),
                            equals: UpdateError.assetMissing, "no .app in directory")
    }
}
