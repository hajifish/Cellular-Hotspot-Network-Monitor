import Foundation

@MainActor
enum UpdateInstallerTests {
    static func all() {
        scriptQuotesAllOperands()
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
