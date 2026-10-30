# 应用自动更新实施计划（GitHub Releases 检测 / 下载 / 换包 / 重启）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 应用自动检测 GitHub Releases 新版本，应用内下载、校验、确认后换包重启完成更新。

**Architecture:** 四个新模块（UpdateModels / UpdateChecker / UpdateInstaller / UpdateService）+ 展示映射（UpdatePresentation），接入现有 MenuBarController 菜单与 HomePageController 主页卡片。换包由分离进程执行 /bin/sh 脚本完成（等旧进程退出 → 备份改名 → 换入 → open）。

**Tech Stack:** Swift 5.9 + Foundation/AppKit/UserNotifications/Darwin，零第三方依赖，内置 TestRun 自测框架。

**Spec:** `docs/superpowers/specs/2026-10-29-auto-update-design.md`

## Global Constraints

- 零第三方依赖；仅可用 Foundation / AppKit / UserNotifications / Darwin / Observation
- **不使用 async/await**：CLT 工具链保守 + 自测需同步驱动。所有回调（progress/completion）保证在**主线程**回调——切线程的责任在生产实现（GithubReleaseChecker / UpdateInstaller 用 `DispatchQueue.main.async`），fake 同步回调使测试完全同步
- 测试框架：CLT 无 XCTest，用内置 `TestRun.expect / expectEqual / suite`；新套件必须注册进 `Sources/TrafficMonitor/SelfTest/TestSupport.swift` 的 `SelfTest.run()`（2026-10-29 基线 99 项，总数随之增长）
- 全部用户可见文案与注释**中文**
- 版本号容忍 `v` 前缀；只认 `releases/latest`（正式版）；开发构建（`swift run`，版本 `0.0.0`）不自动检查、不做应用内安装
- 不修改 `Package.swift`、`scripts/make-app.sh`、`scripts/package-release.sh`、`.github/workflows/*`（发布链路不动）
- 每步验证命令：
  - 构建：`swift build 2>&1 | tail -5`（期望无 error）
  - 自测：`TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -12`（期望 `✔ N checks passed`，N 只增不减）
- 提交信息以 `feat:`/`test:`/`docs:` 开头，结尾加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`

---

### Task 1: UpdateModels — Release 解码 + 版本比较 + 说明摘要

**Files:**
- Create: `Sources/TrafficMonitor/UpdateModels.swift`
- Create: `Sources/TrafficMonitor/SelfTest/UpdateModelsTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift`（注册套件）

**Interfaces:**
- Produces: `struct ReleaseAsset: Codable, Equatable`（`name: String` / `size: Int` / `browserDownloadUrl: String`）；`struct ReleaseInfo: Codable, Equatable`（`tagName` / `htmlUrl` / `body: String?` / `assets: [ReleaseAsset]`）；`enum AppVersion`（`static var current: String`、`static var isBundledApp: Bool`、`static func isNewer(_ a: String, than b: String) -> Bool`、`static func numericComponents(_ version: String) -> [Int]`、`static func notesExcerpt(_ markdown: String?, maxLines: Int = 8, maxChars: Int = 300) -> String`）

- [ ] **Step 1: 写失败测试** `Sources/TrafficMonitor/SelfTest/UpdateModelsTests.swift`

```swift
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
```

在 `TestSupport.swift` 的 `SelfTest.run()` 中（`StatusBarFormatter` 套件之后）注册：

```swift
        TestRun.suite("StatusBarFormatter") { StatusBarFormatterTests.all() }
        TestRun.suite("MenuTextBuilder") { MenuTextBuilderTests.all() }
        TestRun.suite("UpdateModels") { UpdateModelsTests.all() }
        TestRun.finish()
```

- [ ] **Step 2: 验证失败**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL，`UpdateModelsTests.swift` 报 `cannot find 'ReleaseInfo' in scope` 等编译错误

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/UpdateModels.swift`

```swift
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
        return lhs > rhs
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
```

- [ ] **Step 4: 验证通过**

Run: `TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -12`
Expected: 输出含 `── UpdateModels` 行 `ok`，总数 `✔ 111 checks passed`（99 + 12，左右即可，只看全绿）

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/UpdateModels.swift Sources/TrafficMonitor/SelfTest/
git commit -m "feat: release model decoding and semantic version comparison

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: UpdateChecker — GitHub API 请求 + 资产挑选 + 错误文案

**Files:**
- Create: `Sources/TrafficMonitor/UpdateChecker.swift`
- Create: `Sources/TrafficMonitor/SelfTest/UpdateCheckerTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift`（注册套件）

**Interfaces:**
- Consumes: `ReleaseInfo` / `ReleaseAsset` / `AppVersion`（Task 1）
- Produces: `enum UpdateError: Error, Equatable`（`badResponse` / `apiError(Int)` / `assetMissing` / `versionMismatch` / `devBuild`）；`protocol UpdateChecking { func fetchLatestRelease(completion: @escaping (Result<ReleaseInfo, Error>) -> Void) }`（**回调保证主线程**）；`struct GithubReleaseChecker: UpdateChecking`（`init(repository: String = "hajifish/Cellular-Hotspot-Network-Monitor")`；`static func fetchLatestRaw(repository:completion:)` 原线程回调，供实时集成测试）；`static func selectAsset(from: ReleaseInfo) -> ReleaseAsset?`；`static func errorText(_ error: Error) -> String`

- [ ] **Step 1: 写失败测试** `Sources/TrafficMonitor/SelfTest/UpdateCheckerTests.swift`

```swift
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
```

注册套件（`UpdateModels` 之后）：`TestRun.suite("UpdateChecker") { UpdateCheckerTests.all() }`

