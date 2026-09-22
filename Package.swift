// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrafficMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TrafficMonitor", path: "Sources/TrafficMonitor"),
        .testTarget(name: "TrafficMonitorTests", dependencies: ["TrafficMonitor"], path: "Tests/TrafficMonitorTests"),
    ]
)
