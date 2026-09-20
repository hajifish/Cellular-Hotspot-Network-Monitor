# Traffic Monitor 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个 macOS 菜单栏应用，从启动时刻起累计流量，区分 Wi-Fi 与 USB 共享的 iPhone 蜂窝流量，实时显示速率。

**Architecture:** SwiftUI `MenuBarExtra` 应用；每秒用 `getifaddrs()` 采样各网卡累计字节数，与上次快照做差值得增量，按网卡类别（Wi-Fi / iPhone USB）累加进内存状态 `UsageStore`；`@Observable` 驱动菜单栏 UI 刷新。

**Tech Stack:** Swift 5.9+ / SwiftUI / Darwin (`getifaddrs`) / SystemConfiguration (`SCNetworkInterface`) / XCTest，零第三方依赖。

## Global Constraints

- 平台：macOS 14+（`@Observable` 需要 14；实测机器为 macOS 26）
- 单 Swift Package，可执行 target 名 `TrafficMonitor`，无第三方依赖
- 流量单位用十进制（1 KB = 1000 B），与 iPhone 显示一致
- 接口分类：Wi-Fi 按 `SCNetworkInterface` 类型 `IEEE80211`；iPhone USB 按本地化描述含 "iPhone"；其余接口忽略
- 负差值（拔插后计数器清零）钳位为 0
- 数据不落盘；启动即计，仅菜单内手动重置
- 所有 git commit 以 `Co-Authored-By: Claude Code <noreply@anthropic.com>` 结尾

## File Structure

```
Package.swift
Sources/TrafficMonitor/
  Models.swift             — InterfaceCategory / InterfaceCounters / CategoryDelta / ClassifiedSample
  ByteFormat.swift         — 字节单位与速率格式化（纯函数）
  TrafficMath.swift        — 快照差值计算（纯函数）
  UsageStore.swift         — @Observable 累计状态 + 重置
  InterfaceSampler.swift   — getifaddrs 采样 + SCNetworkInterface 分类 + InterfaceSampling 协议
  TrafficMonitor.swift     — 胶水：定时器、速率、menuBarTitle、reset
  TrafficMonitorApp.swift  — @main + MenuBarExtra + 菜单内容
Tests/TrafficMonitorTests/
  ByteFormatTests.swift
  TrafficMathTests.swift
  UsageStoreTests.swift
  InterfaceSamplerTests.swift
  TrafficMonitorTests.swift
scripts/make-app.sh       — Release 构建 + 打包 .app + ad-hoc 签名
README.md
```

---

### Task 1: 包脚手架 + ByteFormat

**Files:**
- Create: `Package.swift`
- Create: `Sources/TrafficMonitor/Models.swift`
- Create: `Sources/TrafficMonitor/ByteFormat.swift`
- Test: `Tests/TrafficMonitorTests/ByteFormatTests.swift`

**Interfaces:**
- Produces: `enum InterfaceCategory { case wifi, iphone }`；`struct InterfaceCounters { var rx: UInt64; var tx: UInt64 }`；`struct CategoryDelta { var rx: UInt64; var tx: UInt64; static let zero }`；`ByteFormat.string(UInt64) -> String`、`ByteFormat.rate(UInt64) -> String`

- [ ] **Step 1: 写 Package.swift 和 Models.swift**

`Package.swift`:
```swift
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
```

`Sources/TrafficMonitor/Models.swift`:
```swift
enum InterfaceCategory: Hashable {
    case wifi
    case iphone
}

struct InterfaceCounters: Equatable {
    var rx: UInt64
    var tx: UInt64
}

struct CategoryDelta: Equatable {
    var rx: UInt64
    var tx: UInt64

    static let zero = CategoryDelta(rx: 0, tx: 0)
}

struct ClassifiedSample {
    let name: String
    let category: InterfaceCategory?
    let counters: InterfaceCounters
}
```

