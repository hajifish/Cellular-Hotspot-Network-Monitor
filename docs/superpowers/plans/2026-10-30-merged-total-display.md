# 合并总流量展示与告警口径提示 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 主页重构为「右侧合并总流量圆环」布局（环=告警进度），菜单接口行去实时速率加合并值，告警设置入口明确合并流量口径。

**Architecture:** 纯展示层改动。新增 `RingGaugeView`（NSView 自绘，与 `RateGraphView` 同模式）；`HomePageController.buildUI()` 重排为左列（汇总条+双卡堆叠）+ 右列圆环面板；`MenuTextBuilder.interfaceRow` 删速率列加合并列；文案改动集中在 `MenuBarController`。告警算法（`TrafficAlert`）、基线/重置联动、通知逻辑一律不动。

**Tech Stack:** Swift 5.9 / SwiftPM 单 executable target / AppKit；测试为内置 SelfTest 套件（无 XCTest）。

**Spec:** `docs/superpowers/specs/2026-10-30-merged-total-display-design.md`

## Global Constraints

- UI 文案与代码注释全部中文（代码库惯例）
- 平台 macOS 14+（`Package.swift` platforms `[.macOS(.v14)]`），单一 executable target，无第三方依赖
- XCTest 不可用（CLT 工具链）：所有测试进 `Sources/TrafficMonitor/SelfTest/`，由 `TRAFFICMONITOR_SELFTEST=1` 触发
- 告警算法不动：不改 `TrafficAlert.swift`、`applyAlertThreshold`、`onReset` 联动、`MilestoneTracker`
- 主页窗口恒为 darkAqua 深色玻璃（既有设定）
- 全量验证命令（每个任务的验收步骤都用它）：
  ```bash
  swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
  ```
  预期：编译无警告错误；输出最后一行 `✔ N checks passed`（N 随用例增加而变大）；退出码 0
- 提交信息末尾加：`Co-Authored-By: Claude Code <noreply@anthropic.com>`

---

### Task 1: RingGaugeView 组件与纯函数（弧比例 + stringParts）

**Files:**
- Create: `Sources/TrafficMonitor/RingGaugeView.swift`
- Modify: `Sources/TrafficMonitor/ByteFormat.swift`（追加 `stringParts`）
- Create: `Sources/TrafficMonitor/SelfTest/RingGaugeTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/ByteFormatTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift`（注册 RingGauge 套件）

**Interfaces:**
- Consumes: `ByteFormat.string(_:)`（既有）
- Produces: `RingGaugeView`：NSView 子类，属性 `arcFraction: Double?`（nil=未设置）、`fired: Bool`、`centerValue: String`、`centerUnit: String`；静态纯函数 `RingGaugeView.arcFraction(threshold: UInt64?, fired: Bool, progressBytes: UInt64) -> Double?`
- Produces: `ByteFormat.stringParts(_ bytes: UInt64) -> (value: String, unit: String)`（Task 4 环心混排用）

- [ ] **Step 1: 写失败测试 — 弧比例纯函数**

新建 `Sources/TrafficMonitor/SelfTest/RingGaugeTests.swift`：

```swift
enum RingGaugeTests {
    static func all() {
        arcFractionComputation()
    }

    /// 未设置 → nil；阈值 0 视同未设置；已触发 → 1；其余按比例并钳位 0…1
    static func arcFractionComputation() {
        TestRun.expect(RingGaugeView.arcFraction(threshold: nil, fired: false, progressBytes: 100) == nil,
                       "unset returns nil")
        TestRun.expect(RingGaugeView.arcFraction(threshold: 0, fired: false, progressBytes: 100) == nil,
                       "zero threshold treated as unset")
        TestRun.expectEqual(RingGaugeView.arcFraction(threshold: 1_000, fired: true, progressBytes: 10),
                            Double?(1), "fired draws full arc")
        TestRun.expectEqual(RingGaugeView.arcFraction(threshold: 1_000, fired: false, progressBytes: 250),
                            Double?(0.25), "quarter progress")
        TestRun.expectEqual(RingGaugeView.arcFraction(threshold: 1_000, fired: false, progressBytes: 5_000),
                            Double?(1), "over-progress clamps to 1")
    }
}
```

