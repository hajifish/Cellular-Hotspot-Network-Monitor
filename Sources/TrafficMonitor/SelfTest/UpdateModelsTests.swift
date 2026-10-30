import Foundation

@MainActor
enum UpdateModelsTests {
    static func all() {
        decodesGitHubLatestPayload()
        versionComparison()
        notesExcerptTruncation()
    }

    /// 与 GitHub /releases/latest 实际返回结构一致（节选字段）
    static let fixtureJSON = """
    {
      "tag_name": "v0.3.0",
      "name": "0.3.0",
      "body": "### 修复\\n- 修复 en7 计数回绕\\n- 新增自动更新",
      "html_url": "https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/releases/tag/v0.3.0",
      "assets": [
        {"name": "TrafficMonitor-0.3.0.zip", "size": 2048000,
         "browser_download_url": "https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/releases/download/v0.3.0/TrafficMonitor-0.3.0.zip"},
        {"name": "TrafficMonitor-0.3.0.dmg", "size": 4096000,
         "browser_download_url": "https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/releases/download/v0.3.0/TrafficMonitor-0.3.0.dmg"}
      ]
    }
    """

    static func decodesGitHubLatestPayload() {
        let release = try! JSONDecoder().decode(ReleaseInfo.self, from: Data(fixtureJSON.utf8))
        TestRun.expectEqual(release.tagName, "v0.3.0", "tag_name")
        TestRun.expectEqual(release.assets.count, 2, "assets count")
        TestRun.expectEqual(release.assets[0].browserDownloadUrl,
                            "https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/releases/download/v0.3.0/TrafficMonitor-0.3.0.zip",
                            "asset download url")
    }

    static func versionComparison() {
        TestRun.expect(AppVersion.isNewer("0.3.0", than: "0.2.9"), "patch bump")
        TestRun.expect(AppVersion.isNewer("0.10.0", than: "0.9.0"), "numeric not lexicographic")
        TestRun.expect(AppVersion.isNewer("v0.3.0", than: "0.2.0"), "v prefix tolerated")
        TestRun.expect(!AppVersion.isNewer("0.2", than: "0.2.0"), "zero padding equal")
        TestRun.expect(!AppVersion.isNewer("0.2.0", than: "0.2.0"), "equal not newer")
        TestRun.expect(AppVersion.isNewer("1.0.0-beta", than: "0.9.9"), "prerelease suffix truncated")
    }

    static func notesExcerptTruncation() {
        TestRun.expectEqual(AppVersion.notesExcerpt(nil), "", "nil body")
        let long = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let excerpt = AppVersion.notesExcerpt(long)
        TestRun.expect(excerpt.split(separator: "\n").count == 8, "line cap 8")
        let clipped = AppVersion.notesExcerpt(String(repeating: "x", count: 400))
        TestRun.expectEqual(clipped.count, 301, "char cap 300 + ellipsis")
    }
}
