import Foundation
import os
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

    /// 诊断/验证用：TRAFFICMONITOR_AUTOUPDATE=1 时发现新版本即自动下载并确认重启
    /// （跳过确认弹窗），用于端到端自测；正常使用不设置该环境变量
    static var autoUpdateRequested: Bool {
        ProcessInfo.processInfo.environment["TRAFFICMONITOR_AUTOUPDATE"] == "1"
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
    /// 测试注入点：发现新版本时的系统通知（UNUserNotificationCenter 在无 bundle 的
    /// 自测二进制里会直接抛异常，故不可用默认实现直接跑自测）
    var versionAvailableNotifier: (ReleaseInfo) -> Void = UpdateService.postUpdateNotification
    /// 测试注入点：手动检查得出「已是最新」时的系统通知（同上，自测注入覆盖）
    var upToDateNotifier: () -> Void = UpdateService.postUpToDateNotification
    /// 本次检查是否由用户手动触发（决定「已是最新」是否打扰）
    private var manualCheckInFlight = false

    private let checker: UpdateChecking
    private let installer: UpdateDownloading
    private var notifiedTag: String?
    private var stagedAppURL: URL?
    private var cancellingDownload = false

    /// 通知投递等更新侧日志（与 TrafficMonitor.swift / TrafficMonitorApp.swift 同一 subsystem）
    private static let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "update")

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

    /// - Parameter manual: 用户手动触发（菜单/主页按钮）。仅手动检查得出「已是最新」
    ///   时发系统通知；自动检查（启动 10s / 每 6h）静默，避免打扰
    func checkNow(manual: Bool = false) {
        guard !isBusy else {
            // 收编在途检查为手动（issue #21）：自动轮询在途时用户手动点「检查更新」，
            // 结束后按手动口径反馈「已是最新」；仅 .checking 态收编——.downloading/.installing
            // 没有 fetch 在途，置位会泄漏到下一次检查误发通知
            if manual, case .checking = state { manualCheckInFlight = true }
            return
        }
        manualCheckInFlight = manual
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
                if Self.autoUpdateRequested { startDownload() } // 诊断/验证：自动进入下载
            } else {
                lastError = nil
                state = .upToDate
                if manualCheckInFlight { upToDateNotifier() }
            }
        }
        manualCheckInFlight = false
        emit()
    }

    /// 每次启动都会重新提醒（用户要求）；运行中同一版本只提醒一次
    private func notifyNewVersionOnce(_ release: ReleaseInfo) {
        guard notifiedTag != release.tagName else { return }
        notifiedTag = release.tagName
        versionAvailableNotifier(release)
    }

    static func postUpdateNotification(_ release: ReleaseInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 有新版本"
        content.body = "\(release.tagName) 可更新（当前 \(AppVersion.current)）。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "update-\(release.tagName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            // 投递失败记 error 级日志（菜单/主页仍有入口，但失败必须可检索）
            if let error {
                Self.logger.error("update notification delivery failed: \(String(describing: error), privacy: .public)")
            } else {
                Self.logger.debug("update notification delivered: \(release.tagName, privacy: .public)")
            }
        }
    }

    /// 手动检查确认已是最新：轻量通知告知即可。identifier 不带 "update-" 前缀，
    /// 点击不跳主页（无升级内容可看）。
    /// 注意：是否跳主页的判定在 MenuBarController 的
    /// `userNotificationCenter(_:didReceive:)` 里按 "update-" 前缀检查——
    /// "uptodate" 与 "update-" 一字之差，重命名 identifier 时两处必须同步，防静默破坏
    static func postUpToDateNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 已是最新版本"
        content.body = "当前 \(AppVersion.current) 即最新发布版。"
        let request = UNNotificationRequest(identifier: "uptodate-check", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            // 手动「已是最新」通知是唯一即时反馈，投递失败必须留痕
            if let error {
                Self.logger.error("up-to-date notification delivery failed: \(String(describing: error), privacy: .public)")
            } else {
                Self.logger.debug("up-to-date notification delivered")
            }
        }
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
        guard case .downloaded(let release) = state, let staged = stagedAppURL else { return }
        state = .installing
        emit()
        do {
            try installer.install(stagedApp: staged)
            exitHandler(0) // 分离脚本等本进程退出后换包并重启
        } catch {
            stagedAppURL = nil
            lastError = Self.errorText(error)
            state = .available(release)
            emit()
        }
    }

    private func confirmRestart(_ release: ReleaseInfo) {
        if Self.autoUpdateRequested {
            installNow() // 诊断/验证：跳过弹窗直接重启更新
            return
        }
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
