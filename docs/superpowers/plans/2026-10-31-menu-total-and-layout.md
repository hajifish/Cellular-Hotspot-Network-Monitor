# 展示布局修正实现计划（菜单合计行 + 主页越界 + 速率图标签固定）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 下拉菜单补「合计」行并彻底消除模块行折行；主页模块卡片累计值改两行堆叠不再越界；速率图当前速率标注固定在右上/右下角落。

**Architecture:** tab 位由「写死 96/196」改为每次刷新按三行文本实测宽度计算共享 `ColumnStops`（列对齐 + 永不折行，面板自然加宽）；主页累计由单行 140pt 标签改为「累计」说明字 + 右侧 ↑/↓ 两行等宽数值；速率图删掉端点跟随标注，改常量坐标角落绘制并着系列色。

**Tech Stack:** Swift + AppKit（macOS CLT，无 Xcode）；测试为内置自测 harness（`TestRun`，无 XCTest）。

**Spec:** `docs/superpowers/specs/2026-10-31-menu-total-and-layout-design.md`

## Global Constraints

- 分支：`feature/menu-total-and-layout`（已建，自 develop）。所有提交在此分支。
- 注释与文档中文为主；代码注释风格与现有文件一致（简体中文、说明「为什么」）。
- 无 XCTest：测试写进 `Sources/TrafficMonitor/SelfTest/`，由 `SelfTest.run()` 注册（`TestSupport.swift`），运行方式 `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`，期望末行 `✔ N checks passed` 且退出码 0。
- 每个 Task 收尾必须 `swift build` 成功、自测全绿，然后提交。
- 提交信息：conventional subject（中文正文），末尾加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。

---

### Task 1: 菜单合计行 + 动态 tab 位

**Files:**
- Modify: `Sources/TrafficMonitor/MenuTextBuilder.swift`（替换 `interfaceRow`，新增布局类型与测量）
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（新增 `totalItem`，`install()` 菜单顺序、`refresh()` 三行共用 stops）
- Test: `Sources/TrafficMonitor/SelfTest/MenuTextBuilderTests.swift`

**Interfaces:**
- Produces:
  - `enum RowLayout { static let leadingIndent: CGFloat; static let columnGap: CGFloat }`
  - `struct ColumnStops: Equatable { let first: CGFloat; let total: CGFloat }`
  - `MenuTextBuilder.InterfaceRowSpec { let name: String; let rx: UInt64; let tx: UInt64 }`
  - `MenuTextBuilder.columnStops(forRows: [InterfaceRowSpec]) -> ColumnStops`
  - `MenuTextBuilder.measuredNameWidth(_ name: String) -> CGFloat`
  - `MenuTextBuilder.measuredMidWidth(tx: String, rx: String) -> CGFloat`
  - `MenuTextBuilder.interfaceRow(name:rx:tx:stops:emphasized:) -> NSAttributedString`（`emphasized` 默认 `false`）

- [ ] **Step 1: 写失败测试**

`MenuTextBuilderTests.swift` 全量替换为（保留既有 4 项断言的用例改用新签名）：

