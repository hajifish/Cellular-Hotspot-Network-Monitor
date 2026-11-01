import Foundation

@MainActor
enum UpdateCheckerTests {
    static func all() {
        selectAssetPrefersVersionMatchedZip()
        selectAssetFallsBackAndSkipsDmg()
        fallbackProbeDecision()
        releaseInfoFromRedirectURL()
        errorTextMapping()
        liveGithubLatest() // 实时集成：网络不可用时内部跳过
        liveRedirectProbe() // 实时集成：同上
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

    /// 仅限流类 API 失败（403/429）走网页重定向降级；其余失败如实上报
    static func fallbackProbeDecision() {
        TestRun.expect(GithubReleaseChecker.shouldFallbackToRedirectProbe(UpdateError.apiError(403)),
                       "403 rate limit → fallback")
        TestRun.expect(GithubReleaseChecker.shouldFallbackToRedirectProbe(UpdateError.apiError(429)),
                       "429 rate limit → fallback")
        TestRun.expect(!GithubReleaseChecker.shouldFallbackToRedirectProbe(UpdateError.apiError(500)),
                       "server error → report as-is")
        TestRun.expect(!GithubReleaseChecker.shouldFallbackToRedirectProbe(URLError(.timedOut)),
                       "timeout → report as-is")
    }

    /// 从 releases/latest 重定向落点（…/releases/tag/{tag}）构造最小 ReleaseInfo：
    /// 无发布说明正文，资产按打包工作流的确定性命名构造
    static func releaseInfoFromRedirectURL() {
        let repo = "hajifish/Cellular-Hotspot-Network-Monitor"
        guard let info = GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases/tag/v1.2.3")!,
            repository: repo) else {
            return TestRun.expect(false, "tag page URL → ReleaseInfo")
        }
        TestRun.expectEqual(info.tagName, "v1.2.3", "tag preserved")
        TestRun.expect(info.body == nil, "degraded path has no release notes")
        TestRun.expectEqual(info.assets.count, 1, "single constructed asset")
        TestRun.expectEqual(info.assets.first?.name, "TrafficMonitor-1.2.3.zip", "asset name (v stripped)")
        TestRun.expectEqual(info.assets.first?.browserDownloadUrl,
                           "https://github.com/\(repo)/releases/download/v1.2.3/TrafficMonitor-1.2.3.zip",
                           "download URL deterministic")
        TestRun.expectEqual(info.htmlUrl, "https://github.com/\(repo)/releases/tag/v1.2.3", "htmlUrl = tag page")
        // tag 无 v 前缀：命名同样正确
        guard let plain = GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases/tag/0.9.9")!,
            repository: repo) else {
            return TestRun.expect(false, "plain tag URL → ReleaseInfo")
        }
        TestRun.expectEqual(plain.assets.first?.name, "TrafficMonitor-0.9.9.zip", "plain tag asset name")
        // 非 tag 页落点（404 / releases 列表页）→ nil
        TestRun.expect(GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases")!, repository: repo) == nil,
                       "non-tag URL → nil")
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

    /// 实时集成：网页端点 releases/latest 的重定向可解析出最新 tag（不走 API 配额，
    /// 限流环境仍可用——正是降级通道存在的意义）
    static func liveRedirectProbe() {
        let sema = DispatchSemaphore(value: 0)
        var probed: String?
        GithubReleaseChecker.redirectProbe(repository: "hajifish/Cellular-Hotspot-Network-Monitor") { result in
            if case .success(let release) = result { probed = release.tagName }
            sema.signal()
        }
        sema.wait()
        guard let probed else { return } // 无网环境跳过
        TestRun.expect(!probed.isEmpty, "redirect probe resolves tag: \(probed)")
    }
}
