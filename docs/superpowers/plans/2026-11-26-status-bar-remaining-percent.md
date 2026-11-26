# 状态栏「剩余」展示项 + 开关文案缩短 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 状态栏新增第三种可选展示「告警剩余百分比」（独立开关），主页右上角三枚开关缩短为「累计 / 实时 / 剩余」。

**Architecture:** 沿用 StatusBarPrefs 独立布尔开关模式；StatusBarFormatter 增加两个纯函数（百分比计算、颜色分档）并在 attributed() 里追加单值列；MenuBarController.updateStatusBarContent 接线告警数据；HomePageController 增加第三枚胶囊。

**Tech Stack:** Swift 5.9 / AppKit / SwiftPM 单 target；测试为内置 SelfTest（`TRAFFICMONITOR_SELFTEST=1`）。

**Spec:** `docs/superpowers/specs/2026-11-26-status-bar-remaining-percent-design.md`

## Global Constraints

- 颜色分档（spec 定死）：剩余 >20% 用传入 textColor（白）；≤20% `.systemOrange`；0% `.systemRed`。
- 百分比 = `(阈值 − 进度) ÷ 阈值 × 100` 四舍五入取整；进度 ≥ 阈值或已触发 → 0；阈值 nil 或 0 → 视为未设置（不渲染列）。
- `showRemaining` 默认 **false**（UserDefaults key：`statusBarShowRemaining`）。
- 三枚胶囊右缘对齐 x=708、宽 60、间距 6：累计 x=516、实时 x=582、剩余 x=648；左缘 516 不得越过汇总条右缘 480。
- 胶囊文案：`累计` / `实时` / `剩余`（两字，字号保持 11pt 不缩）。
- 状态栏剩余列排在最右（实时列之后），单值跨「↑/↓」两行视觉垂直居中。
- 自测命令：`swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`，须输出 `✔ N checks passed`（N ≥ 354）。
- 测试与实现同一 commit；提交信息中文 conventional 风格，结尾加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。
- 目检打包 `scripts/make-app.sh`（产物 `Traffic Monitor.app` 在仓库根），直接跑产物二进制，禁止 `open`、禁止按名 pkill（杀进程只用启动时记录的 PID）；不得动装机版应用。

## Review Focus

1. 阈值存 0（`alertThresholdBytes` 可为 0）→ remainingPercent 必须返回 nil，不得除零崩溃 → Task 1 测试 `thresholdZeroIsUnset`。
2. 进度恰好等于阈值 → 0%（红），不得出现负数或 >100 → Task 1 测试 `progressAtThresholdIsZero` / `progressOverThresholdIsZero`。
3. 舍入边界：剩 2/3 → 67（四舍五入非截断）→ Task 1 测试 `remainingPercentRoundsHalfUp`。
4. 三开关全开最宽组合（`↑999MB ↑99KB/s 100%` 两行）位图宽度不得溢出（renderedImage boundingRect 上限 400pt）→ Task 5 目检确认不截断。
5. 设置/切换/关闭告警阈值后状态栏列即时出现/消失 → Task 3 补 `refresh()` + Task 5 目检。

---

### Task 1: 剩余百分比纯函数 + showRemaining 开关

**Files:**
- Modify: `Sources/TrafficMonitor/StatusBarFormatter.swift`（StatusBarPrefs 与新纯函数都在此文件）
- Test: `Sources/TrafficMonitor/SelfTest/StatusBarFormatterTests.swift`

**Interfaces:**
- Consumes: 无（ foundational 纯函数）
- Produces:
  - `StatusBarPrefs.showRemaining: Bool`（UserDefaults key `statusBarShowRemaining`，默认 false，读写同 showRates 模式）
  - `StatusBarFormatter.remainingPercent(threshold: UInt64?, fired: Bool, progressBytes: UInt64) -> Int?`
  - `StatusBarFormatter.remainingColor(percent: Int, textColor: NSColor) -> NSColor`
- Task 2、Task 3 按上述精确签名消费。

- [ ] **Step 1: 写失败测试**（`StatusBarFormatterTests.swift`，`all()` 里登记新用例；文件头部 `import AppKit` 按需补——现文件无 import，颜色断言需要）