```swift
import AppKit

enum MenuTextBuilderTests {
    static func all() {
        interfaceRowContainsNameAndArrows()
        totalRowSumsModulesAndStaysSingleLine()
        stopsKeepColumnsApartAtScale()
        alertHeaderReflectsState()
    }

    static func interfaceRowContainsNameAndArrows() {
        let spec = MenuTextBuilder.InterfaceRowSpec(name: "iPhone",
                                                    rx: 4_500_000_000, tx: 80_000_000)
        let stops = MenuTextBuilder.columnStops(forRows: [spec])
        let row = MenuTextBuilder.interfaceRow(name: spec.name, rx: spec.rx, tx: spec.tx, stops: stops)
        let plain = row.string
        TestRun.expect(plain.contains("iPhone"), "row has name")
        TestRun.expect(plain.contains("↓"), "row has download arrow")
        TestRun.expect(plain.contains("↑"), "row has upload arrow")
        TestRun.expect(plain.contains("4.5 GB"), "row has rx total")
        TestRun.expect(plain.contains("4.6 GB"), "row has merged total")
        TestRun.expect(!plain.contains("/s"), "row has no real-time rate")
    }

    static func totalRowSumsModulesAndStaysSingleLine() {
        let wifi = MenuTextBuilder.InterfaceRowSpec(name: "Wi-Fi", rx: 3_900_000, tx: 1_200_000)
        let iphone = MenuTextBuilder.InterfaceRowSpec(name: "iPhone", rx: 5_200_000, tx: 28_600_000)
        let total = MenuTextBuilder.InterfaceRowSpec(name: "合计",
                                                     rx: wifi.rx + iphone.rx, tx: wifi.tx + iphone.tx)
        let stops = MenuTextBuilder.columnStops(forRows: [wifi, iphone, total])
        let row = MenuTextBuilder.interfaceRow(name: total.name, rx: total.rx, tx: total.tx,
                                               stops: stops, emphasized: true)
        TestRun.expect(row.string.contains("合计"), "total row labeled 合计")
        TestRun.expect(row.string.contains("38.9 MB"), "total row shows merged sum")
        TestRun.expect(!row.string.contains("\n"), "total row stays on one line")
    }

    static func stopsKeepColumnsApartAtScale() {
        // 999.9 GB 级大数：tab 位仍须把三列隔开，行不折
        let rows = [
            MenuTextBuilder.InterfaceRowSpec(name: "iPhone", rx: 999_900_000_000, tx: 888_800_000_000),
            MenuTextBuilder.InterfaceRowSpec(name: "Wi-Fi", rx: 777_700_000_000, tx: 666_600_000_000),
            MenuTextBuilder.InterfaceRowSpec(name: "合计", rx: 1_777_600_000_000, tx: 1_555_400_000_000),
        ]
        let stops = MenuTextBuilder.columnStops(forRows: rows)
        TestRun.expect(stops.first < stops.total, "stops ordered")
        for row in rows {
            let nameWidth = MenuTextBuilder.measuredNameWidth(row.name)
            let midWidth = MenuTextBuilder.measuredMidWidth(tx: ByteFormat.string(row.tx),
                                                            rx: ByteFormat.string(row.rx))
            TestRun.expect(RowLayout.leadingIndent + nameWidth < stops.first,
                           "\(row.name) name fits before first stop")
            TestRun.expect(stops.first + midWidth < stops.total,
                           "\(row.name) values fit before total stop")
        }
        let row = MenuTextBuilder.interfaceRow(name: rows[2].name, rx: rows[2].rx, tx: rows[2].tx,
                                               stops: stops)
        TestRun.expect(!row.string.contains("\n"), "large values stay single line")
    }

    static func alertHeaderReflectsState() {
        TestRun.expect(MenuTextBuilder.alertHeader(armed: false, fired: false) == nil, "off has no marker")
        let armed = MenuTextBuilder.alertHeader(armed: true, fired: false)
        TestRun.expect(armed?.string.contains("流量告警") == true, "armed has label")
        TestRun.expect(armed?.string.contains("●") == true, "armed has dot")
        let armedWithDetail = MenuTextBuilder.alertHeader(armed: true, fired: false, detail: "剩 2.0GB")
        TestRun.expect(armedWithDetail?.string.contains("剩 2.0GB") == true, "armed shows detail")
        let fired = MenuTextBuilder.alertHeader(armed: true, fired: true, detail: "已触发")
        TestRun.expect(fired?.string.contains("已触发") == true, "fired shows detail")
        TestRun.expect(fired?.string.contains("●") == true, "fired has dot")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
swift build 2>&1 | head -20
```
预期：编译失败（`InterfaceRowSpec` / `columnStops` / `stops:` 参数不存在）。

- [ ] **Step 3: 实现 MenuTextBuilder**

替换 `interfaceRow`（原 33-51 行），并在 `enum MenuTextBuilder` 内新增；文件顶部 `MenuTextBuilder` 定义之前加两个类型：

```swift
/// 列布局常量：前导缩进与列间距（tab 位按内容实测计算，面板随内容自然加宽）
enum RowLayout {
    static let leadingIndent: CGFloat = 4
    static let columnGap: CGFloat = 20
}

/// 一组行共享的两个 tab 位：first = 累计列（↑tx ↓rx）起点，total = 合并列起点
struct ColumnStops: Equatable {
    let first: CGFloat
    let total: CGFloat
}
```

`enum MenuTextBuilder` 内新增（放在 `interfaceRow` 前）：