- [ ] **Step 2: 验证失败**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL，`cannot find 'GithubReleaseChecker' in scope`

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/UpdateChecker.swift`

```swift
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
```

- [ ] **Step 4: 验证通过**

Run: `TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -12`
Expected: `── UpdateChecker` 行 `ok`（联网环境会真实请求一次 GitHub），全绿

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/UpdateChecker.swift Sources/TrafficMonitor/SelfTest/
git commit -m "feat: GitHub releases checker with asset selection and error mapping

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: UpdateInstaller — 下载 / 解压校验 / 换包脚本 / 分离执行

**Files:**
- Create: `Sources/TrafficMonitor/UpdateInstaller.swift`
- Create: `Sources/TrafficMonitor/SelfTest/UpdateInstallerTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift`（注册套件）

**Interfaces:**
- Consumes: `UpdateError`（Task 2）、`AppVersion`（Task 1）
- Produces: `protocol UpdateDownloading: AnyObject`——`func download(from urlString: String, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void)`（progress/completion **主线程**回调；成功返回 zip 文件 URL）、`func cancelDownload()`、`func stageApp(fromZip zipURL: URL, expectedVersion: String) throws -> URL`（返回暂存 `.app` URL）、`func install(stagedApp: URL) throws`（成功后调用方应 `exit(0)`）；`final class UpdateInstaller: NSObject, UpdateDownloading, URLSessionDownloadDelegate`；`static func findVerifiedApp(in directory: URL, expectedVersion: String) throws -> URL`；`static func scriptContents() -> String`；`static func spawnDetached(scriptURL: URL, arguments: [String]) throws`

- [ ] **Step 1: 写失败测试** `Sources/TrafficMonitor/SelfTest/UpdateInstallerTests.swift`

```swift
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

    static func findVerifiedAppAcceptsMatchingVersion() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("umt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try makeFixtureApp(version: "0.3.0", in: dir)
        let app = try UpdateInstaller.findVerifiedApp(in: dir, expectedVersion: "v0.3.0")
        TestRun.expectEqual(app.lastPathComponent, "Traffic Monitor.app", "located app")
    }

    static func findVerifiedAppRejectsMismatch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("umt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try makeFixtureApp(version: "0.2.9", in: dir)
        TestRun.expectError(try UpdateInstaller.findVerifiedApp(in: dir, expectedVersion: "v0.3.0"),
                            equals: UpdateError.versionMismatch, "version mismatch refused")
    }

    static func findVerifiedAppRejectsMissingApp() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("umt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        TestRun.expectError(try UpdateInstaller.findVerifiedApp(in: dir, expectedVersion: "v0.3.0"),
                            equals: UpdateError.assetMissing, "no .app in directory")
    }
}
```

`expectError` 是新断言，先加进 `TestSupport.swift` 的 `TestRun`（`expectEqual` 之后）：

```swift
    static func expectError(_ expression: @autoclosure () throws -> Void,
                            equals expected: Error, _ label: String,
                            file: StaticString = #fileID, line: UInt = #line) {
        do {
            try expression()
            expect(false, "\(label): 期望抛错但没有", file: file, line: line)
        } catch {
            expect(String(describing: error) == String(describing: expected),
                   "\(label): got \(error), want \(expected)", file: file, line: line)
        }
    }
```

注册套件（`UpdateChecker` 之后）：`TestRun.suite("UpdateInstaller") { UpdateInstallerTests.all() }`

- [ ] **Step 2: 验证失败**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL，`cannot find 'UpdateInstaller' in scope`

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/UpdateInstaller.swift`

```swift
import Darwin
import Foundation

/// 下载与换包。回调契约：progress/completion 都在主线程回调。
protocol UpdateDownloading: AnyObject {
    /// 下载安装包 zip 到工作目录；成功经 completion 返回 zip URL
    func download(from urlString: String, progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void)
    func cancelDownload()
    /// 解压 zip → 定位 Traffic Monitor.app → 校验版本与目标 tag 一致
    func stageApp(fromZip zipURL: URL, expectedVersion: String) throws -> URL
    /// 生成替换脚本并分离执行；成功后调用方应尽快 exit(0)
    func install(stagedApp: URL) throws
}

final class UpdateInstaller: NSObject, UpdateDownloading, URLSessionDownloadDelegate {
    /// 下载与暂存共用的工作目录（系统临时目录，重启由系统清理）
    let workDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TrafficMonitorUpdate", isDirectory: true)

    private var session: URLSession!
    private var progressHandler: ((Double) -> Void)?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var task: URLSessionDownloadTask?

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func download(from urlString: String, progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        progressHandler = progress
        self.completion = completion
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        task = session.downloadTask(with: URL(string: urlString)!)
        task?.resume()
    }

    func cancelDownload() {
        task?.cancel()
    }

    // MARK: URLSessionDownloadDelegate（会话代理队列线程 → 主线程）

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progressHandler?(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let zipURL = workDirectory.appendingPathComponent("update.zip")
        try? FileManager.default.removeItem(at: zipURL)
        do {
            try FileManager.default.moveItem(at: location, to: zipURL)
            DispatchQueue.main.async { self.completion?(.success(zipURL)); self.completion = nil }
        } catch {
            DispatchQueue.main.async { self.completion?(.failure(error)); self.completion = nil }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return } // 正常结束由 didFinishDownloadingTo 汇报
        DispatchQueue.main.async { self.completion?(.failure(error)); self.completion = nil }
    }

    // MARK: 暂存与校验

    func stageApp(fromZip zipURL: URL, expectedVersion: String) throws -> URL {
        let stageDir = workDirectory.appendingPathComponent("staged", isDirectory: true)
        try? FileManager.default.removeItem(at: stageDir)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zipURL.path, "-d", stageDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.badResponse }
        return try Self.findVerifiedApp(in: stageDir, expectedVersion: expectedVersion)
    }

    /// 在目录中定位 .app 并校验版本号与目标 tag 一致（纯文件操作，可测）。
    /// 版本不符时绝不返回 URL——校验是安装前的最后闸门。
    static func findVerifiedApp(in directory: URL, expectedVersion: String) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.assetMissing
        }
        guard let info = Bundle(url: appURL)?.infoDictionary,
              let version = info["CFBundleShortVersionString"] as? String else {
            throw UpdateError.versionMismatch
        }
        guard AppVersion.numericComponents(version) == AppVersion.numericComponents(expectedVersion) else {
            throw UpdateError.versionMismatch
        }
        return appURL
    }

    // MARK: 换包脚本

    /// 替换脚本（纯函数，可测）：等旧进程退出 → 备份改名 → 换入新包 → open → 清理。
    /// 参数：$1=旧 .app 路径  $2=新 .app 路径  $3=旧进程 pid  $4=日志文件。
    /// 所有路径严格加引号（"Traffic Monitor.app" 含空格）。
    static func scriptContents() -> String {
        """
        #!/bin/sh
        # TrafficMonitor 自更新脚本（由 UpdateInstaller 生成）
        OLD_APP="$1"; NEW_APP="$2"; WAIT_PID="$3"; LOG="$4"
        {
          for i in $(seq 1 150); do kill -0 "$WAIT_PID" 2>/dev/null || break; sleep 0.1; done
          STAMP="$(date +%Y%m%d%H%M%S)"
          mv "$OLD_APP" "$OLD_APP.old-$STAMP" || exit 1
          if mv "$NEW_APP" "$OLD_APP"; then
            open "$OLD_APP" && rm -rf "$OLD_APP".old-*
          else
            mv "$OLD_APP.old-$STAMP" "$OLD_APP"   # 换入失败：回滚
            exit 1
          fi
        } >> "$LOG" 2>&1
        """
    }

    func install(stagedApp: URL) throws {
        let oldApp = Bundle.main.bundleURL
        let logURL = workDirectory.appendingPathComponent("update.log")
        let scriptURL = workDirectory.appendingPathComponent("replace.sh")
        try Self.scriptContents().write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try Self.spawnDetached(scriptURL: scriptURL,
                               arguments: [oldApp.path, stagedApp.path,
                                           String(ProcessInfo.processInfo.processIdentifier),
                                           logURL.path])
    }

    /// posix_spawn 分离执行（POSIX_SPAWN_SETSID：不随父进程退出被杀）
    static func spawnDetached(scriptURL: URL, arguments: [String]) throws {
        var attr = posix_spawnattr_t()
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        defer { posix_spawnattr_destroy(&attr) }
        var argv: [UnsafeMutablePointer<CChar>?] =
            ([scriptURL.path] + arguments).map { strdup($0) } + [nil]
        defer { for p in argv where p != nil { free(p) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, scriptURL.path, nil, &attr, &argv, environ)
        guard rc == 0 else { throw UpdateError.badResponse }
    }
}
```