```swift
// ---- remainingPercent ----
static func remainingPercentMath() {
    let gb = UInt64(1_000_000_000)
    TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 20 * gb, fired: false,
                       progressBytes: 15 * gb), 25, "20GB 用 15GB 剩 25%")
    TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: false,
                       progressBytes: 250), 75, "普通值")
    TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 3, fired: false,
                       progressBytes: 1), 67, "2/3 四舍五入 67")
    TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: false,
                       progressBytes: 1_000), 0, "进度=阈值 → 0")
    TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: false,
                       progressBytes: 5_000), 0, "进度超阈值 → 0")
    TestRun.expectEqual(StatusBarFormatter.remainingPercent(threshold: 1_000, fired: true,
                       progressBytes: 100), 0, "已触发 → 0")
    TestRun.expect(StatusBarFormatter.remainingPercent(threshold: nil, fired: false,
                   progressBytes: 100) == nil, "未设置 → nil")
    TestRun.expect(StatusBarFormatter.remainingPercent(threshold: 0, fired: false,
                   progressBytes: 100) == nil, "阈值 0 → nil（防除零）")
}

// ---- remainingColor（sRGB 分量近似比较，避免 NSColor 相等性不可靠）----
private static func rgbs(_ c: NSColor) -> (Double, Double, Double) {
    let s = c.usingColorSpace(.sRGB)!
    return (Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent))
}

static func remainingColorBands() {
    func near(_ a: NSColor, _ b: NSColor) -> Bool {
        let (r1, g1, b1) = rgbs(a), (r2, g2, b2) = rgbs(b)
        return abs(r1 - r2) < 0.05 && abs(g1 - g2) < 0.05 && abs(b1 - b2) < 0.05
    }
    TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 100, textColor: .white), .white),
                   ">20% 用传入色")
    TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 21, textColor: .white), .white),
                   "21% 仍白")
    TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 20, textColor: .white), .systemOrange),
                   "≤20% 橙")
    TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 1, textColor: .white), .systemOrange),
                   "1% 橙")
    TestRun.expect(near(StatusBarFormatter.remainingColor(percent: 0, textColor: .white), .systemRed),
                   "0% 红")
}

// ---- showRemaining 开关 ----
static func showRemainingPrefDefaultsAndToggles() {
    let original = StatusBarPrefs.showRemaining
    defer { StatusBarPrefs.showRemaining = original }
    TestRun.expect(UserDefaults.standard.object(forKey: StatusBarPrefs.showRemainingKey) == nil
                   || !original || true, "读取不崩") // 默认值断言见下行：fresh 环境默认 false
    StatusBarPrefs.showRemaining = true
    TestRun.expect(StatusBarPrefs.showRemaining, "写后读回 true")
}
```

注意：`showRemainingPrefDefaultsAndToggles` 里的第一行断言只是占位读安全；真正的默认值断言改为——若 `UserDefaults.standard.object(forKey:)` 为 nil 则 getter 必须等于 false：

```swift
static func showRemainingPrefDefaultsAndToggles() {
    let original = StatusBarPrefs.showRemaining
    defer { StatusBarPrefs.showRemaining = original }
    if UserDefaults.standard.object(forKey: StatusBarPrefs.showRemainingKey) == nil {
        TestRun.expect(!StatusBarPrefs.showRemaining, "未设置时默认 false")
    }
    StatusBarPrefs.showRemaining = true
    TestRun.expect(StatusBarPrefs.showRemaining, "写后读回 true")
}
```

`all()` 更新为：

```swift
static func all() {
    ratesOnlyIsVerticalGroup()
    totalsOnlyIsVerticalGroup()
    bothIsTwoSideBySideGroups()
    bothOffIsNil()
    remainingPercentMath()
    remainingColorBands()
    showRemainingPrefDefaultsAndToggles()
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift build 2>&1 | tail -5`
Expected: 编译失败（`showRemainingKey`/`remainingPercent`/`remainingColor` 不存在）。

- [ ] **Step 3: 实现**

StatusBarPrefs 增加（照 showRates 模式）：

```swift
static let showRemainingKey = "statusBarShowRemaining"
static var showRemaining: Bool {
    get { UserDefaults.standard.object(forKey: showRemainingKey) as? Bool ?? false }
    set { UserDefaults.standard.set(newValue, forKey: showRemainingKey) }
}
```

