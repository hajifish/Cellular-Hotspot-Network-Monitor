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
    /// true 时挂起 completion，用 resolveDownload() 手动收尾（模拟下载中取消）
    var deferredDownload = false
    private var pendingCompletion: ((Result<URL, Error>) -> Void)?
    private(set) var downloadCount = 0
    private(set) var cancelCount = 0
    private(set) var installCount = 0
    private(set) var lastExpectedVersion: String?
    func download(from urlString: String, progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        downloadCount += 1
        progress(0.5)
        if deferredDownload {
            pendingCompletion = completion
        } else {
            completion(downloadResult)
        }
    }
    func resolveDownload() {
        pendingCompletion?(downloadResult)
        pendingCompletion = nil
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
        service.versionAvailableNotifier = { _ in } // 无 bundle 环境下系统通知会崩，注入 no-op
        return (service, checker, installer, exitCode)
    }

    static func checkFindsNewerVersion() {
        // 自测二进制无 bundle 版本 → 0.0.0，任何正常 tag 都算更新
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
        service.confirmRestartHandler = { _, _ in } // 停在 downloaded，不触发确认安装
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
        installer.deferredDownload = true // 挂起完成回调，真实停在下载中
        service.checkNow()
        service.startDownload()
        guard case .downloading = service.state else {
            return TestRun.expect(false, "expected downloading, got \(service.state)")
        }
        installer.downloadResult = .failure(URLError(.cancelled))
        service.cancelDownload()
        TestRun.expectEqual(installer.cancelCount, 1, "cancel forwarded")
        installer.resolveDownload()
        guard case .available = service.state else {
            return TestRun.expect(false, "expected available after cancel, got \(service.state)")
        }
        TestRun.expect(service.lastError == nil, "user cancel leaves no error")
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
        service.confirmRestartHandler = { _, _ in } // 停在 downloaded
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