- [ ] **Step 4: 验证通过**

Run: `TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -12`
Expected: `── UpdateInstaller` 行 `ok`，全绿

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/UpdateInstaller.swift Sources/TrafficMonitor/SelfTest/
git commit -m "feat: installer with staged download verification and atomic swap script

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: UpdateService — 状态机 + 定时检查 + 确认重启

**Files:**
- Create: `Sources/TrafficMonitor/UpdateService.swift`
- Create: `Sources/TrafficMonitor/SelfTest/UpdateServiceTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift`（注册套件）

**Interfaces:**
- Consumes: `UpdateChecking` / `GithubReleaseChecker.selectAsset` / `errorText`（Task 2）、`UpdateDownloading`（Task 3）、`AppVersion`（Task 1）
- Produces: `enum UpdateState: Equatable`（`idle` / `checking` / `upToDate` / `available(ReleaseInfo)` / `failed(String)` / `downloading(Double)` / `downloaded(ReleaseInfo)` / `installing`）；`final class UpdateService`——`init(checker: UpdateChecking = GithubReleaseChecker(), installer: UpdateDownloading = UpdateInstaller())`；`private(set) var state / lastError: String? / lastCheckDate: Date?`；`var onStateChange: (() -> Void)?`；`var confirmRestartHandler: ((ReleaseInfo, @escaping (Bool) -> Void) -> Void)?`；`var exitHandler: (Int32) -> Void`（默认 `exit`）；`var isBundledApp: () -> Bool`（默认 `AppVersion.isBundledApp`，测试注入）；`var isBusy: Bool`；`func checkNow() / startDownload() / cancelDownload() / cancelStagedUpdate() / installNow() / startAutomaticChecks() / applyAutoCheckPref()`；`static var autoCheckEnabled: Bool`（UserDefaults `autoCheckUpdates`，默认 true）

- [ ] **Step 1: 写失败测试** `Sources/TrafficMonitor/SelfTest/UpdateServiceTests.swift`

```swift
import Foundation

/// 同步 fake：completion 直接在调用线程回调（服务契约是"主线程回调"，自测在主线程）
final class FakeChecker: UpdateChecking {
    var result: Result<ReleaseInfo, Error>
    private(set) var callCount = 0
    init(result: Result<ReleaseInfo, Error>) { self.result = result }
    func fetchLatestRelease(completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        callCount += 1
        completion(result)
    }
}

final class FakeInstaller: UpdateDownloading {
    var downloadResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/fake.zip"))
    var stageResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/staged/Traffic Monitor.app"))
    var installError: Error?
    private(set) var downloadCount = 0
    private(set) var cancelCount = 0
    private(set) var installCount = 0
    private(set) var lastExpectedVersion: String?
    func download(from urlString: String, progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        downloadCount += 1
        progress(0.5)
        completion(downloadResult)
    }
    func cancelDownload() { cancelCount += 1 }
    func stageApp(fromZip zipURL: URL, expectedVersion: String) throws -> URL {
        lastExpectedVersion = expectedVersion
        return try stageResult.get()
    }
    func install(stagedApp: URL) throws {
        installCount += 1
        if let installError { throw installError }
    }
}

@MainActor
enum UpdateServiceTests {
    static func all() {
        checkFindsNewerVersion()
        checkUpToDate()
        checkFailureStoresError()
        downloadShowsProgressThenStages()
        downloadFailureReturnsToAvailable()
        downloadCancelIsQuiet()
        devBuildRefusesDownload()
        stageMismatchReturnsToAvailable()
        confirmYesInstallsAndExits()
        confirmNoKeepsStaged()
        cancelStagedReturnsToAvailable()
        autoCheckToggleControlsTimer()
    }

    static func makeRelease(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlUrl: "https://example.com/r/\(tag)",
                    body: "notes for \(tag)",
                    assets: [ReleaseAsset(name: "TrafficMonitor-\(tag).zip", size: 1,
                                          browserDownloadUrl: "https://example.com/\(tag).zip")])
    }

    static func makeService(release: Result<ReleaseInfo, Error>)
        -> (UpdateService, FakeChecker, FakeInstaller, UnsafeMutablePointer<Int32>) {
        let checker = FakeChecker(result: release)
        let installer = FakeInstaller()
        let exitCode = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        exitCode.initialize(to: -1)
        let service = UpdateService(checker: checker, installer: installer)
        service.isBundledApp = { true } // 自测二进制不在 .app 里，注入覆盖以驱动下载路径
        service.exitHandler = { exitCode.pointee = $0 }
        service.confirmRestartHandler = { _, completion in completion(true) } // 默认确认
        return (service, checker, installer, exitCode)
    }

    static func checkFindsNewerVersion() {
        // 自测二进制无 bundle 版本 → 0.0.0，任何正常 tag 都更新
        let (service, checker, _, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        TestRun.expectEqual(checker.callCount, 1, "checker called")
        guard case .available(let release) = service.state else {
            return TestRun.expect(false, "expected available, got \(service.state)")
        }
        TestRun.expectEqual(release.tagName, "0.1.0", "available release")
        TestRun.expect(service.lastCheckDate != nil, "lastCheckDate stamped")
    }

    static func checkUpToDate() {
        let (service, _, _, _) = makeService(release: .success(makeRelease("0.0.0")))
        service.checkNow()
        TestRun.expect(service.state == .upToDate, "equal version → upToDate, got \(service.state)")
    }

    static func checkFailureStoresError() {
        let (service, _, _, _) = makeService(release: .failure(URLError(.timedOut)))
        service.checkNow()
        guard case .failed(let message) = service.state else {
            return TestRun.expect(false, "expected failed, got \(service.state)")
        }
        TestRun.expectEqual(message, "网络不可用或连接超时", "error text")
    }

    static func downloadShowsProgressThenStages() {
        let (service, _, installer, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        service.startDownload()
        guard case .downloaded(let release) = service.state else {
            return TestRun.expect(false, "expected downloaded, got \(service.state)")
        }
        TestRun.expectEqual(release.tagName, "0.1.0", "downloaded release")
        TestRun.expectEqual(installer.downloadCount, 1, "download started")
        TestRun.expectEqual(installer.lastExpectedVersion, "0.1.0", "stage verified against tag")
    }

    static func downloadFailureReturnsToAvailable() {
        let (service, _, installer, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        installer.downloadResult = .failure(URLError(.networkConnectionLost))
        service.startDownload()
        guard case .available = service.state else {
            return TestRun.expect(false, "expected back to available, got \(service.state)")
        }
        TestRun.expectEqual(service.lastError, "网络不可用或连接超时", "error surfaced")
    }

    static func downloadCancelIsQuiet() {
        let (service, _, installer, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        service.startDownload() // fake 同步完成 → downloaded
        service.cancelDownload() // 非下载态，安全 no-op
        TestRun.expectEqual(installer.cancelCount, 1, "cancel forwarded even in downloaded state")
        guard case .downloaded = service.state else {
            return TestRun.expect(false, "downloaded preserved, got \(service.state)")
        }
    }

    static func devBuildRefusesDownload() {
        let (service, _, installer, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.isBundledApp = { false }
        service.checkNow()
        service.startDownload()
        TestRun.expectEqual(installer.downloadCount, 0, "no download in dev build")
        TestRun.expect(service.lastError != nil, "dev-build hint surfaced")
        guard case .available = service.state else {
            return TestRun.expect(false, "stays available, got \(service.state)")
        }
    }

    static func stageMismatchReturnsToAvailable() {
        let (service, _, installer, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        installer.stageResult = .failure(UpdateError.versionMismatch)
        service.startDownload()
        guard case .available = service.state else {
            return TestRun.expect(false, "expected available after mismatch, got \(service.state)")
        }
        TestRun.expectEqual(service.lastError, "下载内容校验不符，已放弃安装", "mismatch text")
    }

    static func confirmYesInstallsAndExits() {
        let (service, _, installer, exitCode) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        service.startDownload()
        service.installNow()
        TestRun.expectEqual(installer.installCount, 1, "install spawned")
        TestRun.expectEqual(exitCode.pointee, 0, "exits cleanly for swap script")
    }

    static func confirmNoKeepsStaged() {
        let (service, _, installer, exitCode) = makeService(release: .success(makeRelease("0.1.0")))
        service.confirmRestartHandler = { _, completion in completion(false) }
        service.checkNow()
        service.startDownload() // finishDownload → 确认弹窗被拒 → 不得自动安装
        TestRun.expectEqual(installer.installCount, 0, "no install on decline")
        TestRun.expectEqual(exitCode.pointee, -1, "no exit on decline")
        guard case .downloaded = service.state else {
            return TestRun.expect(false, "stays downloaded, got \(service.state)")
        }
    }

    static func cancelStagedReturnsToAvailable() {
        let (service, _, _, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        service.startDownload()
        service.cancelStagedUpdate()
        guard case .available = service.state else {
            return TestRun.expect(false, "expected available, got \(service.state)")
        }
    }

    static func autoCheckToggleControlsTimer() {
        let (service, _, _, _) = makeService(release: .success(makeRelease("0.1.0")))
        let original = UpdateService.autoCheckEnabled
        defer { UpdateService.autoCheckEnabled = original }
        UpdateService.autoCheckEnabled = true
        service.applyAutoCheckPref()
        TestRun.expect(service.checkTimer != nil, "timer armed when enabled")
        UpdateService.autoCheckEnabled = false
        service.applyAutoCheckPref()
        TestRun.expect(service.checkTimer == nil, "timer torn down when disabled")
    }
}
```

