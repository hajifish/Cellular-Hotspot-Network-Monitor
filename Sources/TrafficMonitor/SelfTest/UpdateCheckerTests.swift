import Foundation

@MainActor
enum UpdateCheckerTests {
    static func all() {
        selectAssetPrefersVersionMatchedZip()
        selectAssetFallsBackAndSkipsDmg()
        errorTextMapping()
        liveGithubLatest() // 实时集成：网络不可用时内部跳过
    }

    static func releaseWith(assets: [ReleaseAsset]) -> ReleaseInfo {
        ReleaseInfo(tagName: "v0.3.0", htmlUrl: "https://example.com/r", body: nil, assets: assets)
    }

    static func selectAssetPrefersVersionMatchedZip() {
        let release = releaseWith(assets: [
            ReleaseAsset(name: "TrafficMonitor-0.2.0.zip", size: 1, browserDownloadUrl: "https://example.com/old.zip"),
            ReleaseAsset(name: "TrafficMonitor-0.3.0.zip", size: 2, browserDownloadUrl: "https://example.com/new.zip"),
            ReleaseAsset(name: "TrafficMonitor-0.3.0.dmg", size: 3, browserDownloadUrl: "https://example.com/new.dmg"),
        ])
        let asset = GithubReleaseChecker.selectAsset(from: release)
        TestRun.expectEqual(asset?.name, "TrafficMonitor-0.3.0.zip", "version-matched zip wins over dmg/other zip")
    }

    static func selectAssetFallsBackAndSkipsDmg() {
        TestRun.expectEqual(GithubReleaseChecker.selectAsset(from: releaseWith(assets: [])), nil, "no assets → nil")
        let dmgOnly = releaseWith(assets: [
            ReleaseAsset(name: "TrafficMonitor-0.3.0.dmg", size: 1, browserDownloadUrl: "https://example.com/x.dmg"),
        ])
        TestRun.expectEqual(GithubReleaseChecker.selectAsset(from: dmgOnly), nil, "dmg only → nil")
        let anyZip = releaseWith(assets: [
            ReleaseAsset(name: "TrafficMonitor-arm64.zip", size: 1, browserDownloadUrl: "https://example.com/a.zip"),
        ])
        TestRun.expectEqual(GithubReleaseChecker.selectAsset(from: anyZip)?.name, "TrafficMonitor-arm64.zip", "any zip fallback")
    }

    static func errorTextMapping() {
        TestRun.expectEqual(GithubReleaseChecker.errorText(URLError(.timedOut)), "网络不可用或连接超时", "timeout")
        TestRun.expectEqual(GithubReleaseChecker.errorText(UpdateError.apiError(403)), "GitHub 接口限流，请稍后再试", "rate limit")
        TestRun.expectEqual(GithubReleaseChecker.errorText(UpdateError.versionMismatch), "下载内容校验不符，已放弃安装", "mismatch")
        TestRun.expectEqual(GithubReleaseChecker.errorText(UpdateError.devBuild), "开发构建不支持应用内更新，请前往发布页下载", "dev build")
    }

    /// 实时集成：真实请求仓库 latest 并解码（与 ping 网关测试同风格，失败环境跳过）
    static func liveGithubLatest() {
        let sema = DispatchSemaphore(value: 0)
        var decoded: ReleaseInfo?
        GithubReleaseChecker.fetchLatestRaw(repository: "hajifish/Cellular-Hotspot-Network-Monitor") { result in
            if case .success(let release) = result { decoded = release }
            sema.signal()
        }
        sema.wait()
        guard let release = decoded else { return } // 无网 / 限流环境跳过
        TestRun.expect(!release.tagName.isEmpty, "latest tag non-empty")
        TestRun.expect(AppVersion.numericComponents(release.tagName).count >= 2, "tag version-like: \(release.tagName)")
    }
}