- [ ] **Step 2: 写失败测试 — stringParts 拆分**

在 `Sources/TrafficMonitor/SelfTest/ByteFormatTests.swift` 的 `all()` 末尾加入 `stringPartsSplit()` 调用，并新增用例：

```swift
    static func stringPartsSplit() {
        let parts = ByteFormat.stringParts(10_400_000_000)
        TestRun.expectEqual(parts.value, "10.4", "total value part")
        TestRun.expectEqual(parts.unit, "GB", "total unit part")
        let zero = ByteFormat.stringParts(0)
        TestRun.expectEqual(zero.value, "0", "zero value part")
        TestRun.expectEqual(zero.unit, "B", "zero unit part")
    }
```

即 `all()` 变为：

```swift
    static func all() {
        bytes()
        kilobytes()
        megabytesAndGigabytes()
        rateAppendsPerSecond()
        stringPartsSplit()
    }
```

- [ ] **Step 3: 注册套件**

在 `Sources/TrafficMonitor/SelfTest/TestSupport.swift` 的 `SelfTest.run()` 中，`HomePage` 套件之后加一行：

```swift
        TestRun.suite("RingGauge") { RingGaugeTests.all() }
```

- [ ] **Step 4: 运行测试验证失败**

```bash
swift build 2>&1 | tail -5
```

预期：FAIL —— 编译错误 `cannot find 'RingGaugeView' in scope`、`value of type 'ByteFormat' has no member 'stringParts'`（内置自测模式下，缺符号即"测试失败"形态）。

- [ ] **Step 5: 实现 stringParts**

在 `Sources/TrafficMonitor/ByteFormat.swift` 的 `rateParts` 之后追加：

```swift
    /// 拆分字节文本为数值与单位（大字号混排用），如 10_400_000_000 -> ("10.4", "GB")
    static func stringParts(_ bytes: UInt64) -> (value: String, unit: String) {
        let text = string(bytes)
        guard let space = text.firstIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
```

- [ ] **Step 6: 实现 RingGaugeView**

新建 `Sources/TrafficMonitor/RingGaugeView.swift`：

```swift
import AppKit

/// 合并总流量圆环仪表：轨道环常驻，告警进度弧（进行中=橙、已触发=红），
/// 环心为合并总流量大数字。口径 = 所有模块累计上行 + 下行，与告警一致。
final class RingGaugeView: NSView {
    /// 告警弧比例（0…1）；nil = 未设置告警（只画素环）
    var arcFraction: Double? { didSet { needsDisplay = true } }
    var fired = false { didSet { needsDisplay = true } }
    var centerValue = "" { didSet { needsDisplay = true } }
    var centerUnit = "" { didSet { needsDisplay = true } }

    /// 告警弧比例（纯函数，可测）：未设置 → nil；已触发 → 1；其余按比例钳位 0…1
    static func arcFraction(threshold: UInt64?, fired: Bool,
                            progressBytes: UInt64) -> Double? {
        guard let threshold, threshold > 0 else { return nil }
        guard !fired else { return 1 }
        let ratio = Double(progressBytes) / Double(threshold)
        return min(1, max(0, ratio))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let lineWidth: CGFloat = 9
        let diameter = max(0, min(bounds.width, bounds.height) - lineWidth)
        guard diameter > 0 else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = diameter / 2

        // 轨道环常驻
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius,
                        startAngle: 0, endAngle: 360, clockwise: true)
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.10).setStroke()
        track.stroke()

        // 告警进度弧：从 12 点钟起顺时针；进行中橙色，已触发红色整环
        if let fraction = arcFraction {
            (fired ? NSColor.systemRed : NSColor.systemOrange).setStroke()
            let arc = NSBezierPath()
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * CGFloat(fraction),
                          clockwise: true)
            arc.stroke()
        }

        // 环心：合并总流量大数字（等宽）+ 单位小字
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let valueSize = (centerValue as NSString).size(withAttributes: valueAttributes)
        let unitSize = (centerUnit as NSString).size(withAttributes: unitAttributes)
        (centerValue as NSString).draw(
            at: NSPoint(x: center.x - valueSize.width / 2, y: center.y + 1),
            withAttributes: valueAttributes)
        (centerUnit as NSString).draw(
            at: NSPoint(x: center.x - unitSize.width / 2, y: center.y - unitSize.height - 5),
            withAttributes: unitAttributes)
    }
}
```

