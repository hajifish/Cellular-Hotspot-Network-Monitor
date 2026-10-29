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

    /// 分离执行替换脚本。父进程 exit(0) 属正常退出，不会终止子进程；
    /// 脚本自身有 kill -0 等待环，与父进程退出的先后时序无关紧要。
    static func spawnDetached(scriptURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