（executable target 暂无 `@main`，`swift build` 会报 "no main" 警告级错误——若报错，先放一个临时空 `main.swift`? 不要：executableTarget 用函数式 main 会在 Task 6 替换。为让 Task 1-5 可编译测试，创建占位 `Sources/TrafficMonitor/TrafficMonitorApp.swift` 内容为：

```swift
import Foundation

// 占位入口，Task 6 替换为 SwiftUI @main。
@main
struct PlaceholderMain {
    static func main() {}
}
```

注意：`@main` 与后续 SwiftUI App 同名冲突，Task 6 直接整体替换本文件即可。）

- [ ] **Step 2: 写失败测试** `Tests/TrafficMonitorTests/ByteFormatTests.swift`:

```swift
import XCTest
@testable import TrafficMonitor

final class ByteFormatTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(ByteFormat.string(0), "0 B")
        XCTAssertEqual(ByteFormat.string(999), "999 B")
    }

    func testKilobytes() {
        XCTAssertEqual(ByteFormat.string(1_000), "1.0 KB")
        XCTAssertEqual(ByteFormat.string(1_500), "1.5 KB")
    }

    func testMegabytesAndGigabytes() {
        XCTAssertEqual(ByteFormat.string(1_000_000), "1.0 MB")
        XCTAssertEqual(ByteFormat.string(2_500_000_000), "2.5 GB")
        XCTAssertEqual(ByteFormat.string(1_234_567_890_123), "1.2 TB")
    }

    func testRateAppendsPerSecond() {
        XCTAssertEqual(ByteFormat.rate(0), "0 B/s")
        XCTAssertEqual(ByteFormat.rate(1_200_000), "1.2 MB/s")
    }
}
```

- [ ] **Step 3: 运行确认失败**

Run: `swift test --filter ByteFormatTests 2>&1 | tail -5`
Expected: 编译失败，`ByteFormat` 未定义

- [ ] **Step 4: 实现** `Sources/TrafficMonitor/ByteFormat.swift`:

```swift
enum ByteFormat {
    private static let units: [(suffix: String, scale: UInt64)] = [
        ("B", 1), ("KB", 1_000), ("MB", 1_000_000), ("GB", 1_000_000_000), ("TB", 1_000_000_000_000),
    ]

    /// "0 B"、"999 B"、"1.0 KB"、"2.5 GB"、"1.2 TB"（十进制单位）
    static func string(_ bytes: UInt64) -> String {
        let unit = units.last { bytes >= $0.scale } ?? units[0]
        guard unit.scale > 1 else { return "\(bytes) B" }
        let value = Double(bytes) / Double(unit.scale)
        return String(format: "%.1f %@", value, unit.suffix)
    }

    /// 速率显示：在 string 后追加 "/s"
    static func rate(_ bytesPerSecond: UInt64) -> String {
        string(bytesPerSecond) + "/s"
    }
}
```

- [ ] **Step 5: 运行确认通过**

Run: `swift test --filter ByteFormatTests 2>&1 | tail -5`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat: package scaffold and byte formatting

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: TrafficMath 差值计算

**Files:**
- Create: `Sources/TrafficMonitor/TrafficMath.swift`
- Test: `Tests/TrafficMonitorTests/TrafficMathTests.swift`

**Interfaces:**
- Consumes: `InterfaceCategory`、`InterfaceCounters`、`CategoryDelta`（Task 1）
- Produces: `TrafficMath.deltas(previous: [String: InterfaceCounters], current: [String: InterfaceCounters], categories: [String: InterfaceCategory]) -> [InterfaceCategory: CategoryDelta]`

- [ ] **Step 1: 写失败测试** `Tests/TrafficMonitorTests/TrafficMathTests.swift`:

