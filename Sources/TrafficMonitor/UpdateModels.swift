import Foundation

/// GitHub Release 资产（releases/latest 返回体中本应用关心的字段）
struct ReleaseAsset: Codable, Equatable {
    let name: String
    let size: Int
    let browserDownloadUrl: String

    private enum CodingKeys: String, CodingKey {
        case name, size
        case browserDownloadUrl = "browser_download_url"
    }
}

/// GitHub Release（draft/prerelease 不会出现在 releases/latest）
struct ReleaseInfo: Codable, Equatable {
    let tagName: String
    let htmlUrl: String
    let body: String? // Markdown 发布说明
    let assets: [ReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body, assets
    }
}

/// 版本来源与比较：打包 app 读 Info.plist；swift run 无 bundle 版本 → 0.0.0 开发构建
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 是否从打包的 .app 运行（决定能否应用内换包）
    static var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// 语义化版本严格比较：a > b。容忍 v 前缀；'-' 预发布后缀截断；
    /// 逐段数字比较，段数不足补零（0.2 ≡ 0.2.0）；非数字段按 0
    static func isNewer(_ a: String, than b: String) -> Bool {
        var lhs = numericComponents(a), rhs = numericComponents(b)
        let n = max(lhs.count, rhs.count)
        lhs += Array(repeating: 0, count: n - lhs.count)
        rhs += Array(repeating: 0, count: n - rhs.count)
        for i in 0..<n where lhs[i] != rhs[i] {
            return lhs[i] > rhs[i]
        }
        return false
    }

    static func numericComponents(_ version: String) -> [Int] {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v = String(v.dropFirst()) }
        if let dash = v.firstIndex(of: "-") { v = String(v[..<dash]) }
        return v.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// 发布说明摘要：按行与字符双截断，尾部加「…」，供主页卡片纯文本展示
    static func notesExcerpt(_ markdown: String?, maxLines: Int = 8, maxChars: Int = 300) -> String {
        guard let markdown, !markdown.isEmpty else { return "" }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: true).prefix(maxLines)
        var text = lines.joined(separator: "\n")
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "…" }
        return text
    }
}