StatusBarFormatter enum 增加两个静态纯函数（含与 spec 一致的中文 doc 注释）：

```swift
/// 告警剩余百分比（0-100 四舍五入）；未设置/阈值为 0 → nil；已触发或进度≥阈值 → 0
static func remainingPercent(threshold: UInt64?, fired: Bool, progressBytes: UInt64) -> Int?
/// 剩余分档色：>20% 传入色（白）；≤20% 橙；0% 红（与主页汇总条 armed/fired 语义一致）
static func remainingColor(percent: Int, textColor: NSColor) -> NSColor
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor 2>&1 | tail -5`
Expected: `✔ N checks passed`（现有用例全绿 + 新增用例绿）。

- [ ] **Step 5: Commit**

```bash
git add Sources/TrafficMonitor/StatusBarFormatter.swift Sources/TrafficMonitor/SelfTest/StatusBarFormatterTests.swift
git commit -m "feat: 剩余百分比纯函数与颜色分档 + statusBarShowRemaining 开关

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: attributed() 渲染第三列

**Files:**
- Modify: `Sources/TrafficMonitor/StatusBarFormatter.swift:34-106`（StatusBarFormatter.attributed 及其 doc 注释）
- Test: `Sources/TrafficMonitor/SelfTest/StatusBarFormatterTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `remainingPercent`/`remainingColor`/`StatusBarPrefs.showRemaining`（本任务只用前两者；prefs 在 Task 3 接线）。
- Produces（Task 3 消费的最终签名）:

```swift
static func attributed(showRates: Bool, showTotals: Bool, showRemaining: Bool,
                       remainingPercent: Int?, textColor: NSColor,
                       totalRate: CategoryDelta, totalRX: UInt64, totalTX: UInt64) -> NSAttributedString?
```

语义：`showRemaining == false` 或 `remainingPercent == nil` → 不渲染该列（等价于没传）；其余在原两列最右追加 `"\(percent)%"` 单值，放第一行行尾、基线下移约 3.5pt 视觉跨两行居中；仅剩这一列时（rates+totals 全关）输出单行 `"\(percent)%"`。全部为空 → 仍返回 nil。

- [ ] **Step 1: 更新失败测试**（现有 4 用例调用点补 `showRemaining: false, remainingPercent: nil`，断言文本不变；新增用例并登记进 `all()`）

```swift
static func remainingOnlyShowsPercent() {
    let text = StatusBarFormatter.attributed(showRates: false, showTotals: true, showRemaining: false,
                                             remainingPercent: 25, textColor: .white,
                                             totalRate: rate, totalRX: 0, totalTX: 0)
    TestRun.expect(text == nil, "开关关 → 即使有百分比也不渲染")
}

static func remainingColumnRenders() {
    let text = StatusBarFormatter.attributed(showRates: false, showTotals: false, showRemaining: true,
                                             remainingPercent: 25, textColor: .white,
                                             totalRate: rate, totalRX: 0, totalTX: 0)?.string
    TestRun.expectEqual(text, "25%", "仅剩余列单行输出")
}

static func allThreeColumns() {
    let text = StatusBarFormatter.attributed(showRates: true, showTotals: true, showRemaining: true,
                                             remainingPercent: 25, textColor: .white,
                                             totalRate: rate,
                                             totalRX: 8_100_000_000, totalTX: 2_300_000_000)?.string
    TestRun.expectEqual(text, "↑2.3GB  ↑300B/s  25%\n↓8.1GB  ↓1.2KB/s",
                        "累计 → 实时 → 剩余（剩余只在首行）")
}

static func unsetAlertHidesColumn() {
    let text = StatusBarFormatter.attributed(showRates: false, showTotals: false, showRemaining: true,
                                             remainingPercent: nil, textColor: .white,
                                             totalRate: rate, totalRX: 0, totalTX: 0)
    TestRun.expect(text == nil, "告警未设置 → 列不占位")
}
```

`all()` 追加：`remainingOnlyShowsPercent()`、`remainingColumnRenders()`、`allThreeColumns()`、`unsetAlertHidesColumn()`。

- [ ] **Step 2: 跑测试确认失败**

Run: `swift build 2>&1 | tail -5`
Expected: 编译失败（attributed 缺参）。

