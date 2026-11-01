import Foundation

@MainActor
enum UpdateCheckerTests {
    static func all() {
        selectAssetPrefersVersionMatchedZip()
        selectAssetFallsBackAndSkipsDmg()
        fallbackProbeDecision()
        releaseInfoFromRedirectURL()
        degradedReleaseSurvivesAssetSelection()
        handleProbeResponseMapsOutcome()
        routeFallsBackToProbeOnRateLimit()
        routeReportsServerErrorsAsIs()
        routePropagatesProbeFailureVerbatim()
        simulatesTimeoutOffByDefault()
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
        // tag 可含斜杠：取 "tag/" 之后整段
        TestRun.expectEqual(GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases/tag/rel/1.2.3")!,
            repository: repo)?.tagName, "rel/1.2.3", "slash-containing tag preserved")
        // 大写 V 前缀同样剥除
        TestRun.expectEqual(GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases/tag/V1.2.3")!,
            repository: repo)?.assets.first?.name, "TrafficMonitor-1.2.3.zip", "uppercase V prefix stripped")
        // 非 tag 页落点（404 / releases 列表页）→ nil
        TestRun.expect(GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases")!, repository: repo) == nil,
                       "non-tag URL → nil")
    }

    /// 降级通道产物可与既有资产挑选逻辑闭环：探得的 ReleaseInfo 能选出安装包
    static func degradedReleaseSurvivesAssetSelection() {
        let repo = "hajifish/Cellular-Hotspot-Network-Monitor"
        let info = GithubReleaseChecker.releaseInfo(
            fromRedirectURL: URL(string: "https://github.com/\(repo)/releases/tag/v1.2.3")!, repository: repo)
        TestRun.expectEqual(GithubReleaseChecker.selectAsset(from: info!)?.name,
                           "TrafficMonitor-1.2.3.zip", "degraded release → selectable zip")
    }

    /// Result 的失败值（离线比对错误类型用）
    static func failureError(_ result: Result<ReleaseInfo, Error>) -> Error? {
        if case .failure(let error) = result { return error }
        return nil
    }

    /// Result 的成功值
    static func successInfo(_ result: Result<ReleaseInfo, Error>) -> ReleaseInfo? {
        if case .success(let info) = result { return info }
        return nil
    }

    /// 探测响应语义（离线构造 HTTPURLResponse，不出网）：传输层错误原样失败、
    /// 非 HTTP → badResponse、非 2xx → apiError(状态码)、2xx 按 tag 落点成败
    static func handleProbeResponseMapsOutcome() {
        let repo = "hajifish/Cellular-Hotspot-Network-Monitor"
        func probe(_ response: URLResponse?, error: Error? = nil) -> Result<ReleaseInfo, Error> {
            GithubReleaseChecker.handleProbeResponse(response: response, error: error, repository: repo)
        }
        func httpResponse(_ path: String, statusCode: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://github.com/\(repo)\(path)")!,
                            statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        }
        // 传输层错误原样传播
        TestRun.expect((failureError(probe(nil, error: URLError(.dnsLookupFailed))) as? URLError)?.code
                           == .dnsLookupFailed, "transport error propagates verbatim")
        // 非 HTTP 响应
        let plain = URLResponse(url: URL(string: "https://github.com/x")!, mimeType: nil,
                                expectedContentLength: 0, textEncodingName: nil)
        TestRun.expectEqual(failureError(probe(plain)) as? UpdateError, UpdateError.badResponse,
                            "non-HTTP response → badResponse")
        // 非 2xx 保留状态码
        TestRun.expectEqual(failureError(probe(httpResponse("/releases/latest", statusCode: 429))) as? UpdateError,
                           UpdateError.apiError(429), "429 → apiError(429)")
        // 2xx 但非 tag 页落点
        TestRun.expectEqual(failureError(probe(httpResponse("/releases", statusCode: 200))) as? UpdateError,
                           UpdateError.badResponse, "200 non-tag landing → badResponse")
        // 2xx tag 落点 → 成功且 ReleaseInfo 正确
        let info = successInfo(probe(httpResponse("/releases/tag/v1.2.3", statusCode: 200)))
        TestRun.expectEqual(info?.tagName, "v1.2.3", "200 tag landing → ReleaseInfo tag")
        TestRun.expectEqual(info?.assets.first?.name, "TrafficMonitor-1.2.3.zip", "200 tag landing asset")
    }

    /// 403 限流 → 转降级探测，且 completion 不被提前回调（spy probe 挂起不返回）
    static func routeFallsBackToProbeOnRateLimit() {
        var probeCalled = false
        GithubReleaseChecker.route(.failure(UpdateError.apiError(403)), repository: "hajifish/x",
                                   probe: { _, _ in probeCalled = true },
                                   completion: { _ in
                                       TestRun.expect(false, "completion fired before probe resolves")
                                   })
        TestRun.expect(probeCalled, "403 → probe invoked")
    }

    /// 500 服务端错误 → 不探测，原样回传 apiError(500)
    static func routeReportsServerErrorsAsIs() {
        var probed = false
        var delivered: Error?
        GithubReleaseChecker.route(.failure(UpdateError.apiError(500)), repository: "hajifish/x",
                                   probe: { _, _ in probed = true },
                                   completion: { if case .failure(let error) = $0 { delivered = error } })
        TestRun.expect(!probed, "500 → no probe")
        TestRun.expectEqual(delivered as? UpdateError, UpdateError.apiError(500), "500 → apiError(500) as-is")
    }

    /// probe 自身失败（如 DNS）→ 原样回传调用方，不被吞掉或二次包装
    static func routePropagatesProbeFailureVerbatim() {
        var delivered: Error?
        GithubReleaseChecker.route(.failure(UpdateError.apiError(429)), repository: "hajifish/x",
                                   probe: { _, completion in completion(.failure(URLError(.dnsLookupFailed))) },
                                   completion: { if case .failure(let error) = $0 { delivered = error } })
        TestRun.expect((delivered as? URLError)?.code == .dnsLookupFailed, "probe failure propagates verbatim")
    }

    /// 超时模拟默认关闭：TRAFFICMONITOR_UPDATE_TIMEOUT 未设时不应误触发短路
    static func simulatesTimeoutOffByDefault() {
        TestRun.expectEqual(GithubReleaseChecker.simulatesTimeout, false,
                            "env unset → simulatesTimeout false")
    }

    static func errorTextMapping() {
        TestRun.expectEqual(GithubReleaseChecker.errorText(URLError(.timedOut)), "网络不可用或连接超时", "timeout")
        TestRun.expectEqual(GithubReleaseChecker.errorText(UpdateError.apiError(403)), "GitHub 接口限流，请稍后再试", "rate limit")
        TestRun.expectEqual(GithubReleaseChecker.errorText(UpdateError.versionMismatch), "下载内容校验不符，已放弃安装", "mismatch")
        TestRun.expectEqual(GithubReleaseChecker.errorText(UpdateError.devBuild), "开发构建不支持应用内更新，请前往发布页下载", "dev build")
    }

    /// 实时集成：真实请求仓库 latest 并解码（与 ping 网关测试同风格，
    /// 无网 / 双通道皆断环境跳过）
    static func liveGithubLatest() {
        let sema = DispatchSemaphore(value: 0)
        var decoded: ReleaseInfo?
        GithubReleaseChecker.fetchLatestRaw(repository: "hajifish/Cellular-Hotspot-Network-Monitor") { result in
            if case .success(let release) = result { decoded = release }
            sema.signal()
        }
        sema.wait()
        guard let release = decoded else { // 无网 / 双通道皆断环境跳过（限流时降级探测会成功）
            print("  ⤷ skipped: no network")
            return
        }
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
        guard let probed else { // 无网环境跳过
            print("  ⤷ skipped: no network")
            return
        }
        TestRun.expect(!probed.isEmpty, "redirect probe resolves tag: \(probed)")
    }
}
