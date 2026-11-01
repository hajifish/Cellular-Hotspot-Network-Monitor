import Foundation

/// 检查/安装阶段可归类的失败
enum UpdateError: Error, Equatable {
    case badResponse      // 非 HTTP 响应或 spawn 失败
    case apiError(Int)    // GitHub 返回非 2xx（403/429 = 限流）
    case assetMissing     // Release 无可用 zip 资产
    case versionMismatch  // 新包版本与 tag 不符，拒绝安装
    case devBuild         // 开发构建不支持应用内更新
}

protocol UpdateChecking {
    /// 回调保证在主线程
    func fetchLatestRelease(completion: @escaping (Result<ReleaseInfo, Error>) -> Void)
}

struct GithubReleaseChecker: UpdateChecking {
    let repository: String

    init(repository: String = "hajifish/Cellular-Hotspot-Network-Monitor") {
        self.repository = repository
    }

    /// 诊断/验证用：TRAFFICMONITOR_UPDATE_TIMEOUT=1 时短路为连接超时失败——用于
    /// 目检失败可见性 UI（菜单「· 失败」+ 主页卡片），无需断网。短路仅在
    /// fetchLatestRelease；fetchLatestRaw/redirectProbe 不检查该变量。
    /// 正常使用不设置该环境变量
    static var simulatesTimeout: Bool {
        ProcessInfo.processInfo.environment["TRAFFICMONITOR_UPDATE_TIMEOUT"] == "1"
    }

    func fetchLatestRelease(completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        if Self.simulatesTimeout {
            return DispatchQueue.main.async { completion(.failure(URLError(.timedOut))) }
        }
        Self.fetchLatestRaw(repository: repository) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 原线程回调版本：实时集成自测用（避免主线程被信号量阻塞时死锁）。
    /// API 限流（403/429，共享出口 IP 环境常态）时自动降级网页重定向探测
    static func fetchLatestRaw(repository: String,
                               completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return completion(.failure(UpdateError.badResponse))
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            Self.route(Self.decodeLatestResponse(data: data, response: response, error: error),
                       repository: repository, completion: completion)
        }.resume()
    }

    /// API 响应 → Result（解析逻辑独立，便于直测）
    static func decodeLatestResponse(data: Data?, response: URLResponse?, error: Error?)
        -> Result<ReleaseInfo, Error> {
        if let error { return .failure(error) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(UpdateError.badResponse)
        }
        guard (200..<300).contains(http.statusCode), let data else {
            return .failure(UpdateError.apiError(http.statusCode))
        }
        return Result { try JSONDecoder().decode(ReleaseInfo.self, from: data) }
    }

    /// 仅限流类 API 失败值得降级探测；网络故障 / 服务端错误如实上报
    static func shouldFallbackToRedirectProbe(_ error: Error) -> Bool {
        if let updateError = error as? UpdateError, case .apiError(let code) = updateError {
            return code == 403 || code == 429
        }
        return false
    }

    /// 降级探测闭包（可注入 spy/stub 以离线验证路由决策）
    typealias RedirectProbe = (_ repository: String,
                               _ completion: @escaping (Result<ReleaseInfo, Error>) -> Void) -> Void

    /// API 结果 → 下一步路由：仅限流类失败（403/429）转降级探测，其余结果原样回调。
    /// probe 参数化，路由决策可离线验证
    static func route(_ result: Result<ReleaseInfo, Error>, repository: String,
                      probe: RedirectProbe = { GithubReleaseChecker.redirectProbe(repository: $0, completion: $1) },
                      completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        if case .failure(let error) = result, shouldFallbackToRedirectProbe(error) {
            return probe(repository, completion)
        }
        completion(result)
    }