- [ ] **Step 7: 运行全量自测验证通过**

```bash
swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```

预期：`── RingGauge` 行显示 `ok`；最后一行 `✔ N checks passed`；退出码 0。

- [ ] **Step 8: 提交**

```bash
git add Sources/TrafficMonitor/RingGaugeView.swift Sources/TrafficMonitor/ByteFormat.swift \
        Sources/TrafficMonitor/SelfTest/RingGaugeTests.swift Sources/TrafficMonitor/SelfTest/ByteFormatTests.swift \
        Sources/TrafficMonitor/SelfTest/TestSupport.swift
git commit -m "feat: RingGaugeView 圆环仪表与弧比例/字节拆分纯函数

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: 菜单接口行去实时速率、加合并值

**Files:**
- Modify: `Sources/TrafficMonitor/MenuTextBuilder.swift:32-51`（`interfaceRow`）
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift:394-399`（调用点）、`:415-417`（删死代码 `row`）
- Modify: `Sources/TrafficMonitor/SelfTest/MenuTextBuilderTests.swift`

**Interfaces:**
- Consumes: `ByteFormat.string(_:)`（既有）
- Produces: `MenuTextBuilder.interfaceRow(name: String, rx: UInt64, tx: UInt64) -> NSAttributedString`（签名从 4 参变 3 参：删 `rate`）

- [ ] **Step 1: 改失败测试**

替换 `Sources/TrafficMonitor/SelfTest/MenuTextBuilderTests.swift` 中的 `interfaceRowContainsNameAndArrows()`：

```swift
    static func interfaceRowContainsNameAndArrows() {
        let row = MenuTextBuilder.interfaceRow(name: "iPhone",
                                               rx: 4_500_000_000, tx: 80_000_000)
        let plain = row.string
        TestRun.expect(plain.contains("iPhone"), "row has name")
        TestRun.expect(plain.contains("↓"), "row has download arrow")
        TestRun.expect(plain.contains("↑"), "row has upload arrow")
        TestRun.expect(plain.contains("4.5 GB"), "row has rx total")
        TestRun.expect(plain.contains("4.6 GB"), "row has merged total")
        TestRun.expect(!plain.contains("/s"), "row has no real-time rate")
    }
```

（4_500_000_000 + 80_000_000 = 4_580_000_000 → `"4.6 GB"`）

- [ ] **Step 2: 运行测试验证失败**

```bash
swift build 2>&1 | tail -5
```

预期：FAIL —— `missing argument for parameter 'rate' in call`（测试已按新签名调用，实现仍是旧 4 参签名）。

注意：此时 `TrafficMonitorApp.swift` 的调用点仍带 `rate:` 实参，与旧签名匹配、不报错；失败只来自测试文件。本步骤确认编译失败即可。

- [ ] **Step 3: 实现 interfaceRow 新签名**

替换 `Sources/TrafficMonitor/MenuTextBuilder.swift` 中的 `interfaceRow`（删除 `rate` 参数与第三列速率，新增第三列合并值 semibold）：

```swift
    /// 接口行：名称 | 累计（彩色箭头 + 等宽数字）| 合并（上行 + 下行，semibold）
    static func interfaceRow(name: String, rx: UInt64, tx: UInt64) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 96),
                              NSTextTab(textAlignment: .left, location: 196)]

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: name, attributes: attributes(size: 13, color: .labelColor)))
        text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))

        text.append(arrow("↑", uploadAccent))
        text.append(NSAttributedString(string: "\(ByteFormat.string(tx)) ", attributes: attributes(size: 13, color: .labelColor, mono: true)))
        text.append(arrow("↓", downloadAccent))
        text.append(NSAttributedString(string: ByteFormat.string(rx), attributes: attributes(size: 13, color: .labelColor, mono: true)))

        text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))
        text.append(NSAttributedString(string: ByteFormat.string(rx + tx),
                                       attributes: attributes(size: 13, color: .labelColor, weight: .semibold, mono: true)))
        return text
    }
```