注意 `checkTimer` 要可断言——实现里声明为 `private(set) var checkTimer: Timer?`。`downloadCancelIsQuiet` 里 `service.state = ...` 需要可写——改为把该用例简化：去掉对 `state` 的直接赋值，验证 `cancelDownload` 在非下载态是安全 no-op 即可（fake 已同步完成，`cancelDownload` guard 会拦下）：

```swift
    static func downloadCancelIsQuiet() {
        let (service, _, installer, _) = makeService(release: .success(makeRelease("0.1.0")))
        service.checkNow()
        service.startDownload() // fake 同步完成 → downloaded
        service.cancelDownload() // 非下载态，安全 no-op
        TestRun.expectEqual(installer.cancelCount, 1, "cancel forwarded even in downloaded state")
        guard case .downloaded = service.state else {
            return TestRun.expect(false, "downloaded preserved, got \(service.state)")
        }
    }
```

（`state` 保持 `private(set)`，测试不得直接赋值。）

注册套件（`UpdateInstaller` 之后）：`TestRun.suite("UpdateService") { UpdateServiceTests.all() }`

- [ ] **Step 2: 验证失败**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL，`cannot find 'UpdateService' in scope`

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/UpdateService.swift`

```swift
import Foundation
import UserNotifications

/// 更新流程状态
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case failed(String)
    case downloading(Double)      // 进度 0...1
    case downloaded(ReleaseInfo)  // 已暂存待重启
    case installing
}

/// 更新状态机。主线程使用；checker/installer 的回调保证在主线程。
final class UpdateService {
    static let autoCheckKey = "autoCheckUpdates"

    /// 自动检查开关（默认开）
    static var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    private(set) var state: UpdateState = .idle
    private(set) var lastError: String?
    private(set) var lastCheckDate: Date?
    private(set) var checkTimer: Timer?

    /// 状态变化回调（主线程），UI 据此刷新
    var onStateChange: (() -> Void)?
    /// 下载完成后询问「立即重启？」；UI 层注入 NSAlert 实现，无注入则静默保持 downloaded
    var confirmRestartHandler: ((ReleaseInfo, @escaping (Bool) -> Void) -> Void)?
    /// 测试注入点：默认直接 exit
    var exitHandler: (Int32) -> Void = { exit($0) }
    /// 测试注入点：是否从打包 .app 运行
    var isBundledApp: () -> Bool = { AppVersion.isBundledApp }

    private let checker: UpdateChecking
    private let installer: UpdateDownloading
    private var notifiedTag: String?
    private var stagedAppURL: URL?
    private var cancellingDownload = false