```swift
/// 行数据：名称 + 各向累计（tab 位测量与行排版共用）
struct InterfaceRowSpec {
    let name: String
    let rx: UInt64
    let tx: UInt64
}

/// 按各行文本实测宽度（与渲染同字体）计算共享 tab 位，保证列对齐且永不折行。
/// 名称与数值均按最重字重（semibold，合计行）测量，普通行必有余量。
static func columnStops(forRows rows: [InterfaceRowSpec]) -> ColumnStops {
    let nameWidth = rows.map { measuredNameWidth($0.name) }.max() ?? 0
    let first = RowLayout.leadingIndent + ceil(nameWidth) + RowLayout.columnGap
    let midWidth = rows.map {
        measuredMidWidth(tx: ByteFormat.string($0.tx), rx: ByteFormat.string($0.rx))
    }.max() ?? 0
    return ColumnStops(first: first, total: first + ceil(midWidth) + RowLayout.columnGap)
}

/// 名称实测宽度（供布局不变式测试复用）
static func measuredNameWidth(_ name: String) -> CGFloat {
    (name as NSString).size(withAttributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    ]).width
}

/// 「↑tx ↓rx」段实测宽度（供布局不变式测试复用）
static func measuredMidWidth(tx: String, rx: String) -> CGFloat {
    midSegment(tx: tx, rx: rx, valueWeight: .semibold).size().width
}
```

`interfaceRow` 整体替换为：

```swift
/// 接口行：名称 | 累计（彩色箭头 + 等宽数字）| 合并（上行 + 下行，semibold）。
/// tab 位由 columnStops 按全组行实测得出，列对齐且不折行；emphasized（合计行）整行加重
static func interfaceRow(name: String, rx: UInt64, tx: UInt64,
                         stops: ColumnStops, emphasized: Bool = false) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    // 单行行：firstLineHeadIndent 才作用于首行（headIndent 只管续行）
    paragraph.firstLineHeadIndent = RowLayout.leadingIndent
    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: stops.first),
                          NSTextTab(textAlignment: .left, location: stops.total)]
    let weight: NSFont.Weight = emphasized ? .semibold : .regular

    let text = NSMutableAttributedString()
    text.append(NSAttributedString(string: name, attributes:
        attributes(size: 13, color: .labelColor, weight: emphasized ? .semibold : .regular)))
    text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))
    text.append(midSegment(tx: ByteFormat.string(tx), rx: ByteFormat.string(rx), valueWeight: weight))
    text.append(NSAttributedString(string: "\t", attributes: [.paragraphStyle: paragraph]))
    text.append(NSAttributedString(string: ByteFormat.string(rx + tx),
                                   attributes: attributes(size: 13, color: .labelColor, weight: .semibold, mono: true)))
    return text
}

/// 中段「↑tx ↓rx」：排版与测量共用同一构建，宽度口径一致
private static func midSegment(tx: String, rx: String, valueWeight: NSFont.Weight) -> NSAttributedString {
    let text = NSMutableAttributedString()
    text.append(arrow("↑", uploadAccent))
    text.append(NSAttributedString(string: "\(tx) ", attributes:
        attributes(size: 13, color: .labelColor, weight: valueWeight, mono: true)))
    text.append(arrow("↓", downloadAccent))
    text.append(NSAttributedString(string: rx, attributes:
        attributes(size: 13, color: .labelColor, weight: valueWeight, mono: true)))
    return text
}
```

- [ ] **Step 4: 接入 TrafficMonitorApp**

属性区（`iphoneItem` 声明后）加：

```swift
private var totalItem: NSMenuItem!
```

`install()` 中 `iphoneItem = ...` 之后加创建，菜单装配改为：

```swift
totalItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

menu.addItem(startTimeItem)
menu.addItem(.separator())
menu.addItem(wifiItem)
menu.addItem(iphoneItem)
menu.addItem(.separator())
menu.addItem(totalItem)
menu.addItem(.separator())
menu.addItem(openHome)
```

`refresh()` 中替换三行 `attributedTitle` 赋值：

```swift
let specs = [
    MenuTextBuilder.InterfaceRowSpec(name: InterfaceCategory.wifi.displayName,
                                     rx: store.wifi.rx, tx: store.wifi.tx),
    MenuTextBuilder.InterfaceRowSpec(name: InterfaceCategory.iphone.displayName,
                                     rx: store.iphone.rx, tx: store.iphone.tx),
    MenuTextBuilder.InterfaceRowSpec(name: "合计",
                                     rx: store.wifi.rx + store.iphone.rx,
                                     tx: store.wifi.tx + store.iphone.tx),
]
let stops = MenuTextBuilder.columnStops(forRows: specs)
wifiItem.attributedTitle = MenuTextBuilder.interfaceRow(name: specs[0].name, rx: specs[0].rx,
                                                        tx: specs[0].tx, stops: stops)
iphoneItem.attributedTitle = MenuTextBuilder.interfaceRow(name: specs[1].name, rx: specs[1].rx,
                                                          tx: specs[1].tx, stops: stops)
totalItem.attributedTitle = MenuTextBuilder.interfaceRow(name: specs[2].name, rx: specs[2].rx,
                                                         tx: specs[2].tx, stops: stops, emphasized: true)
```