- [ ] **Step 4: 更新调用点并删死代码**

`Sources/TrafficMonitor/TrafficMonitorApp.swift` 的 `refresh()` 中，`wifiItem` / `iphoneItem` 两处调用删去 `rate:` 实参：

```swift
        wifiItem.attributedTitle = MenuTextBuilder.interfaceRow(
            name: InterfaceCategory.wifi.displayName,
            rx: store.wifi.rx, tx: store.wifi.tx)
        iphoneItem.attributedTitle = MenuTextBuilder.interfaceRow(
            name: InterfaceCategory.iphone.displayName,
            rx: store.iphone.rx, tx: store.iphone.tx)
```

同文件末尾删除已无人调用的私有函数：

```swift
    private static func row(_ name: String, rx: UInt64, tx: UInt64, rate: CategoryDelta) -> String {
        "\(name)  ↑\(ByteFormat.string(tx)) ↓\(ByteFormat.string(rx))   \(ByteFormat.rate(rate.rx + rate.tx))"
    }
```

- [ ] **Step 5: 运行全量自测验证通过**

```bash
swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```

预期：`── MenuTextBuilder` 行 `ok`；`✔ N checks passed`；退出码 0。

- [ ] **Step 6: 提交**

```bash
git add Sources/TrafficMonitor/MenuTextBuilder.swift Sources/TrafficMonitor/TrafficMonitorApp.swift \
        Sources/TrafficMonitor/SelfTest/MenuTextBuilderTests.swift
git commit -m "feat: 菜单接口行去实时速率、新增上行+下行合并列

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: 告警口径提示文案

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift:186`（子菜单 caption）、`:248`（自定义弹窗 informativeText）

**Interfaces:**
- Consumes: 无（纯字符串改动）
- Produces: 无（展示文案）

- [ ] **Step 1: 改子菜单说明**

`Sources/TrafficMonitor/TrafficMonitorApp.swift` 的 `buildAlertMenu()` 中：

```swift
        let caption = NSMenuItem(title: "按所有模块累计上行 + 下行的合并流量提醒一次",
                                 action: nil, keyEquivalent: "")
```

- [ ] **Step 2: 改自定义阈值弹窗文案**

`showCustomAlertThreshold()` 中：

```swift
        dialog.informativeText = "输入达到时提醒的合并流量（所有模块累计上行 + 下行）。示例：5 GB、500 MB。\n设置后提醒进度将重新计算，已触发的提醒状态会被清除。"
```

- [ ] **Step 3: 构建验证**

```bash
swift build 2>&1 | tail -3
```

预期：编译通过（纯文案改动，无新用例；既有用例不受影响）。

- [ ] **Step 4: 提交**

```bash
git add Sources/TrafficMonitor/TrafficMonitorApp.swift
git commit -m "feat: 告警设置入口明确标注合并流量口径

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: 主页方案 B 布局重排（左列堆叠 + 右侧圆环）

**Files:**
- Modify: `Sources/TrafficMonitor/HomePageController.swift`（窗口尺寸、buildUI、refresh）
- Modify: `Sources/TrafficMonitor/SelfTest/HomePageTests.swift:19`（unset 文案）

**Interfaces:**
- Consumes: Task 1 的 `RingGaugeView`（属性 `arcFraction/fired/centerValue/centerUnit`）、`RingGaugeView.arcFraction(threshold:fired:progressBytes:)`、`ByteFormat.stringParts(_:)`
- Produces: `HomePageController.alertStrip` 的 unset 文案变为 `"告警未设置"`（菜单 unset 分支 detail 仍传 `""`，不受影响）

- [ ] **Step 1: 改失败测试（unset 文案）**

`Sources/TrafficMonitor/SelfTest/HomePageTests.swift` 的 `alertStripFormatting()` 第一组断言改为：

```swift
        let unset = HomePageController.alertStrip(threshold: nil, fired: false, progressBytes: 100)
        TestRun.expectEqual(unset.text, "告警未设置", "unset text")
        TestRun.expect(unset.state == .unset, "unset state")