- [ ] **Step 3: 实现**

attributed 签名如 Interfaces；渲染逻辑要点（实现者写实现）：
- `let remaining: (text: String, color: NSColor)? = showRemaining ? remainingPercent.map { ("\($0)%", remainingColor(percent: $0, textColor: textColor)) } : nil`
- 出口条件改为 `guard !columns.isEmpty || remaining != nil else { return nil }`。
- columns 为空 → 直接拼单行：font 9pt semibold（`monospacedDigitSystemFont`）、remaining 色、无分隔。
- 否则沿用双行循环，第一行全部列之后追加：两空格分隔（8pt，同现有）+ 百分比段（font 9pt semibold、remaining 色、`.baselineOffset: -3.5`）。
- doc 注释布局示例更新为：

```text
↑3.9MB   ↑5.1KB/s  75%
↓1.2MB   ↓9.2KB/s
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor 2>&1 | tail -5`
Expected: `✔ N checks passed`。

- [ ] **Step 5: Commit**

```bash
git add Sources/TrafficMonitor/StatusBarFormatter.swift Sources/TrafficMonitor/SelfTest/StatusBarFormatterTests.swift
git commit -m "feat: 状态栏第三列渲染告警剩余百分比

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: MenuBarController 接线

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（`updateStatusBarContent()` ~L250-274；实例方法 `applyAlertThreshold` 尾部 ~L406）

**Interfaces:**
- Consumes: Task 1/2 全部产物（`StatusBarPrefs.showRemaining`、`remainingPercent(threshold:fired:progressBytes:)`、`attributed` 新签名）、既有 `alert: TrafficAlert`、`currentMeteredTotal()`。
- Produces: 无（叶子接线）。

- [ ] **Step 1: 编译期失败的改动即测试**（本任务无新纯逻辑，编译通过 + 全量自测回归即验证）

- [ ] **Step 2: 实现**

`updateStatusBarContent()` 内、调用 attributed 前计算：

```swift
let remainingPercent: Int? = StatusBarPrefs.showRemaining
    ? StatusBarFormatter.remainingPercent(threshold: alert.threshold,
                                          fired: alert.fired,
                                          progressBytes: alert.progress(totalBytes: currentMeteredTotal()))
    : nil
```

attributed 调用补 `showRemaining: StatusBarPrefs.showRemaining, remainingPercent: remainingPercent`。
方法 doc 注释「仅图标模式…」段补一句：剩余列数据来自告警阈值与进度，未设置告警时不渲染。

实例方法 `applyAlertThreshold` 的 `refreshAlertMenuStates()` 之后追加 `refresh()`，注释：`// 状态栏剩余列即时反映阈值增删（采样 tick 有 ≤1s 延迟）`。

- [ ] **Step 3: 全量自测回归**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor 2>&1 | tail -3`
Expected: `✔ N checks passed`（TrafficMonitorApp suite 全绿）。

- [ ] **Step 4: Commit**

```bash
git add Sources/TrafficMonitor/TrafficMonitorApp.swift
git commit -m "feat: 状态栏接线告警剩余百分比，阈值增删即时刷新

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: 主页三枚开关胶囊

**Files:**
- Modify: `Sources/TrafficMonitor/HomePageController.swift`（属性区 ~L26-31；buildUI 开关段 ~L111-134；`toggleRates`/`toggleTotals`/`refreshToggles` ~L328-350；L111、L136 注释）

**Interfaces:**
- Consumes: `StatusBarPrefs.showRemaining`（Task 1）。
- Produces: 无（纯 UI；`updateBaseViews` 平移列表包含新胶囊）。

- [ ] **Step 1: 实现**（UI 无纯函数可测，编译 + 目检即验证；SelfTest 不加用例）

属性区仿现有三元组追加：`remainingChip: NSView!`、`remainingToggle: NSButton!`、`remainingLabel: NSTextField!`。

buildUI 开关段（注释改为「顶部右侧：状态栏显示开关（累计/实时/剩余三枚；都关 = 状态栏只显示图标）」）：