- [ ] **Step 5: 构建并跑自测**

```bash
swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```
预期：全部 suite `ok`，末行 `✔ 226 checks passed`（基线 215 + 新 11）。

- [ ] **Step 6: 提交**

```bash
git add Sources/TrafficMonitor/MenuTextBuilder.swift Sources/TrafficMonitor/TrafficMonitorApp.swift Sources/TrafficMonitor/SelfTest/MenuTextBuilderTests.swift
git commit -m "feat: 菜单合计行与动态 tab 位布局

Wi-Fi / iPhone / 合计三行共享按实测文本宽度计算的 tab 位，
数值任意大不折行，面板随内容加宽；合计行 semibold 并带分隔线

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: 主页模块卡片累计两行堆叠

**Files:**
- Modify: `Sources/TrafficMonitor/HomePageController.swift`（`buildUI()` 卡片累计标签区 161-166 行附近；`refresh()` 496 行；新增纯函数）
- Test: `Sources/TrafficMonitor/SelfTest/HomePageTests.swift`

**Interfaces:**
- Produces: `HomePageController.totalLines(tx: UInt64, rx: UInt64) -> (up: String, down: String)`（`nonisolated static`，纯函数可测）

- [ ] **Step 1: 写失败测试**

`HomePageTests.swift` 的 `all()` 增加 `totalLinesFormat()`，并新增：

```swift
static func totalLinesFormat() {
    let lines = HomePageController.totalLines(tx: 123_400_000, rx: 567_800_000)
    TestRun.expectEqual(lines.up, "↑ 123.4 MB", "total up line")
    TestRun.expectEqual(lines.down, "↓ 567.8 MB", "total down line")
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
swift build 2>&1 | head -10
```
预期：编译失败（`totalLines` 不存在）。

- [ ] **Step 3: 实现**

`HomePageController` 内（`durationText` 旁）加纯函数：

```swift
/// 模块卡片累计两行文本（纯函数，可测）：↑上行 / ↓下行，右列堆叠展示
nonisolated static func totalLines(tx: UInt64, rx: UInt64) -> (up: String, down: String) {
    ("↑ \(ByteFormat.string(tx))", "↓ \(ByteFormat.string(rx))")
}
```

`buildUI()` 卡片循环内，替换原 `total` 标签创建（161-166 行）：

```swift
let rate = makeLabel(size: 12, color: .labelColor, weight: .regular)
rate.frame = NSRect(x: 18, y: 12, width: 280, height: 40)
// 累计两行：说明字 + 右侧 ↑/↓ 两行等宽数值（三位数以上量级也不越界）
let totalCaption = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
totalCaption.stringValue = "累计"
totalCaption.frame = NSRect(x: 334, y: 27, width: 26, height: 14)
let total = makeLabel(size: 11, color: .secondaryLabelColor, weight: .regular)
total.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
total.frame = NSRect(x: 362, y: 14, width: 76, height: 36)
total.lineBreakMode = .byClipping
```

`for label in [title, rate, total, meta]` 改为 `for label in [title, rate, total, meta, totalCaption]`。

`refresh()` 中替换 `labels.total.stringValue = "累计  ↑ …` 一行：

```swift
let lines = Self.totalLines(tx: usage.tx, rx: usage.rx)
labels.total.stringValue = lines.up + "\n" + lines.down
```

- [ ] **Step 4: 构建并跑自测**

```bash
swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```
预期：全绿，`✔ 228 checks passed`（226 + 2）。

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/HomePageController.swift Sources/TrafficMonitor/SelfTest/HomePageTests.swift
git commit -m "fix: 主页模块卡片累计改两行堆叠，大数值不再越界

单行 140pt 标签在数值整数达三位时被裁切；改为「累计」说明字 +
右侧 ↑/↓ 两行等宽数值，最宽情形仍远小于可用宽度

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: 速率图标注固定在角落

**Files:**
- Modify: `Sources/TrafficMonitor/RateGraphView.swift`（`draw(_:)` 61-63 行、删除 `drawEndLabel`）

**Interfaces:** 无新接口；`downloadLabel` / `uploadLabel` 属性语义不变（文案仍由 `HomePageController.refresh()` 每秒更新）。

- [ ] **Step 1: 替换绘制逻辑**

`draw(_:)` 末尾两行端点跟随标注：

```swift
// 线端直接标注当前值（次级文本色）
drawEndLabel(downloadLabel, near: point(samples.count - 1, { $0.rx }), above: true)
drawEndLabel(uploadLabel, near: point(samples.count - 1, { $0.tx }), above: false)
```

替换为：

```swift
// 当前速率标注：位置固定（下载=右上、上传=右下），不随线端移动，避免被折线穿过
drawCornerLabel(downloadLabel, color: Self.downloadColor, atTop: true)
drawCornerLabel(uploadLabel, color: Self.uploadColor, atTop: false)
```

删除 `drawEndLabel(_:near:above:)` 整个方法，新增：

```swift
/// 角落固定标注（右上/右下），用系列色与底部图例呼应
private func drawCornerLabel(_ text: String, color: NSColor, atTop: Bool) {
    guard !text.isEmpty else { return }
    let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    let size = (text as NSString).size(withAttributes: [.font: font])
    let x = bounds.maxX - size.width - 4
    let y = atTop ? bounds.maxY - size.height - 2 : bounds.minY + 2
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: font,
        .foregroundColor: color,
    ])
}
```

（`point` 辅助函数仍被 `drawSeries` 使用，保留。）

- [ ] **Step 2: 构建并跑自测**

```bash
swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```
预期：全绿，`✔ 228 checks passed`（本任务无新断言，靠目检）。

- [ ] **Step 3: 目检（可自动化则自动化）**

```bash
TRAFFICMONITOR_SHOWHOME=1 .build/debug/TrafficMonitor >/dev/null 2>&1 &
```
打开主页人工确认：右上蓝 `↓速率`、右下橙 `↑速率`，固定不动、不被折线穿过。（CI 无头环境跳过；本机执行。）

- [ ] **Step 4: 提交**

```bash
git add Sources/TrafficMonitor/RateGraphView.swift
git commit -m "fix: 速率图当前速率标注固定右上/右下，不再被折线遮挡

原标注跟随线端上下移动，线抬起即从文字中穿过；
改常量角落坐标并着系列色（下载蓝/上传橙），与图例呼应

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: 变更日志 + 截图 + 全量验证

**Files:**
- Modify: `CHANGELOG.md`（`[Unreleased]` 节）
- Modify: `docs/assets/screenshot-menubar.png`、`docs/assets/screenshot-home.png`（重截）

- [ ] **Step 1: CHANGELOG**

`## [Unreleased]` 下补：

```markdown
### 新增 (Added)

- 状态栏菜单新增「合计」行：所有模块累计上行 + 下行与合并总量（与告警同口径），
  数值加重、上方带分隔线

### 变更 (Changed)

- 状态栏菜单 Wi-Fi / iPhone / 合计行改为按内容实测宽度动态计算对齐位，
  数值再大也不折行，面板随之加宽
- 主页模块卡片「累计」改为两行堆叠展示（↑上行 / ↓下行），三位数以上数值不再越界
- 速率图当前速率标注固定在右上（下载）/ 右下（上传）角落并改用系列色，
  不再跟随折线端点、不被线条遮挡
```

- [ ] **Step 2: 重截截图**

运行 `TRAFFICMONITOR_SHOWHOME=1 .build/debug/TrafficMonitor`，分别截主页窗口与下拉菜单（含合计行），覆盖 `docs/assets/screenshot-home.png`、`docs/assets/screenshot-menubar.png`。若本会话无法稳定截菜单下拉，请用户手截后放入同路径。

- [ ] **Step 3: 全量验证**

```bash
swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
```
预期：`✔ 228 checks passed`，退出码 0。

- [ ] **Step 4: 提交**

```bash
git add CHANGELOG.md docs/assets/screenshot-menubar.png docs/assets/screenshot-home.png
git commit -m "docs: 更新变更日志与主页、菜单栏截图

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## 验收清单（对照 spec）

1. 下拉面板出现「合计」行（semibold、上方分隔线），数值 = 两模块合并总量 → Task 1
2. TB 级数值 / 任意名称下三行均单行、列对齐、面板加宽 → Task 1（`stopsKeepColumnsApartAtScale`）
3. 主页模块卡片三位数以上累计完整显示 → Task 2（`totalLinesFormat` + 目检）
4. 速率图两速率值固定上/下角落不被线穿过 → Task 3（目检）