    init(checker: UpdateChecking = GithubReleaseChecker(),
         installer: UpdateDownloading = UpdateInstaller()) {
        self.checker = checker
        self.installer = installer
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: 检查

    func checkNow() {
        guard !isBusy else { return }
        state = .checking
        emit()
        checker.fetchLatestRelease { [weak self] result in
            self?.finishCheck(result)
        }
    }

    private func finishCheck(_ result: Result<ReleaseInfo, Error>) {
        lastCheckDate = Date()
        switch result {
        case .failure(let error):
            lastError = Self.errorText(error)
            state = .failed(lastError ?? "检查失败")
        case .success(let release):
            if AppVersion.isNewer(release.tagName, than: AppVersion.current) {
                lastError = nil
                state = .available(release)
                notifyNewVersionOnce(release)
            } else {
                lastError = nil
                state = .upToDate
            }
        }
        emit()
    }

    /// 每次启动都会重新提醒（用户要求）；运行中同一版本只提醒一次
    private func notifyNewVersionOnce(_ release: ReleaseInfo) {
        guard notifiedTag != release.tagName else { return }
        notifiedTag = release.tagName
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 有新版本"
        content.body = "新版本 \(release.tagName) 已发布（当前 \(AppVersion.current)），可从菜单或主页更新。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "update-\(release.tagName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in } // 通知不可用时静默：菜单/主页仍有入口
    }

    // MARK: 下载

    func startDownload() {
        guard case .available(let release) = state else { return }
        guard isBundledApp() else {
            lastError = Self.errorText(UpdateError.devBuild)
            emit()
            return
        }
        guard let asset = GithubReleaseChecker.selectAsset(from: release) else {
            lastError = Self.errorText(UpdateError.assetMissing)
            emit()
            return
        }
        state = .downloading(0)
        lastError = nil
        emit()
        installer.download(from: asset.browserDownloadUrl,
                           progress: { [weak self] fraction in self?.applyProgress(fraction) },
                           completion: { [weak self] result in
                               self?.finishDownload(release: release, result: result)
                           })
    }

    private func applyProgress(_ fraction: Double) {
        guard case .downloading = state else { return }
        state = .downloading(min(max(fraction, 0), 1))
        emit()
    }

    private func finishDownload(release: ReleaseInfo, result: Result<URL, Error>) {
        defer { emit() }
        switch result {
        case .failure(let error):
            state = .available(release)
            if cancellingDownload {
                cancellingDownload = false
                lastError = nil
            } else {
                lastError = Self.errorText(error)
            }
        case .success(let zipURL):
            do {
                stagedAppURL = try installer.stageApp(fromZip: zipURL, expectedVersion: release.tagName)
                lastError = nil
                state = .downloaded(release)
            } catch {
                state = .available(release)
                lastError = Self.errorText(error)
            }
        }
        if case .downloaded = state { confirmRestart(release) }
    }

    func cancelDownload() {
        guard case .downloading = state else { return }
        cancellingDownload = true
        installer.cancelDownload()
    }

    /// 丢弃已暂存的更新，回到 available
    func cancelStagedUpdate() {
        guard case .downloaded(let release) = state else { return }
        if let stagedAppURL {
            try? FileManager.default.removeItem(at: stagedAppURL.deletingLastPathComponent())
        }
        stagedAppURL = nil
        state = .available(release)
        emit()
    }

    // MARK: 安装（换包 + 重启）

    func installNow() {
        guard case .downloaded(let release) = state, let stagedAppURL else { return }
        state = .installing
        emit()
        do {
            try installer.install(stagedApp: stagedAppURL)
            exitHandler(0) // 分离脚本等本进程退出后换包并重启
        } catch {
            stagedAppURL = nil
            lastError = Self.errorText(error)
            state = .available(release)
            emit()
        }
    }

    private func confirmRestart(_ release: ReleaseInfo) {
        guard let confirmRestartHandler else { return }
        confirmRestartHandler(release) { [weak self] confirmed in
            if confirmed { self?.installNow() }
        }
    }

    // MARK: 自动检查

    /// 打包运行时调用：启动 10 秒后首查 + 每 6 小时轮询（开发构建不自动检查）
    func startAutomaticChecks() {
        guard isBundledApp(), Self.autoCheckEnabled else { return }
        applyAutoCheckPref()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkNow() }
    }

    /// 偏好开关切换后调用：开=重建定时器，关=停表
    func applyAutoCheckPref() {
        checkTimer?.invalidate()
        checkTimer = nil
        guard Self.autoCheckEnabled else { return }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
    }

    private func emit() {
        onStateChange?()
    }

    static func errorText(_ error: Error) -> String {
        GithubReleaseChecker.errorText(error)
    }
}
```

- [ ] **Step 4: 验证通过**

Run: `TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -12`
Expected: `── UpdateService` 行 `ok`，全绿

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/UpdateService.swift Sources/TrafficMonitor/SelfTest/
git commit -m "feat: update state machine with staged install and confirm-restart flow

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 5: UpdatePresentation — 菜单与主页卡片的展示映射（纯函数）

**Files:**
- Create: `Sources/TrafficMonitor/UpdatePresentation.swift`
- Create: `Sources/TrafficMonitor/SelfTest/UpdatePresentationTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift`（注册套件）

**Interfaces:**
- Consumes: `UpdateState`（Task 4）、`AppVersion`（Task 1）
- Produces: `enum UpdatePresentation`——`struct MenuContent: Equatable { info / infoBold / primary: String? / primaryEnabled / secondary: String? }`；`static func menuContent(for state: UpdateState, currentVersion: String) -> MenuContent`；`enum CardKind { neutral / ok / attention / error }`；`struct CardContent: Equatable { status / kind / notes / primary: String? / secondary: String? }`；`static func cardContent(for state: UpdateState, currentVersion: String, lastCheck: Date?, errorText: String?) -> CardContent`

- [ ] **Step 1: 写失败测试** `Sources/TrafficMonitor/SelfTest/UpdatePresentationTests.swift`

```swift
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
```

注册套件（`UpdateService` 之后）：`TestRun.suite("UpdatePresentation") { UpdatePresentationTests.all() }`

- [ ] **Step 2: 验证失败**

Run: `swift build 2>&1 | tail -5`
Expected: FAIL，`cannot find 'UpdatePresentation' in scope`

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/UpdatePresentation.swift`