    /// 降级探测：GET 网页端点 releases/latest（不受 API 配额限制），URLSession 跟随
    /// 302 落在 …/releases/tag/{tag}，从最终 URL 构造最小 ReleaseInfo。仅传输层错误
    /// 原样回调；状态码/落点异常归一为 apiError/badResponse（见 handleProbeResponse）
    static func redirectProbe(repository: String,
                              completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        guard let url = URL(string: "https://github.com/\(repository)/releases/latest") else {
            return completion(.failure(UpdateError.badResponse))
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        URLSession.shared.dataTask(with: request) { _, response, error in
            completion(Self.handleProbeResponse(response: response, error: error, repository: repository))
        }.resume()
    }

    /// 探测响应 → Result（独立于传输，便于直测）：传输层错误原样失败；非 HTTP 响应
    /// → badResponse；非 2xx → apiError(状态码)；2xx 非 tag 页落点 → badResponse；
    /// tag 页落点 → 最小 ReleaseInfo
    static func handleProbeResponse(response: URLResponse?, error: Error?, repository: String)
        -> Result<ReleaseInfo, Error> {
        if let error { return .failure(error) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(UpdateError.badResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(UpdateError.apiError(http.statusCode))
        }
        guard let finalURL = http.url ?? response?.url,
              let info = releaseInfo(fromRedirectURL: finalURL, repository: repository) else {
            return .failure(UpdateError.badResponse)
        }
        return .success(info)
    }

    /// tag 页 URL（…/releases/tag/{tag}）→ 最小 ReleaseInfo：body 为 nil（发布说明
    /// 不可得），资产按打包工作流的确定性命名构造（TrafficMonitor-{去v版本}.zip）。
    /// 非 tag 页落点返回 nil。tag 理论上可含斜杠，故取 "tag/" 之后的整段
    static func releaseInfo(fromRedirectURL url: URL, repository: String) -> ReleaseInfo? {
        let parts = url.pathComponents.filter { !$0.isEmpty }
        guard let tagIndex = parts.firstIndex(of: "tag"),
              tagIndex >= 1, tagIndex + 1 < parts.count,
              parts[tagIndex - 1] == "releases" else { return nil }
        let tag = parts[(tagIndex + 1)...].joined(separator: "/")
        guard !tag.isEmpty else { return nil }
        var version = tag
        if version.hasPrefix("v") || version.hasPrefix("V") { version = String(version.dropFirst()) }
        let zipName = "TrafficMonitor-\(version).zip"
        return ReleaseInfo(
            tagName: tag,
            htmlUrl: "https://github.com/\(repository)/releases/tag/\(tag)",
            body: nil,
            assets: [ReleaseAsset(name: zipName, size: 0,
                                  browserDownloadUrl: "https://github.com/\(repository)/releases/download/\(tag)/\(zipName)")])
    }

    /// 挑安装包资产：TrafficMonitor-*.zip（忽略 DMG），优先文件名含目标版本（去 v）
    static func selectAsset(from release: ReleaseInfo) -> ReleaseAsset? {
        var tag = release.tagName
        if tag.hasPrefix("v") || tag.hasPrefix("V") { tag = String(tag.dropFirst()) }
        let zips = release.assets.filter { $0.name.hasPrefix("TrafficMonitor-") && $0.name.hasSuffix(".zip") }
        return zips.first { $0.name == "TrafficMonitor-\(tag).zip" } ?? zips.first
    }

    /// 错误 → 用户可读文案
    static func errorText(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .notConnectedToInternet,
                 .networkConnectionLost, .dnsLookupFailed:
                return "网络不可用或连接超时"
            case .cancelled:
                return "已取消"
            default:
                break
            }
        }
        if let updateError = error as? UpdateError {
            switch updateError {
            case .apiError(403): return "GitHub 接口限流，请稍后再试"
            case .apiError(let code): return "GitHub 接口错误（\(code)）"
            case .badResponse: return "GitHub 响应异常"
            case .assetMissing: return "新版本的安装包尚未就绪，请稍后再试或前往发布页"
            case .versionMismatch: return "下载内容校验不符，已放弃安装"
            case .devBuild: return "开发构建不支持应用内更新，请前往发布页下载"
            }
        }
        return error.localizedDescription
    }
}