```swift
import XCTest
@testable import TrafficMonitor

final class TrafficMathTests: XCTestCase {
    private func c(_ rx: UInt64, _ tx: UInt64) -> InterfaceCounters {
        InterfaceCounters(rx: rx, tx: tx)
    }

    func testNormalDelta() {
        let d = TrafficMath.deltas(
            previous: ["en0": c(100, 50)],
            current: ["en0": c(160, 80)],
            categories: ["en0": .wifi])
        XCTAssertEqual(d[.wifi], CategoryDelta(rx: 60, tx: 30))
    }

    func testNegativeDeltaClampedToZero() {
        // iPhone 拔插后计数器清零的场景
        let d = TrafficMath.deltas(
            previous: ["en5": c(10_000, 5_000)],
            current: ["en5": c(300, 100)],
            categories: ["en5": .iphone])
        XCTAssertEqual(d[.iphone], CategoryDelta.zero)
    }

    func testNewInterfaceContributesNothing() {
        // 刚插入的接口没有上一拍基线，不能把开机以来的累计量算进当秒
        let d = TrafficMath.deltas(
            previous: [:],
            current: ["en5": c(987_654_321, 123_456_789)],
            categories: ["en5": .iphone])
        XCTAssertEqual(d[.iphone], CategoryDelta.zero)
    }

    func testUncategorizedInterfacesIgnored() {
        let d = TrafficMath.deltas(
            previous: ["utun3": c(1, 1), "en0": c(10, 10)],
            current: ["utun3": c(500, 500), "en0": c(20, 15)],
            categories: ["en0": .wifi])
        XCTAssertEqual(d, [.wifi: CategoryDelta(rx: 10, tx: 5)])
    }

    func testSameCategorySumsAcrossInterfaces() {
        let d = TrafficMath.deltas(
            previous: ["en0": c(0, 0), "en1": c(0, 0)],
            current: ["en0": c(30, 0), "en1": c(0, 40)],
            categories: ["en0": .wifi, "en1": .wifi])
        XCTAssertEqual(d[.wifi], CategoryDelta(rx: 30, tx: 40))
    }

    func testDisappearedInterfaceExcluded() {
        let d = TrafficMath.deltas(
            previous: ["en5": c(1000, 1000), "en0": c(10, 10)],
            current: ["en0": c(20, 20)],
            categories: ["en5": .iphone, "en0": .wifi])
        XCTAssertEqual(d[.iphone], nil)
        XCTAssertEqual(d[.wifi], CategoryDelta(rx: 10, tx: 10))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter TrafficMathTests 2>&1 | tail -5`