```

- [ ] **Step 2: 运行测试验证失败**

```bash
swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor; echo "exit=$?"
```

预期：编译通过但 `── HomePage` 显示 `FAILED`（`unset text: got 未设置, want 告警未设置`），退出码非 0。

- [ ] **Step 3: 改 alertStrip 的 unset 文案**

`Sources/TrafficMonitor/HomePageController.swift` 的 `alertStrip` 中：

```swift
        guard let threshold, threshold > 0 else { return ("告警未设置", .unset) }
```

- [ ] **Step 4: 重排 buildUI（窗口 720×470，左列堆叠，右列圆环）**

在 `HomePageController` 中做以下改动：

4a. 属性区：删除 `private var alertValueLabel: NSTextField!`，在 `private let graphView = RateGraphView()` 之后加：

```swift
    private let ringView = RingGaugeView()
```

并新增一个状态 label 属性（与 `legendLabel` 等声明放一起）：

```swift
    private var ringStatusLabel: NSTextField!
```

4b. `init` 中窗口尺寸 `428` 改 `470`：

```swift
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 470),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
```

4c. `buildUI()` 整体替换为（视觉层高度同步 470；汇总条只留三项；卡片上下堆叠每卡两行；右侧圆环面板；坐标基于 720×470 自下而上排布）：

```swift
    private func buildUI() {
        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 720, height: 470))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        window.contentView = visual
        let content = visual

        // 顶部右侧：状态栏显示开关（累计流量在前、实时速率在后；都关 = 状态栏只显示图标）
        totalsToggle = sphereToggle(action: #selector(toggleTotals))
        totalsToggle.frame = NSRect(x: 538, y: 426, width: 18, height: 18)
        content.addSubview(totalsToggle)
        totalsLabel = makeLabel(size: 11, color: .labelColor, weight: .medium)
        totalsLabel.stringValue = "累计流量"
        totalsLabel.frame = NSRect(x: 560, y: 428, width: 56, height: 16)
        content.addSubview(totalsLabel)
        ratesToggle = sphereToggle(action: #selector(toggleRates))
        ratesToggle.frame = NSRect(x: 628, y: 426, width: 18, height: 18)
        content.addSubview(ratesToggle)
        ratesLabel = makeLabel(size: 11, color: .labelColor, weight: .medium)
        ratesLabel.stringValue = "实时速率"
        ratesLabel.frame = NSRect(x: 650, y: 428, width: 56, height: 16)
        content.addSubview(ratesLabel)
        refreshToggles()
        updateBaseViews.append(contentsOf: [totalsToggle, totalsLabel, ratesToggle, ratesLabel])

        // 左列汇总条：会话、总上传、总下载（流量告警移至右侧圆环面板）
        let strip = roundedCard(frame: NSRect(x: 24, y: 368, width: 456, height: 46))
        content.addSubview(strip)
        updateBaseViews.append(strip)
        let summarySpecs: [(String, CGFloat)] = [
            ("会话", 18), ("总上传", 150), ("总下载", 280),
        ]
        for (caption, x) in summarySpecs {
            let captionLabel = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
            captionLabel.stringValue = caption
            captionLabel.frame = NSRect(x: x, y: 26, width: 120, height: 12)
            strip.contentView?.addSubview(captionLabel)
            let value = makeLabel(size: 12, color: .labelColor, weight: .semibold)
            value.frame = NSRect(x: x, y: 6, width: 120, height: 18)
            value.lineBreakMode = .byClipping
            strip.contentView?.addSubview(value)
            summaryValues.append(value)
        }

        // 左列接口卡片：上下堆叠；每卡两行——上行「标题 + 开始信息 + 重置」，下行「速率 + 累计」
        let cardSpecs: [(InterfaceCategory, CGFloat)] = [
            (.wifi, 274),
            (.iphone, 180),
        ]
        for (category, y) in cardSpecs {
            let card = roundedCard(frame: NSRect(x: 24, y: y, width: 456, height: 86))
            content.addSubview(card)
            updateBaseViews.append(card)

            let title = makeLabel(size: 13, color: .labelColor, weight: .semibold)
            title.frame = NSRect(x: 18, y: 56, width: 240, height: 18)
            let meta = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
            meta.frame = NSRect(x: 258, y: 58, width: 160, height: 16)
            meta.alignment = .right
            if let resetIcon = NSImage(systemSymbolName: "arrow.counterclockwise",
                                       accessibilityDescription: "重置计量") {
                let reset = NSButton(image: resetIcon, target: self, action: #selector(resetCategory(_:)))
                reset.isBordered = false
                reset.contentTintColor = .secondaryLabelColor
                reset.setFrameOrigin(NSPoint(x: 456 - 34, y: 54))
                reset.toolTip = "重置计量"
                reset.identifier = NSUserInterfaceItemIdentifier(category == .wifi ? "wifi" : "iphone")
                card.contentView?.addSubview(reset)
            }
            let rate = makeLabel(size: 12, color: .labelColor, weight: .regular)
            rate.frame = NSRect(x: 18, y: 12, width: 280, height: 40)
            let total = makeLabel(size: 12, color: .secondaryLabelColor, weight: .regular)
            total.frame = NSRect(x: 298, y: 26, width: 140, height: 20)
            total.alignment = .right
            total.lineBreakMode = .byClipping
            for label in [title, rate, total, meta] {
                card.contentView?.addSubview(label)
            }
            cards[category] = (rate, total, title, meta)
        }

        // 右列：合并总流量圆环面板（环 = 告警进度，环心 = 全局合并总量，与告警同口径）
        let ringPanel = roundedCard(frame: NSRect(x: 492, y: 180, width: 204, height: 234))
        content.addSubview(ringPanel)
        updateBaseViews.append(ringPanel)
        ringView.frame = NSRect(x: 37, y: 62, width: 130, height: 130)
        ringPanel.contentView?.addSubview(ringView)
        let ringCaption = makeLabel(size: 9, color: .tertiaryLabelColor, weight: .medium)
        ringCaption.stringValue = "合并总流量"
        ringCaption.frame = NSRect(x: 0, y: 44, width: 204, height: 14)
        ringCaption.alignment = .center
        ringPanel.contentView?.addSubview(ringCaption)
        ringStatusLabel = makeLabel(size: 12, color: .white, weight: .semibold)
        ringStatusLabel.frame = NSRect(x: 10, y: 16, width: 184, height: 18)
        ringStatusLabel.alignment = .center
        ringStatusLabel.lineBreakMode = .byClipping
        ringPanel.contentView?.addSubview(ringStatusLabel)

        let sectionLabel = makeLabel(size: 11, color: .secondaryLabelColor, weight: .medium)
        sectionLabel.stringValue = "实时速率 · 近 120 秒"
        sectionLabel.frame = NSRect(x: 24, y: 154, width: 672, height: 16)
        content.addSubview(sectionLabel)
        updateBaseViews.append(sectionLabel)

        graphView.frame = NSRect(x: 24, y: 40, width: 672, height: 106)
        content.addSubview(graphView)
        updateBaseViews.append(graphView)

        legendLabel = makeLabel(size: 11, color: .secondaryLabelColor, weight: .regular)
        legendLabel.frame = NSRect(x: 24, y: 16, width: 672, height: 18)
        content.addSubview(legendLabel)
        updateBaseViews.append(legendLabel)
        updateLegend()

        // 图例行右端的当前版本号小字（无更新时的唯一展示）
        updateVersionLabel = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
        updateVersionLabel.frame = NSRect(x: 520, y: 18, width: 176, height: 14)
        updateVersionLabel.alignment = .right
        updateVersionLabel.stringValue = "v\(AppVersion.current)"
        content.addSubview(updateVersionLabel)

        // 软件更新卡片：仅在有更新进行时展开（默认隐藏）
        let updateCard = roundedCard(frame: NSRect(x: 24, y: 8, width: 672, height: 76))
        content.addSubview(updateCard)
        updateCardBox = updateCard
        updateCardBox.isHidden = true
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
    }
```

- [ ] **Step 5: 改 refresh()（汇总条三项 + 圆环刷新）**

`refresh()` 中把「会话/告警汇总条」**整段**替换（起点 = `// 会话/告警汇总条` 注释行，终点 = alertValueLabel 的 `switch strip.state` 收尾大括号），换成下面代码块——它包含重写的会话汇总行与新的圆环刷新，不要保留原段中任何一行以免重复声明：

```swift
        // 会话/告警汇总
        let sessionStart = store.sessionStart
        let totalRX = store.wifi.rx + store.iphone.rx
        let totalTX = store.wifi.tx + store.iphone.tx
        let total = monitor.totalRate
        let seconds = max(0, Int(Date().timeIntervalSince(sessionStart)))
        summaryValues[0].stringValue = "\(sessionStart.formatted(date: .omitted, time: .shortened)) · \(Self.durationText(seconds))"
        summaryValues[1].stringValue = "↑ \(ByteFormat.string(totalTX))"
        summaryValues[2].stringValue = "↓ \(ByteFormat.string(totalRX))"

        // 合并总流量圆环：环 = 告警进度，环心 = 全局合并总量（与告警同口径）
        let alertState = alertStateProvider?()
        let fired = alertState?.fired ?? false
        let progressBytes = alertState?.progressBytes ?? 0
        let mergedParts = ByteFormat.stringParts(totalRX + totalTX)
        ringView.centerValue = mergedParts.value
        ringView.centerUnit = mergedParts.unit
        ringView.arcFraction = RingGaugeView.arcFraction(threshold: alertState?.threshold,
                                                         fired: fired,
                                                         progressBytes: progressBytes)
        ringView.fired = fired
        let strip = Self.alertStrip(threshold: alertState?.threshold, fired: fired,
                                    progressBytes: progressBytes)
        ringStatusLabel.stringValue = strip.text
        switch strip.state {
        case .unset: ringStatusLabel.textColor = .white
        case .armed: ringStatusLabel.textColor = .systemOrange
        case .fired: ringStatusLabel.textColor = .systemRed
        }
```

（`totalRX/totalTX/total/seconds` 原有声明保留即可，只需删除 alertValueLabel 相关行；graph 刷新段不变。）

- [ ] **Step 6: 运行全量自测验证通过**

```bash
swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```

预期：`── HomePage` 行 `ok`；`✔ N checks passed`；退出码 0。

- [ ] **Step 7: 提交**

```bash
git add Sources/TrafficMonitor/HomePageController.swift Sources/TrafficMonitor/SelfTest/HomePageTests.swift
git commit -m "feat: 主页重构为右侧合并总流量圆环布局（环=告警进度）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 5: 文档更新 + 运行验证

**Files:**
- Modify: `README.md:44-50`（流量告警、主页窗口两条 bullet）、`README.md:90`（自测项数）
- Modify: `README.en.md:50-60`（对应两条 bullet）、`README.en.md:103`（自测项数）
- Modify: `CHANGELOG.md:7`（Unreleased 段）

**Interfaces:**
- Consumes: 前四个任务完成后的自测输出 `✔ N checks passed`（N 即要写入 README 的数字）
- Produces: 无（文档）

- [ ] **Step 1: 更新 README.md 流量告警 bullet**

`README.md` 中「**流量告警**」bullet 整段替换为（口径前置、"告警条"改"告警环"）：

```markdown
- **流量告警** —— 以**所有模块累计上行 + 下行的合并流量**为口径，阈值可选
  关闭 / 1 / 2 / 5 / 10 / 20 GB / 自定义（如 `5 GB`、`500 MB`），按套餐预算呈现：
  设置后菜单与主页显示余量「剩 X · 已用 Y%」。达到阈值时播放柔和钟声 +
  系统通知横幅（未授权通知时回退为应用内弹窗），告警环变红。
  每个阈值只提醒一次，重置或换档后重新武装
```

- [ ] **Step 2: 更新 README.md 主页窗口 bullet**

```markdown
- **主页窗口（⌘0）** —— 左列接口卡片（接口名、实时速率、累计收发、重置按钮），
  右侧**合并总流量圆环**（环 = 告警进度：素环未设置 / 橙弧进行中 / 红环已触发），
  近 120 秒滚动速率折线图（上传/下载双线，自适应浅色/深色模式）
```

- [ ] **Step 3: 更新 README.en.md 对应两条 bullet**

「**Traffic alerts**」bullet：

```markdown
- **Traffic alerts** — based on the **merged total of all modules'
  cumulative upload + download**; thresholds off / 1 / 2 / 5 / 10 / 20 GB or
  custom values (`5 GB`, `500 MB`), presented as a plan budget: once armed,
  the menu and home window show the remainder ("剩 X · 已用 Y%" = X left · Y%
  used). On crossing: a soft chime plus a system notification (in-app
  dialog if notifications are not authorized) and the ring turns red.
  Fires once per threshold and re-arms on reset or change
```

「**Home window (⌘0)**」bullet：

```markdown
- **Home window (⌘0)** — interface cards on the left (name, live rates,
  totals, reset) and a **merged-total ring gauge** on the right (ring =
  alert progress: plain when unset / orange arc while armed / red when
  fired), plus a rolling 120-second upload/download rate graph that adapts
  to light and dark mode
```

- [ ] **Step 4: 更新 CHANGELOG Unreleased**

`CHANGELOG.md` 的 `## [Unreleased]` 段填入：

```markdown
## [Unreleased]

### 变更 (Changed)

- 主页重构为「右侧圆环仪表」布局：合并总流量（所有模块累计上行 + 下行，与
  告警同口径）以环心大数字突出展示，环即告警进度——未设置素环、进行中橙弧、
  已触发红环；汇总条只留会话/总上传/总下载，接口卡片改为左列上下堆叠
- 状态栏菜单的 Wi-Fi / iPhone 行去掉实时速率，改为「累计上行、下行、合并」
  三项；告警子菜单与自定义阈值弹窗明确标注合并流量口径
```

- [ ] **Step 5: 运行全量自测并回填项数**

```bash
swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```

记下输出 `✔ N checks passed` 中的 N，把 `README.md:90` 的「当前 204 项」改为「当前 N 项」，`README.en.md:103` 的 "currently 204 checks" 改为 "currently N checks"（两处都用刚才实际的 N）。

- [ ] **Step 6: 运行应用目测三处**

```bash
TRAFFICMONITOR_SHOWHOME=1 TRAFFICMONITOR_ALERT_MB=1 .build/debug/TrafficMonitor &
sleep 3
```

请用户目测确认：① 主页圆环显示橙弧 + 环心合并总流量大数字 + 「剩 … · 已用 …%」橙字（1MB 阈值下大概率直接橙弧甚至触发红环，属预期）；② 点状态栏图标，Wi-Fi / iPhone 行三列（↑累计 ↓累计 合并值）且无速率；③ 「流量告警」子菜单顶部说明为「按所有模块累计上行 + 下行的合并流量提醒一次」。确认后结束进程：

```bash
pkill -f ".build/debug/TrafficMonitor"
```

再跑一次不带 `TRAFFICMONITOR_ALERT_MB` 的启动（`TRAFFICMONITOR_SHOWHOME=1`）确认未设置态素环 + 「告警未设置」白字。

- [ ] **Step 7: 提交**

```bash
git add README.md README.en.md CHANGELOG.md
git commit -m "docs: 合并总流量圆环与告警口径的 README/CHANGELOG 更新

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

- [ ] **Step 8: 手动跟进项（告知用户，非本计划任务）**

`docs/assets/screenshot-home.png` 截图已过时（主页布局变了），无法自动化重截——完成后提醒用户自行更新。

---

### Task 6: 通知正文附触发时刻 — 已取消（2026-10-30）

设计曾获用户确认并写入本计划，随后用户复核指出 macOS 通知中心自带每条通知的到达时刻显示，正文再标注一次属冗余——需求取消。实现中途叫停，半成品已清理，无代码提交。
