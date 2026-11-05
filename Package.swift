// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrafficMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // ObjC 桥：NSUserNotification 老通知接口对 Swift 模块不可见（AppKit swiftmodule
        // 已剔除），仅 clang 编译期可见——照抄 mac-notification-sys 的自带桥方案。
        .target(
            name: "TMNotify",
            path: "Sources/TMNotify",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        // 单可执行 target：自测代码内置于 SelfTest/ 目录，运行时以
        // TRAFFICMONITOR_SELFTEST=1 环境变量进入测试模式。
        // （本机仅有 CLT 工具链：XCTest 不可用，swift-testing 宏插件不稳定，
        //   executable→executable 的 @testable import 无法被显式模块扫描解析，
        //   单模块方案是唯一在 `swift build` 下完全确定的结构。）
        .executableTarget(
            name: "TrafficMonitor",
            dependencies: ["TMNotify"],
            path: "Sources/TrafficMonitor"
        ),
    ]
)
