import Foundation

/// 检查/安装阶段可归类的失败
enum UpdateError: Error, Equatable {
    case badResponse      // 非 HTTP 响应或 spawn 失败
    case apiError(Int)    // GitHub 返回非 2xx（403 = 限流）
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

    func fetchLatestRelease(completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        Self.fetchLatestRaw(repository: repository) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 原线程回调版本：实时集成自测用（避免主线程被信号量阻塞时死锁）
    static func fetchLatestRaw(repository: String,
                               completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return completion(.failure(UpdateError.badResponse))
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { return completion(.failure(error)) }
            guard let http = response as? HTTPURLResponse else {
                return completion(.failure(UpdateError.badResponse))
            }
            guard (200..<300).contains(http.statusCode), let data else {
                return completion(.failure(UpdateError.apiError(http.statusCode)))
            }
            completion(Result { try JSONDecoder().decode(ReleaseInfo.self, from: data) })
        }.resume()
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