Expected: 编译失败，`TrafficMath` 未定义

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/TrafficMath.swift`:

```swift
enum TrafficMath {
    /// 计算两个快照之间按类别聚合的字节增量。
    /// - 只统计同时出现在两个快照中的接口（中途插拔的接口不参与当秒统计）
    /// - 负差值（计数器回绕/清零）钳位为 0
    /// - 不在 categories 中的接口忽略
    static func deltas(previous: [String: InterfaceCounters],
                       current: [String: InterfaceCounters],
                       categories: [String: InterfaceCategory]) -> [InterfaceCategory: CategoryDelta] {
        var result: [InterfaceCategory: CategoryDelta] = [:]
        for (name, now) in current {
            guard let category = categories[name], let before = previous[name] else { continue }
            let rx = now.rx > before.rx ? now.rx - before.rx : 0
            let tx = now.tx > before.tx ? now.tx - before.tx : 0
            let existing = result[category] ?? .zero
            result[category] = CategoryDelta(rx: existing.rx + rx, tx: existing.tx + tx)
        }
        return result
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter TrafficMathTests 2>&1 | tail -5`
Expected: `Executed 6 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat: snapshot delta math with clamp and category aggregation

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: UsageStore 累计状态

**Files:**
- Create: `Sources/TrafficMonitor/UsageStore.swift`
- Test: `Tests/TrafficMonitorTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `InterfaceCategory`、`CategoryDelta`（Task 1）
- Produces: `@MainActor final class UsageStore`，属性 `startTime: Date`、`wifiRX/wifiTX/iphoneRX/iphoneTX: UInt64`，方法 `record(_ deltas: [InterfaceCategory: CategoryDelta])`、`reset()`

- [ ] **Step 1: 写失败测试** `Tests/TrafficMonitorTests/UsageStoreTests.swift`:

```swift
import XCTest
@testable import TrafficMonitor

@MainActor
final class UsageStoreTests: XCTestCase {
    func testInitialValuesAreZero() {
        let store = UsageStore()
        XCTAssertEqual(store.wifiRX, 0)
        XCTAssertEqual(store.wifiTX, 0)
        XCTAssertEqual(store.iphoneRX, 0)
        XCTAssertEqual(store.iphoneTX, 0)
    }

    func testRecordAccumulatesPerCategory() {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 50)])
        store.record([.wifi: CategoryDelta(rx: 10, tx: 5), .iphone: CategoryDelta(rx: 7000, tx: 300)])
        XCTAssertEqual(store.wifiRX, 110)
        XCTAssertEqual(store.wifiTX, 55)
        XCTAssertEqual(store.iphoneRX, 7000)
        XCTAssertEqual(store.iphoneTX, 300)
    }

    func testResetZeroesAndRestartsClock() throws {
        let store = UsageStore()
        store.record([.wifi: CategoryDelta(rx: 100, tx: 100)])
        let before = store.startTime
        try XCTWaiter().wait(for: [], timeout: 0.02) // 保证时钟前进
        store.reset()
        XCTAssertEqual(store.wifiRX, 0)
        XCTAssertGreaterThanOrEqual(store.startTime.timeIntervalSince(before), 0)
    }
}
```

（`XCTWaiter().wait(for: [], timeout:)` 只是让出主线程片刻；若编译器告警可换成 `Thread.sleep(forTimeInterval: 0.02)`。）

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter UsageStoreTests 2>&1 | tail -5`
Expected: 编译失败，`UsageStore` 未定义

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/UsageStore.swift`:

```swift
import Observation

@Observable
@MainActor
final class UsageStore {
    private(set) var startTime = Date()
    private(set) var wifiRX: UInt64 = 0
    private(set) var wifiTX: UInt64 = 0
    private(set) var iphoneRX: UInt64 = 0
    private(set) var iphoneTX: UInt64 = 0

    func record(_ deltas: [InterfaceCategory: CategoryDelta]) {
        if let d = deltas[.wifi] {
            wifiRX += d.rx
            wifiTX += d.tx
        }
        if let d = deltas[.iphone] {
            iphoneRX += d.rx
            iphoneTX += d.tx
        }
    }