```swift
import Foundation

/// 菜单栏与主页卡片的展示映射（纯函数，可测）；着色等 AppKit 细节在 UI 层完成
enum UpdatePresentation {
    struct MenuContent: Equatable {
        let info: String
        let infoBold: Bool
        let primary: String?   // nil = 隐藏
        let primaryEnabled: Bool
        let secondary: String? // nil = 隐藏
    }

    static func menuContent(for state: UpdateState, currentVersion: String) -> MenuContent {
        switch state {
        case .idle:
            return MenuContent(info: "版本 \(currentVersion)", infoBold: false,
                               primary: "检查更新…", primaryEnabled: true, secondary: nil)
        case .checking:
            return MenuContent(info: "正在检查更新…", infoBold: false,
                               primary: nil, primaryEnabled: false, secondary: nil)
        case .upToDate:
            return MenuContent(info: "版本 \(currentVersion) ✓", infoBold: false,
                               primary: "检查更新…", primaryEnabled: true, secondary: nil)
        case .available(let release):
            return MenuContent(info: "⬆️ 新版本 \(release.tagName) 可用", infoBold: true,
                               primary: "下载并更新", primaryEnabled: true, secondary: "查看更新内容")
        case .failed:
            return MenuContent(info: "检查更新失败", infoBold: false,
                               primary: "重试检查", primaryEnabled: true, secondary: nil)
        case .downloading(let progress):
            return MenuContent(info: "下载更新中… \(Int(progress * 100))%", infoBold: false,
                               primary: nil, primaryEnabled: false, secondary: "取消下载")
        case .downloaded(let release):
            return MenuContent(info: "已下载 \(release.tagName)，待重启", infoBold: false,
                               primary: "重启以完成更新", primaryEnabled: true, secondary: "取消更新")
        case .installing:
            return MenuContent(info: "正在重启更新…", infoBold: false,
                               primary: nil, primaryEnabled: false, secondary: nil)
        }
    }

    /// 卡片内容颜色语义（着色在 HomePageController 做）
    enum CardKind: Equatable {
        case neutral, ok, attention, error
    }

    struct CardContent: Equatable {
        let status: String
        let kind: CardKind
        let notes: String
        let primary: String?
        let secondary: String?
    }

    static func cardContent(for state: UpdateState, currentVersion: String,
                            lastCheck: Date?, errorText: String?) -> CardContent {
        let checkedAt = lastCheck.map { "上次检查 \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        switch state {
        case .idle:
            return CardContent(status: "当前版本 \(currentVersion)", kind: .neutral,
                               notes: "尚未检查过更新", primary: "检查更新", secondary: nil)
        case .checking:
            return CardContent(status: "当前版本 \(currentVersion)", kind: .neutral,
                               notes: "正在检查更新…", primary: nil, secondary: nil)
        case .upToDate:
            return CardContent(status: "当前版本 \(currentVersion) · 已是最新", kind: .ok,
                               notes: checkedAt, primary: "检查更新", secondary: nil)
        case .available(let release):
            let excerpt = AppVersion.notesExcerpt(release.body)
            return CardContent(status: "发现新版本 \(release.tagName)", kind: .attention,
                               notes: excerpt.isEmpty ? checkedAt : excerpt,
                               primary: "下载并更新", secondary: "打开发布页")
        case .failed:
            return CardContent(status: "检查更新失败", kind: .error,
                               notes: errorText ?? "", primary: "重试检查", secondary: nil)
        case .downloading(let progress):
            return CardContent(status: "正在下载更新 \(Int(progress * 100))%", kind: .attention,
                               notes: "", primary: nil, secondary: "取消下载")
        case .downloaded(let release):
            return CardContent(status: "\(release.tagName) 已就绪，重启后生效", kind: .attention,
                               notes: "安装包已校验并暂存，重启应用即完成更新",
                               primary: "重启以完成更新", secondary: "取消更新")
        case .installing:
            return CardContent(status: "正在重启完成更新…", kind: .attention,
                               notes: "", primary: nil, secondary: nil)
        }
    }
}
```

- [ ] **Step 4: 验证通过**

