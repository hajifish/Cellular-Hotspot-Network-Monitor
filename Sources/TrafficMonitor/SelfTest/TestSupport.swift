import Foundation

/// 极简测试收集器：记录断言通过/失败，最后以退出码报告。
enum TestRun {
    private(set) static var failures = 0
    private(set) static var checks = 0

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                       file: StaticString = #fileID, line: UInt = #line) {
        checks += 1
        if !condition {
            failures += 1
            print("  ✘ \(file):\(line) — \(message())")
        }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                          file: StaticString = #fileID, line: UInt = #line) {
        expect(actual == expected, "\(label): got \(actual), want \(expected)", file: file, line: line)
    }

    static func suite(_ name: String, _ body: () -> Void) {
        let before = failures
        print("── \(name)")
        body()
        print("   \(failures == before ? "ok" : "FAILED")")
    }

    static func finish() -> Never {
        if failures == 0 {
            print("✔ \(checks) checks passed")
        } else {
            print("✘ \(failures)/\(checks) checks failed")
        }
        exit(failures == 0 ? 0 : 1)
    }
}

/// 自测入口：TRAFFICMONITOR_SELFTEST=1 时由 Main.main 调用
enum SelfTest {
    @MainActor
    static func run() -> Never {
        TestRun.suite("ByteFormat") { ByteFormatTests.all() }
        TestRun.suite("TrafficMath") { TrafficMathTests.all() }
        TestRun.suite("UsageStore") { UsageStoreTests.all() }
        TestRun.suite("InterfaceSampler") { InterfaceSamplerTests.all() }
        TestRun.suite("TrafficMonitor") { TrafficMonitorTests.all() }
        TestRun.suite("RateHistory") { RateHistoryTests.all() }
        TestRun.suite("HomePage") { HomePageTests.all() }
        TestRun.suite("TrafficAlert") { TrafficAlertTests.all() }
        TestRun.suite("MilestoneTracker") { MilestoneTrackerTests.all() }
        TestRun.suite("StatusBarFormatter") { StatusBarFormatterTests.all() }
        TestRun.suite("MenuTextBuilder") { MenuTextBuilderTests.all() }
        TestRun.finish()
    }
}