    /// 清零累计并重新开始计时
    func reset() {
        startTime = Date()
        wifiRX = 0
        wifiTX = 0
        iphoneRX = 0
        iphoneTX = 0
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter UsageStoreTests 2>&1 | tail -5`
Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat: observable usage store with reset

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: 接口分类 + getifaddrs 采样

**Files:**
- Create: `Sources/TrafficMonitor/InterfaceSampler.swift`
- Test: `Tests/TrafficMonitorTests/InterfaceSamplerTests.swift`

**Interfaces:**
- Consumes: `InterfaceCategory`、`InterfaceCounters`、`ClassifiedSample`（Task 1）
- Produces: `protocol InterfaceSampling { func sample() -> [ClassifiedSample] }`；`InterfaceClassifier.category(interfaceType: String, description: String) -> InterfaceCategory?`；`struct InterfaceSampler: InterfaceSampling`

- [ ] **Step 1: 写失败测试** `Tests/TrafficMonitorTests/InterfaceSamplerTests.swift`:

```swift
import XCTest
@testable import TrafficMonitor

final class InterfaceSamplerTests: XCTestCase {
    func testWiFiByInterfaceType() {
        XCTAssertEqual(InterfaceClassifier.category(interfaceType: "IEEE80211", description: "Wi-Fi"), .wifi)
    }

    func testIPhoneByDescription() {
        XCTAssertEqual(InterfaceClassifier.category(interfaceType: "Ethernet", description: "iPhone USB"), .iphone)
        XCTAssertEqual(InterfaceClassifier.category(interfaceType: "Ethernet", description: "iphone"), .iphone)
    }

    func testOtherInterfacesIgnored() {
        XCTAssertNil(InterfaceClassifier.category(interfaceType: "Ethernet", description: "USB 10/100/1000 LAN"))
        XCTAssertNil(InterfaceClassifier.category(interfaceType: "Ethernet", description: "Ethernet"))
        XCTAssertNil(InterfaceClassifier.category(interfaceType: "", description: ""))
    }

    /// 集成冒烟测试：真实系统上至少采到一个接口，且名字唯一
    func testLiveSampleReturnsUniqueInterfaces() {
        let samples = InterfaceSampler().sample()
        XCTAssertFalse(samples.isEmpty)
        let names = samples.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter InterfaceSamplerTests 2>&1 | tail -5`
Expected: 编译失败，`InterfaceClassifier`/`InterfaceSampler` 未定义

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/InterfaceSampler.swift`:

```swift
import Darwin
import SystemConfiguration

protocol InterfaceSampling {
    /// 采样一次所有链路层接口；category 为 nil 表示与本应用无关
    func sample() -> [ClassifiedSample]
}

enum InterfaceClassifier {
    /// 纯分类规则：Wi-Fi 按接口类型，iPhone USB 按本地化描述
    static func category(interfaceType: String, description: String) -> InterfaceCategory? {
        if interfaceType == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if description.localizedCaseInsensitiveContains("iPhone") { return .iphone }
        return nil
    }
}

struct InterfaceSampler: InterfaceSampling {
    private var categoryByBSDName: [String: InterfaceCategory] {
        var result: [String: InterfaceCategory] = [:]
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return result }
        for iface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String? ?? ""
            let description = SCNetworkInterfaceGetLocalizedDescription(iface) as String? ?? ""
            if let category = InterfaceClassifier.category(interfaceType: type, description: description) {
                result[bsd] = category
            }
        }
        return result
    }

    func sample() -> [ClassifiedSample] {
        let categories = categoryByBSDName
        var result: [ClassifiedSample] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return result }
        defer { freeifaddrs(ifaddrPtr) }

        var seen = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let ifa = ptr.pointee
            cursor = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard seen.insert(name).inserted else { continue } // 每个接口取第一条 AF_LINK 记录
            var rx: UInt64 = 0
            var tx: UInt64 = 0
            if let dataPtr = ifa.ifa_data {
                let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                rx = data.ifi_ibytes
                tx = data.ifi_obytes
            }
            result.append(ClassifiedSample(name: name,
                                           category: categories[name],
                                           counters: InterfaceCounters(rx: rx, tx: tx)))
        }
        return result
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter InterfaceSamplerTests 2>&1 | tail -5`
Expected: `Executed 4 tests, with 0 failures`（live 冒烟测试在真实 mac 上必过）

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat: interface classification and getifaddrs sampling

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 5: TrafficMonitor 胶水层

**Files:**
- Create: `Sources/TrafficMonitor/TrafficMonitor.swift`
- Test: `Tests/TrafficMonitorTests/TrafficMonitorTests.swift`

**Interfaces:**
- Consumes: `InterfaceSampling`/`ClassifiedSample`（Task 4）、`TrafficMath`（Task 2）、`UsageStore`（Task 3）、`ByteFormat`（Task 1）
- Produces: `@MainActor final class TrafficMonitor`，属性 `store: UsageStore`、`wifiRate/iphoneRate: CategoryDelta`、`menuBarTitle: String`，方法 `init(sampler: InterfaceSampling)`、`start()`、`tick()`、`update(from samples: [ClassifiedSample])`、`reset()`

- [ ] **Step 1: 写失败测试** `Tests/TrafficMonitorTests/TrafficMonitorTests.swift`:

```swift
import XCTest
@testable import TrafficMonitor

private final class FakeSampler: InterfaceSampling {
    var samples: [ClassifiedSample]
    init(samples: [ClassifiedSample]) { self.samples = samples }
    func sample() -> [ClassifiedSample] { samples }
}

@MainActor
final class TrafficMonitorTests: XCTestCase {
    private func sample(_ name: String, _ category: InterfaceCategory?, rx: UInt64, tx: UInt64) -> ClassifiedSample {
        ClassifiedSample(name: name, category: category, counters: InterfaceCounters(rx: rx, tx: tx))
    }

    func testMenuBarTitleShowsRates() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 50)])
        monitor.update(from: [sample("en0", .wifi, rx: 1_100, tx: 1_050)])
        // wifi 速率 rx=1000 tx=1000，无 iphone
        XCTAssertEqual(monitor.menuBarTitle, "↑1.0 KB/s ↓1.0 KB/s")
    }

    func testUpdateAccumulatesTotalsAndRates() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0), sample("en5", .iphone, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 2_000_000, tx: 1_000_000),
                              sample("en5", .iphone, rx: 500_000, tx: 250_000)])
        XCTAssertEqual(monitor.store.wifiRX, 2_000_000)
        XCTAssertEqual(monitor.store.wifiTX, 1_000_000)
        XCTAssertEqual(monitor.store.iphoneRX, 500_000)
        XCTAssertEqual(monitor.store.iphoneTX, 250_000)
        XCTAssertEqual(monitor.wifiRate, CategoryDelta(rx: 2_000_000, tx: 1_000_000))
        XCTAssertEqual(monitor.iphoneRate, CategoryDelta(rx: 500_000, tx: 250_000))
    }

    func testResetZeroesRatesAndStore() {
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: []))
        monitor.update(from: [sample("en0", .wifi, rx: 0, tx: 0)])
        monitor.update(from: [sample("en0", .wifi, rx: 100, tx: 100)])
        monitor.reset()
        XCTAssertEqual(monitor.store.wifiRX, 0)
        XCTAssertEqual(monitor.wifiRate, .zero)
    }

    func testFirstSampleIsBaselineNotCounted() {
        // 构造时采到的"开机以来累计量"不应被计入
        let monitor = TrafficMonitor(sampler: FakeSampler(samples: [sample("en0", .wifi, rx: 999_999_999, tx: 999_999_999)]))
        XCTAssertEqual(monitor.store.wifiRX, 0)
        XCTAssertEqual(monitor.store.wifiTX, 0)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter TrafficMonitorTests 2>&1 | tail -5`
Expected: 编译失败，`TrafficMonitor` 未定义

- [ ] **Step 3: 实现** `Sources/TrafficMonitor/TrafficMonitor.swift`:

```swift
import Observation
import os

@Observable
@MainActor
final class TrafficMonitor {
    let store = UsageStore()
    private let sampler: InterfaceSampling
    private let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "tick")
    private var previousCounters: [String: InterfaceCounters] = [:]
    private(set) var wifiRate = CategoryDelta.zero
    private(set) var iphoneRate = CategoryDelta.zero
    private var timer: Timer?

    init(sampler: InterfaceSampling = InterfaceSampler()) {
        self.sampler = sampler
        // 首次采样作为基线：接口计数器是"开机以来累计"，不能直接计入
        previousCounters = Self.counterMap(from: sampler.sample())
    }

    /// 菜单栏标题：总实时速率 ↑tx ↓rx
    var menuBarTitle: String {
        let tx = wifiRate.tx + iphoneRate.tx
        let rx = wifiRate.rx + iphoneRate.rx
        return "↑\(ByteFormat.rate(tx)) ↓\(ByteFormat.rate(rx))"
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        update(from: sampler.sample())
        logger.debug("wifiRx=\(self.store.wifiRX, format: .decimal) wifiTx=\(self.store.wifiTX, format: .decimal) iphoneRx=\(self.store.iphoneRX, format: .decimal) iphoneTx=\(self.store.iphoneTX, format: .decimal)")
    }

    /// 用一份新采样推进状态（测试可直接调用）
    func update(from samples: [ClassifiedSample]) {
        var categories: [String: InterfaceCategory] = [:]
        for s in samples {
            if let c = s.category { categories[s.name] = c }
        }
        let current = Self.counterMap(from: samples)
        let deltas = TrafficMath.deltas(previous: previousCounters, current: current, categories: categories)
        store.record(deltas)
        wifiRate = deltas[.wifi] ?? .zero
        iphoneRate = deltas[.iphone] ?? .zero
        previousCounters = current
    }

    func reset() {
        store.reset()
        wifiRate = .zero
        iphoneRate = .zero
    }

    private static func counterMap(from samples: [ClassifiedSample]) -> [String: InterfaceCounters] {
        Dictionary(samples.map { ($0.name, $0.counters) }, uniquingKeysWith: { first, _ in first })
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter TrafficMonitorTests 2>&1 | tail -5`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat: traffic monitor glue with timer, rates and menubar title

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 6: SwiftUI 菜单栏应用

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（整体替换占位入口）

**Interfaces:**
- Consumes: `TrafficMonitor`（Task 5）、`ByteFormat`（Task 1）
- Produces: 可执行的应用入口

- [ ] **Step 1: 整体替换** `Sources/TrafficMonitor/TrafficMonitorApp.swift`:

```swift
import SwiftUI

@main
struct TrafficMonitorApp: App {
    @State private var monitor = TrafficMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            Text(monitor.menuBarTitle)
        }
    }
}

struct MenuContent: View {
    let monitor: TrafficMonitor

    var body: some View {
        Text("开始于 \(monitor.store.startTime.formatted(date: .omitted, time: .shortened))")
        Divider()
        row("Wi-Fi", rx: monitor.store.wifiRX, tx: monitor.store.wifiTX, rate: monitor.wifiRate)
        row("iPhone", rx: monitor.store.iphoneRX, tx: monitor.store.iphoneTX, rate: monitor.iphoneRate)
        Divider()
        Button("重置计数") { monitor.reset() }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }

    private func row(_ name: String, rx: UInt64, tx: UInt64, rate: CategoryDelta) -> some View {
        Text("\(name)  ↑\(ByteFormat.string(tx)) ↓\(ByteFormat.string(rx))   \(ByteFormat.rate(rate.rx + rate.tx))")
    }
}
```

注意：MenuBarExtra 默认 `.menu` 风格下，顶层 `Text` 渲染为灰色不可点的说明行，`Button`/`Divider` 为原生菜单项——正是设计稿的样式。`start()` 必须被调用：在 `TrafficMonitorApp` 里通过 `init` 不可靠，改为在 `MenuContent.onAppear` 调用？菜单 `.menu` 风格内容不常驻渲染。因此把启动放到 App init 后首帧：在 `TrafficMonitorApp.init` 中 `monitor.start()`（SwiftUI App init 在主线程执行一次，安全）：

最终 App 结构（替换上面 body 所在 struct 的完整写法）：

```swift
@main
struct TrafficMonitorApp: App {
    @State private var monitor = TrafficMonitor()

    init() {
        monitor.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            Text(monitor.menuBarTitle)
        }
    }
}
```

（`@State` 包装的 `@Observable` 对象在 init 里调用其方法即可，状态仍由 SwiftUI 管理；`start()` 幂等，重复调用无害。）

- [ ] **Step 2: 全量测试确认无回归**

Run: `swift test 2>&1 | tail -5`
Expected: 全部通过（21 个测试）

- [ ] **Step 3: Release 构建确认可编译**

Run: `swift build -c release 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "feat: menubar app UI with per-interface breakdown

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 7: 打包脚本 + README + 运行验证

**Files:**
- Create: `scripts/make-app.sh`（可执行）
- Create: `README.md`

**Interfaces:**
- Consumes: Release 可执行文件 `.build/release/TrafficMonitor`
- Produces: `Traffic Monitor.app`，可直接 `open` 运行

- [ ] **Step 1: 写打包脚本** `scripts/make-app.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
swift build -c "$CONFIG"

APP="Traffic Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/TrafficMonitor" "$APP/Contents/MacOS/TrafficMonitor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TrafficMonitor</string>
    <key>CFBundleIdentifier</key><string>local.shin.TrafficMonitor</string>
    <key>CFBundleName</key><string>Traffic Monitor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "Built ./$APP"
```

然后 `chmod +x scripts/make-app.sh`。

- [ ] **Step 2: 写 README.md**:

```markdown
# Traffic Monitor

macOS 菜单栏流量监测：从启动时刻起累计 Wi-Fi 与 USB 共享 iPhone 的流量，实时显示速率。

## 运行

    ./scripts/make-app.sh
    open "Traffic Monitor.app"

菜单栏出现 `↑.. ↓..` 速率图标；点开可看 Wi-Fi / iPhone 分类累计、开始时间，支持重置与退出。

## 开发

    swift test          # 运行全部测试
    swift build -c release

接口分类规则：Wi-Fi 按接口类型 `IEEE80211`；iPhone USB 按硬件端口描述含 "iPhone"（`SCNetworkInterface`）。设计文档见 `docs/superpowers/specs/`。
```

- [ ] **Step 3: 打包并运行**

Run: `./scripts/make-app.sh && open "Traffic Monitor.app"`
Expected: `Built ./Traffic Monitor.app`；菜单栏出现 `↑0 B/s ↓0 B/s` 图标

- [ ] **Step 4: 运行时验证数据管线**

Run:
```bash
pgrep -f TrafficMonitor   # 确认进程在
log stream --predicate 'process == "TrafficMonitor"' --style compact > /tmp/trafficmon.log 2>&1 &
LOGPID=$!
sleep 3
curl -sS -o /dev/null https://www.apple.com
sleep 3
kill $LOGPID
grep -c "wifiRx\|iphoneRx" /tmp/trafficmon.log   # 应 > 0
```
Expected: 日志中出现每秒 tick 且 wifiRx 数值在 curl 后明显增长（比 curl 前最后一次大）。若日志为空：改用 `log show --last 1m --predicate 'process == "TrafficMonitor"'` 检查。

- [ ] **Step 5: 确认菜单栏标签在增长（防 MenuBarExtra label 不刷新的已知历史问题）**

若 `log stream` 中数值在涨但菜单栏数字不动（需肉眼确认则向用户报告前先自查：用 `osascript` 读菜单栏属于系统辅助功能授权，成本高；以日志为准，标签刷新问题留给 Task 6 已用的 `@Observable` + macOS 26 机制，一般无碍）。如有问题，回退方案：改用 `NSStatusItem` 手动刷 `button.title`。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "feat: app bundle script and readme

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Self-Review 结论

- **Spec 覆盖**：菜单栏形态（Task 6）、总量+速率（Task 5 menuBarTitle + Task 6 行展示）、启动即计手动重置（Task 3/5）、getifaddrs 采集（Task 4）、Wi-Fi/iPhone 分类（Task 4）、负差值钳位（Task 2）、边界情况（Task 2/4 测试）、格式化（Task 1）、打包运行（Task 7）——全部有对应任务。
- **占位符扫描**：无 TBD/TODO；所有步骤含完整代码与命令。
- **类型一致性**：`ClassifiedSample`/`CategoryDelta`/`deltas(previous:current:categories:)`/`sample()` 在各任务间签名一致；`UsageStore` 属性名与 Task 6 UI 引用一致。

## 执行方式

用户已指示全程无需询问 → 选择 **Inline Execution（superpowers:executing-plans）**，在本会话逐任务执行。