Run: `TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -12`
Expected: `── UpdatePresentation` 行 `ok`，全绿

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/UpdatePresentation.swift Sources/TrafficMonitor/SelfTest/
git commit -m "feat: menu and home-card presentation mapping for update states

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 6: MenuBarController 接入 — 更新菜单区 + 通知点击 + 确认弹窗

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`

**Interfaces:**
- Consumes: `UpdateService` / `UpdateState`（Task 4）、`UpdatePresentation.menuContent`（Task 5）、`ReleaseInfo`（Task 1）
- Produces: 菜单「版本/更新」区（`updateInfoItem` / `updatePrimaryItem` / `updateSecondaryItem` / `autoCheckItem`）；`MenuBarController` 成为 `UNUserNotificationCenterDelegate`；`updateService.confirmRestartHandler` 注入 NSAlert 确认弹窗。HomePageController 的接入在 Task 7（本任务 `onStateChange` 只刷新菜单）

- [ ] **Step 1: 修改 `TrafficMonitorApp.swift`**

1a. 类声明加协议，新增属性（`private var changeObserverID: UUID?` 之前）：

```swift
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate, UNUserNotificationCenterDelegate {
```

```swift
    private let updateService = UpdateService()
    private var updateInfoItem: NSMenuItem!
    private var updatePrimaryItem: NSMenuItem!
    private var updateSecondaryItem: NSMenuItem!
    private var autoCheckItem: NSMenuItem!
```

1b. `install()` 菜单构建处（现有 `menu.addItem(alertItem)` 与 `menu.addItem(.separator())` / `menu.addItem(quit)` 之间），改为：

```swift
        menu.addItem(startTimeItem)
        menu.addItem(.separator())
        menu.addItem(wifiItem)
        menu.addItem(iphoneItem)
        menu.addItem(.separator())
        menu.addItem(openHome)
        menu.addItem(alertItem)
        menu.addItem(.separator())
        updateInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        updatePrimaryItem = NSMenuItem(title: "", action: #selector(updatePrimaryAction), keyEquivalent: "")
        updatePrimaryItem.target = self
        updateSecondaryItem = NSMenuItem(title: "", action: #selector(updateSecondaryAction), keyEquivalent: "")
        updateSecondaryItem.target = self
        autoCheckItem = NSMenuItem(title: "自动检查更新", action: #selector(toggleAutoCheck), keyEquivalent: "")
        autoCheckItem.target = self
        autoCheckItem.state = UpdateService.autoCheckEnabled ? .on : .off
        menu.addItem(updateInfoItem)
        menu.addItem(updatePrimaryItem)
        menu.addItem(updateSecondaryItem)
        menu.addItem(autoCheckItem)
        menu.addItem(.separator())
        menu.addItem(quit)
```

1c. `install()` 尾部（`monitor.start()` / `refresh()` 之前）接入服务回调与通知代理：

```swift
        updateService.onStateChange = { [weak self] in
            self?.refreshUpdateItems()
        }
        updateService.confirmRestartHandler = { [weak self] release, completion in
            self?.showRestartConfirm(release: release, completion: completion)
        }
        UNUserNotificationCenter.current().delegate = self
        updateService.startAutomaticChecks()
```

1d. 新增方法（`refreshAlertMenuStates()` 之后的合适位置）：

```swift
    // MARK: - 软件更新

    private func refreshUpdateItems() {
        let content = UpdatePresentation.menuContent(for: updateService.state,
                                                     currentVersion: AppVersion.current)
        updateInfoItem.attributedTitle = NSAttributedString(string: content.info, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: content.infoBold ? .semibold : .regular),
            .foregroundColor: content.infoBold ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
        updateInfoItem.isEnabled = false
        updatePrimaryItem.title = content.primary ?? ""
        updatePrimaryItem.isHidden = content.primary == nil
        updatePrimaryItem.isEnabled = content.primaryEnabled
        updateSecondaryItem.title = content.secondary ?? ""
        updateSecondaryItem.isHidden = content.secondary == nil
        updateSecondaryItem.isEnabled = true
    }

    @objc private func updatePrimaryAction() {
        switch updateService.state {
        case .available: updateService.startDownload()
        case .downloaded: updateService.installNow()
        default: updateService.checkNow() // idle / upToDate / failed
        }
    }

    @objc private func updateSecondaryAction() {
        switch updateService.state {
        case .available(let release): openRelease(release)
        case .downloaded: updateService.cancelStagedUpdate()
        case .downloading: updateService.cancelDownload()
        default: break
        }
    }

    private func openRelease(_ release: ReleaseInfo) {
        guard let url = URL(string: release.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleAutoCheck() {
        UpdateService.autoCheckEnabled.toggle()
        autoCheckItem.state = UpdateService.autoCheckEnabled ? .on : .off
        updateService.applyAutoCheckPref()
    }

    /// 下载完成后的确认弹窗（用户决策：确认后才换包重启）
    private func showRestartConfirm(release: ReleaseInfo, completion: @escaping (Bool) -> Void) {
        let dialog = NSAlert()
        dialog.messageText = "更新已就绪"
        dialog.informativeText = "新版本 \(release.tagName) 已下载并校验完成。立即重启以完成更新？"
        dialog.addButton(withTitle: "立即重启")
        dialog.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        completion(dialog.runModal() == .alertFirstButtonReturn)
    }
```

1e. 文件底部追加通知代理扩展（点击更新通知 → 打开主页；前台也显示横幅——对既有告警/里程碑通知同为改善）：

```swift
extension MenuBarController {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("update-") {
            openHome()
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
```

- [ ] **Step 2: 构建与自测**

Run: `swift build 2>&1 | tail -5 && TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -3`
Expected: 无 error，全绿（UI 接线不改逻辑，既有用例不变）

- [ ] **Step 3: 手动冒烟（开发构建行为）**

Run: `TRAFFICMONITOR_SHOWHOME=1 swift run TrafficMonitor & sleep 3`，点菜单栏图标查看：
Expected: 菜单出现「版本 0.0.0 / 检查更新… / 自动检查更新 ✓」；点「检查更新…」→ 变为「⬆️ 新版本 v0.1.0 可用（加粗）+ 下载并更新 + 查看更新内容」；点「下载并更新」→ 因开发构建被拒（主页 Task 7 完成后可见提示文案，此时观察 `log stream` 无崩溃）；系统出现「Traffic Monitor 有新版本」通知（如已授权）。验证后 `kill %1`。

- [ ] **Step 4: 提交**

```bash
git add Sources/TrafficMonitor/TrafficMonitorApp.swift
git commit -m "feat: menu bar update section, notification actions, restart confirmation

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 7: HomePageController 接入 — 主页「软件更新」卡片

**Files:**
- Modify: `Sources/TrafficMonitor/HomePageController.swift`
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（`onStateChange` 补主页刷新、homeController 构造参数）

**Interfaces:**
- Consumes: `UpdateService`（Task 4）、`UpdatePresentation.cardContent` / `CardKind`（Task 5）
- Produces: `HomePageController.init(monitor: TrafficMonitor, updateService: UpdateService)`；`func refreshUpdateCard()`（公开，供 `onStateChange` 触发）

- [ ] **Step 1: 窗体增高 + 现有元素上移**

窗口与背景从 428 → 512 高（底部腾出 84pt 放更新卡片），现有所有视图 y 坐标 +84：

| 位置 | 原 y | 新 y |
|---|---|---|
| `window = NSWindow(contentRect: ... height: 428 ...)` | 428 | 512 |
| `NSVisualEffectView(frame: ... height: 428)` | 428 | 512 |
| `totalsToggle.frame` | 384 | 468 |
| `totalsLabel.frame` | 386 | 470 |
| `ratesToggle.frame` | 384 | 468 |
| `ratesLabel.frame` | 386 | 470 |
| `cardSpecs` 卡片 `y: 180` | 180 | 264 |
| 会话/告警 `strip` `y: 322` | 322 | 406 |
| `sectionLabel` `y: 148` | 148 | 232 |
| `graphView` `y: 36` | 36 | 120 |
| `legendLabel` `y: 12` | 12 | 96 |

- [ ] **Step 2: 新增属性与构造参数**

```swift
    private let updateService: UpdateService
    private var updateStatusLabel: NSTextField!
    private var updateNotesLabel: NSTextField!
    private var updatePrimaryButton: NSButton!
    private var updateSecondaryButton: NSButton!
    private var updateProgress: NSProgressIndicator!

    init(monitor: TrafficMonitor, updateService: UpdateService) {
        self.monitor = monitor
        self.updateService = updateService
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 512), ...)
        // 其余不变
```

- [ ] **Step 3: buildUI() 末尾（`updateLegend()` 之后）建卡片**

```swift
        // 软件更新卡片：版本状态 + 发布说明摘要 + 上下文按钮 + 下载进度
        let updateCard = roundedCard(frame: NSRect(x: 24, y: 8, width: 672, height: 76))
        content.addSubview(updateCard)
        let updateCaption = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
        updateCaption.stringValue = "软件更新"
        updateCaption.frame = NSRect(x: 18, y: 56, width: 200, height: 12)
        updateCard.contentView?.addSubview(updateCaption)
        updateStatusLabel = makeLabel(size: 12, color: .labelColor, weight: .semibold)
        updateStatusLabel.frame = NSRect(x: 18, y: 30, width: 390, height: 20)
        updateStatusLabel.lineBreakMode = .byClipping
        updateCard.contentView?.addSubview(updateStatusLabel)
        updateNotesLabel = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
        updateNotesLabel.frame = NSRect(x: 18, y: 8, width: 390, height: 20)
        updateNotesLabel.lineBreakMode = .byTruncatingTail
        updateCard.contentView?.addSubview(updateNotesLabel)
        updatePrimaryButton = NSButton(title: "检查更新", target: self, action: #selector(updatePrimaryAction))
        updatePrimaryButton.frame = NSRect(x: 420, y: 24, width: 118, height: 28)
        updatePrimaryButton.bezelStyle = .rounded
        updateCard.contentView?.addSubview(updatePrimaryButton)
        updateSecondaryButton = NSButton(title: "", target: self, action: #selector(updateSecondaryAction))
        updateSecondaryButton.frame = NSRect(x: 546, y: 24, width: 110, height: 28)
        updateSecondaryButton.bezelStyle = .rounded
        updateSecondaryButton.isHidden = true
        updateCard.contentView?.addSubview(updateSecondaryButton)
        updateProgress = NSProgressIndicator(frame: NSRect(x: 420, y: 10, width: 236, height: 8))
        updateProgress.isIndeterminate = false
        updateProgress.minValue = 0
        updateProgress.maxValue = 1
        updateProgress.isHidden = true
        updateCard.contentView?.addSubview(updateProgress)
        refreshUpdateCard()
```

- [ ] **Step 4: 刷新与动作方法**（`refresh()` 尾部追加 `refreshUpdateCard()`；新增方法放在「按模块重置」区之后）

```swift
    // MARK: - 软件更新卡片

    /// 服务状态变化与每秒刷新共用；按钮文案/可用性由展示映射给出
    func refreshUpdateCard() {
        let content = UpdatePresentation.cardContent(for: updateService.state,
                                                     currentVersion: AppVersion.current,
                                                     lastCheck: updateService.lastCheckDate,
                                                     errorText: updateService.lastError)
        updateStatusLabel.stringValue = content.status
        updateStatusLabel.textColor = color(for: content.kind)
        updateNotesLabel.stringValue = content.notes
        if case .downloading(let progress) = updateService.state {
            updateProgress.isHidden = false
            updateProgress.doubleValue = progress
        } else {
            updateProgress.isHidden = true
        }
        updatePrimaryButton.title = content.primary ?? ""
        updatePrimaryButton.isHidden = content.primary == nil
        updateSecondaryButton.title = content.secondary ?? ""
        updateSecondaryButton.isHidden = content.secondary == nil
    }

    private func color(for kind: UpdatePresentation.CardKind) -> NSColor {
        switch kind {
        case .neutral: return .labelColor
        case .ok: return .systemGreen
        case .attention: return .systemOrange
        case .error: return .systemRed
        }
    }

    @objc private func updatePrimaryAction() {
        switch updateService.state {
        case .available: updateService.startDownload()
        case .downloaded: updateService.installNow()
        default: updateService.checkNow()
        }
    }

    @objc private func updateSecondaryAction() {
        switch updateService.state {
        case .available(let release):
            if let url = URL(string: release.htmlUrl) { NSWorkspace.shared.open(url) }
        case .downloaded: updateService.cancelStagedUpdate()
        case .downloading: updateService.cancelDownload()
        default: break
        }
    }
```

- [ ] **Step 5: MenuBarController 侧接线**（`TrafficMonitorApp.swift`）

```swift
    override init() {
        updateService = UpdateService()
        homeController = HomePageController(monitor: monitor, updateService: updateService)
        super.init()
        restoreAlertThreshold()
        StatusBarPrefs.migrateLegacyMode()
    }
```

注意：`updateService` 是 `private let updateService: UpdateService`（去掉 Task 6 的 `= UpdateService()` 默认初始化，改为 init 首行赋值，且必须排在 `homeController` 之前）。

`onStateChange` 闭包扩展：

```swift
        updateService.onStateChange = { [weak self] in
            self?.refreshUpdateItems()
            self?.homeController.refreshUpdateCard()
        }
```

- [ ] **Step 6: 构建自测 + 手动冒烟**

Run: `swift build 2>&1 | tail -5 && TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -3`
Expected: 全绿

Run: `TRAFFICMONITOR_SHOWHOME=1 swift run TrafficMonitor & sleep 3`
Expected: 主页底部出现「软件更新」卡片（窗口 720×512，布局无重叠）；点「检查更新」→ 状态变「发现新版本」+ 说明摘要 +「打开发布页」；点「下载并更新」→ 卡片出现开发构建提示。验证后 `kill %1`。

- [ ] **Step 7: 提交**

```bash
git add Sources/TrafficMonitor/HomePageController.swift Sources/TrafficMonitor/TrafficMonitorApp.swift
git commit -m "feat: home page software-update card wired to update service

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 8: 端到端打包冒烟 + 文档同步

**Files:**
- Modify: `CHANGELOG.md`（`## [Unreleased]` 小节）
- Modify: `README.md`（「功能」小节列表尾）与 `README.en.md`（对应 Features 列表）

**Interfaces:**
- Consumes: 前七个任务全部产物
- Produces: 文档同步完成；发布构建冒烟通过

- [ ] **Step 1: release 构建全量自测**

Run: `swift build -c release 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/release/TrafficMonitor 2>&1 | tail -3`
Expected: 全绿（与 CI `release.yml` 同路径）

- [ ] **Step 2: 打包冒烟**

Run: `./scripts/make-app.sh && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "Traffic Monitor.app/Contents/Info.plist"`
Expected: 打包成功；打包版 `.app` 手动打开（注意记忆坑：先 `ps -p <pid> -o lstart=` 确认是新进程）：菜单显示真实版本（开发仓库无版本注入则为 0.0.0 属预期）；打包运行时应触发 10 秒后自动检查（`log stream --predicate 'process == "TrafficMonitor"' --level debug` 观察）。

- [ ] **Step 3: 更新 CHANGELOG**

`## [Unreleased]` 小节改为：

```markdown
## [Unreleased]

### 新增 (Added)

- 应用自动更新：基于 GitHub Releases 检测新版本（启动后 10 秒首查、每 6 小时
  轮询，菜单可手动「检查更新」或关闭自动检查）；发现新版本时系统通知 +
  菜单栏与主页「软件更新」卡片同步提醒，应用内下载（带进度）并校验版本后
  确认重启即完成换包更新，失败自动回滚旧包；开发构建（`swift run`）仅提示
  并跳转发布页
```

- [ ] **Step 4: 更新 README.md 功能列表（列表尾追加一条，格式随现有条目）**

```markdown
- 自动更新：基于 GitHub Releases 检测新版本，应用内下载并确认重启即完成更新；
  可在菜单中手动检查或关闭自动检查
```

`README.en.md` 对应 Features 列表尾追加：

```markdown
- Auto-update: detects new releases via GitHub Releases, downloads in-app and
  restarts on confirmation; manual check and auto-check toggle in the menu
```

- [ ] **Step 5: 全量验证**

Run: `TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor 2>&1 | tail -3 && git status --short`
Expected: 全绿；工作区无意外文件

- [ ] **Step 6: 提交**

```bash
git add CHANGELOG.md README.md README.en.md
git commit -m "docs: auto-update feature in changelog and readme

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## 验收对照（spec → 任务）

| Spec 条目 | 任务 |
|---|---|
| GitHub API 检测 + 版本比较 | Task 1/2 |
| 应用内下载 + 校验 + 确认后换包重启 | Task 3/4/6 |
| 菜单版本/升级展示 + 自动检查开关 | Task 5/6 |
| 系统通知（启动提醒 + 点击打开主页） | Task 4（发送）/ Task 6（点击） |
| 主页更新卡片 | Task 5/7 |
| 失败矩阵（断网/限流/资产缺失/校验不符/回滚） | Task 2/3/4 用例 |
| 内置自测 + 实时 API 集成 | Task 1–5 + Task 2 live |
| 文档同步 | Task 8 |
| 端到端真实换包（需真实 Release） | 超出本计划：下次发版验证（spec 验收 4 已注明） |