- `totalsChip.frame = NSRect(x: 516, y: 386, width: 60, height: 26)`；label `stringValue = "累计"`，frame 改 `NSRect(x: 28, y: 5, width: 26, height: 16)`
- `ratesChip.frame = NSRect(x: 582, y: 386, width: 60, height: 26)`；label `"实时"`，同上 frame
- 新增 `remainingChip`：frame `NSRect(x: 648, y: 386, width: 60, height: 26)`，`remainingToggle`（action `#selector(toggleRemaining)`，frame 同现有 x6 y4 18×18），`remainingLabel` `"剩余"` frame 同上；`content.addSubview(remainingChip)`、`remainingChip.addSubview(...)` 与现有一致
- `updateBaseViews.append(contentsOf:)` 追加 `remainingChip`
- L136 注释「右上『累计流量』开关同行」改为「右上开关胶囊行」

动作与刷新：

```swift
@objc private func toggleRemaining() {
    StatusBarPrefs.showRemaining.toggle()
    refreshToggles()
}
```

`refreshToggles()` 按 totals/rates 现有五行样式（styleSphere、chip 底色、label font/textColor）补 remaining 三元组。

- [ ] **Step 2: 编译 + 全量自测回归**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor 2>&1 | tail -3`
Expected: `✔ N checks passed`。

- [ ] **Step 3: Commit**

```bash
git add Sources/TrafficMonitor/HomePageController.swift
git commit -m "feat: 主页三枚状态栏开关（累计/实时/剩余）并缩短文案

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 5: 全量自测 + 打包目检 + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`（`[Unreleased]` 段）

**Interfaces:**
- Consumes: 前四个任务全部完成后的 feature 分支。
- Produces: 验证结论 + CHANGELOG 条目。

- [ ] **Step 1: 全量自测**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor 2>&1 | tail -3`
Expected: `✔ N checks passed`，N ≥ 354，退出码 0。

- [ ] **Step 2: 打包并启动目检**

```bash
swift build -c release && scripts/make-app.sh
defaults write local.shin.TrafficMonitor statusBarShowRemaining -bool true
defaults write local.shin.TrafficMonitor statusBarShowTotals -bool true
TRAFFICMONITOR_SHOWHOME=1 TRAFFICMONITOR_ALERT_MB=50000 "./Traffic Monitor.app/Contents/MacOS/TrafficMonitor" &
echo $! > /tmp/tm-visual.pid
sleep 3 && screencapture -x /tmp/tm-visual-home.png
```

检查 `screencapture` 截图（Read 图片）：① 右上角三枚胶囊「累计 / 实时 / 剩余」，无重叠、不压汇总条；② 状态栏出现剩余百分比列（50GB 阈值下应为白色大百分比）；③ 切换 `statusBarShowRemaining -bool false` 重启后列消失。目检完毕 `kill $(cat /tmp/tm-visual.pid)`（只杀自己起的 PID）。Review Focus 第 4 条（三列全开不溢出）在同一截图中确认。

- [ ] **Step 3: 恢复 prefs 并写 CHANGELOG**

```bash
defaults delete local.shin.TrafficMonitor statusBarShowRemaining 2>/dev/null || true
defaults delete local.shin.TrafficMonitor statusBarShowTotals 2>/dev/null || true
```

`CHANGELOG.md` 的 `[Unreleased]` 增补（中文，风格随既有条目）：

```markdown
- 状态栏新增「告警剩余百分比」展示项（右上角新增「剩余」开关；告警未设置时不占位，剩余 ≤20% 转橙、触发转红）
- 主页右上角开关文案缩短：累计流量→累计、实时速率→实时
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG [Unreleased] 增补状态栏剩余百分比与开关文案缩短

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Self-Review 记录

- 覆盖检查：spec 四条目标 → Task 1/2（展示项+计算）、Task 2（状态栏列）、Task 4（胶囊+文案）、Task 1/5（测试）；非目标未越界（未动 alertStrip、告警逻辑、菜单）。
- 签名一致性：`remainingPercent(threshold:fired:progressBytes:) -> Int?`、`remainingColor(percent:textColor:) -> NSColor`、`attributed(showRates:showTotals:showRemaining:remainingPercent:textColor:totalRate:totalRX:totalTX:)` 在 Task 1/2/3 间一致。
- Review Focus 5 条：1/2/3 落 Task 1 测试；4/5 落 Task 5 目检。
- 比例：测试代码为计划主体，实现只给签名与算法要点，无转录体。
