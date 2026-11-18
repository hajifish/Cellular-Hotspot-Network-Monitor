# 主页左列重排（汇总条上移同行 + 总流量项）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 主页左列汇总条上移到「累计流量」开关同一行并新增「总流量」第四项，接口卡片加高使左右列上下边缘对齐；右侧告警圆环不动。

**Architecture:** 纯 AppKit 手工定框布局，改 [HomePageController.swift](../../../Sources/TrafficMonitor/HomePageController.swift) 的 frame 常量与 `refresh()` 一处接线；新增一个可测纯函数。无新文件、无新依赖。

**Tech Stack:** Swift 5.9 / AppKit，SPM 单可执行 target，内置自测（`TRAFFICMONITOR_SELFTEST=1`）。

## Global Constraints

- 本机为 macOS CLT 工具链：无 XCTest / swift-testing；测试 = SelfTest 目录内置自测，运行命令 `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`。
- **绝不 kill/open 装机版应用**；目检直接运行产物二进制（`"Traffic Monitor.app/Contents/MacOS/TrafficMonitor"`），与装机版共存。
- 注释、提交信息中文为主；提交信息带 `Co-Authored-By: Claude Code <noreply@anthropic.com>` 尾行。
- 布局数值（AppKit 底左原点，窗口 720×470）：
  - 汇总条 `(24, 402, 456, 46)`，顶边 448 = 开关胶囊顶边；
  - 槽位 x = 会话18 / 总上传126 / 总下载234 / 总流量342，宽 105；
  - 接口卡 `(24/259, 180, 221, 214)`，卡内 title/meta/reset local y = 182/166/180，rate/total 不变（58/20）；
  - 圆环面板 `(492, 180, 204, 234)` 不动。
- 设计依据：`docs/superpowers/specs/2026-11-18-home-summary-row-design.md`。

---

### Task 1: 总流量汇总项（纯函数 + 第四槽位）

**Files:**
- Modify: `Sources/TrafficMonitor/SelfTest/HomePageTests.swift`
- Modify: `Sources/TrafficMonitor/HomePageController.swift`

**Interfaces:**
- Consumes: `ByteFormat.string(UInt64) -> String`（十进制单位，如 `2_600_000_000 -> "2.6 GB"`）
- Produces: `HomePageController.summaryTotalLine(tx: UInt64, rx: UInt64) -> String`，返回 `"↑↓ <合并值>"`；`summaryValues` 数组从 3 项变 4 项（索引 3 = 总流量）

- [ ] **Step 1: 写失败测试**

`Sources/TrafficMonitor/SelfTest/HomePageTests.swift`：`all()` 里 `totalLineFormat()` 之后加一行 `summaryTotalLineFormat()`，文件末尾（`durationTextFormatting` 之后、类结尾 `}` 之前）加：

```swift
    static func summaryTotalLineFormat() {
        TestRun.expectEqual(HomePageController.summaryTotalLine(tx: 0, rx: 0), "↑↓ 0 B", "zero total")
        TestRun.expectEqual(
            HomePageController.summaryTotalLine(tx: 1_200_000_000, rx: 1_400_000_000),
            "↑↓ 2.6 GB", "combined upload+download")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift build 2>&1 | tail -3`
Expected: 编译错误 `value of type ... has no member 'summaryTotalLine'`（单模块方案下"未定义"即失败）

- [ ] **Step 3: 实现纯函数 + 接线第四槽位 + 槽宽调整**

`Sources/TrafficMonitor/HomePageController.swift`：

(a) `totalLine(tx:rx:)` 之后（约 84 行处）加：

```swift
    /// 汇总条总流量单行文本（纯函数，可测）：↑↓ 合并 = 总上传 + 总下载
    nonisolated static func summaryTotalLine(tx: UInt64, rx: UInt64) -> String {
        "↑↓ \(ByteFormat.string(tx + rx))"
    }
```

(b) `summarySpecs` 三项改四项（约 135 行）：

```swift
        let summarySpecs: [(String, CGFloat)] = [
            ("会话", 18), ("总上传", 126), ("总下载", 234), ("总流量", 342),
        ]
```

(c) 同一循环内两处 frame 宽度 `120` 改 `105`（caption 与 value 两行：`NSRect(x: x, y: 26, width: 105, height: 12)`、`NSRect(x: x, y: 6, width: 105, height: 18)`）。

(d) `refresh()` 汇总赋值处（约 572 行）追加第四项：

```swift
        summaryValues[1].stringValue = "↑ \(ByteFormat.string(totalTX))"
        summaryValues[2].stringValue = "↓ \(ByteFormat.string(totalRX))"
        summaryValues[3].stringValue = Self.summaryTotalLine(tx: totalTX, rx: totalRX)
```

- [ ] **Step 4: 跑自测确认通过**

Run: `swift build 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor | tail -3`
Expected: `✔ 356 checks passed`（基线 354 + 新增 2；只要 0 failed 且全量套件 ok 即可，数量以实际基线 +2 为准）

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/HomePageController.swift Sources/TrafficMonitor/SelfTest/HomePageTests.swift
git commit -m "feat: 汇总条新增总流量项（↑↓ 合并总上传+总下载）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: 左列重排（汇总条上移同行 + 接口卡片加高）

**Files:**
- Modify: `Sources/TrafficMonitor/HomePageController.swift`

**Interfaces:**
- Consumes: Task 1 的四槽位 `summarySpecs`
- Produces: 无新接口；`updateBaseViews` 成员 frame 更新，折叠/展开的 y 增量平移逻辑不受影响

- [ ] **Step 1: 汇总条上移**

`buildUI()` 中（约 132 行）：

```swift
        // 左列汇总条：会话、总上传、总下载、总流量（顶边 448 与右上「累计流量」开关同行，2026-11-18 左列重排）
        let strip = roundedCard(frame: NSRect(x: 24, y: 402, width: 456, height: 46))
```

- [ ] **Step 2: 接口卡片加高 + 卡内顶部元素上移**

(a) 卡片 frame（约 156 行）`height: 182 → 214`，注释同步：

```swift
            // 卡片加高：顶边 394 与汇总条底边 402 留 8pt，左右列上下边缘对齐（顶 448 / 底 180）
            let card = roundedCard(frame: NSRect(x: x, y: 180, width: 221, height: 214))
```

(b) 卡内顶部三件随顶边上移 +32（rate y=58、total y=20 不变，保持贴底）：

```swift
            let title = makeLabel(size: 13, color: .labelColor, weight: .semibold)
            title.frame = NSRect(x: 14, y: 182, width: 150, height: 18)
            let meta = makeLabel(size: 10, color: .tertiaryLabelColor, weight: .regular)
            meta.frame = NSRect(x: 14, y: 166, width: 193, height: 14)
```

重置按钮（约 170 行）：

```swift
                reset.frame = NSRect(x: 181, y: 180, width: 26, height: 22)
```

- [ ] **Step 3: 构建确认零警告零错误**

Run: `swift build 2>&1 | tail -3`
Expected: 编译通过

- [ ] **Step 4: 提交**

```bash
git add Sources/TrafficMonitor/HomePageController.swift
git commit -m "feat: 主页左列重排——汇总条上移与累计流量开关同行、接口卡片加高对齐

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: 全量验证 + 打包目检

**Files:**
- 只读验证；如目检发现问题，修 `Sources/TrafficMonitor/HomePageController.swift`

**Interfaces:**
- Consumes: Task 1-2 完成后的工作区
- Produces: 验证结论（自测全绿 + 截图目检通过）

- [ ] **Step 1: release 构建 + 全量自测**

Run: `swift build -c release 2>&1 | tail -3 && TRAFFICMONITOR_SELFTEST=1 .build/release/TrafficMonitor | tail -5`
Expected: `✔ N checks passed`，0 failed，所有套件 ok

- [ ] **Step 2: 打包**

Run: `./scripts/make-app.sh 2>&1 | tail -2`
Expected: `Built ./Traffic Monitor.app`

- [ ] **Step 3: 运行产物二进制并截图目检**（与装机版共存，不 kill、不用 open）

```bash
"Traffic Monitor.app/Contents/MacOS/TrafficMonitor" >/tmp/tm-dev.log 2>&1 &
APP_PID=$!
sleep 3
WID=$(APP_PID=$APP_PID swift - <<'EOF'
import CoreGraphics
import Foundation
let target = Int32(ProcessInfo.processInfo.environment["APP_PID"] ?? "0") ?? 0
// 跨 Space 须用 .optionAll 枚举；键名为 kCGWindowOwnerPID（无 Window 中缀）且需 as String 转换
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID] as? Int32) == target {
    if let num = w[kCGWindowNumber] as? Int { print(num) }
}
EOF
)
screencapture -x -o -l "$WID" /tmp/home-summary-row-check.png
```

读 `/tmp/home-summary-row-check.png`，逐项确认：
1. 汇总条与右上「累计流量 / 实时速率」开关同一行，四项齐全（会话 / 总上传 / 总下载 / 总流量）；
2. 总流量值 = ↑ 与 ↓ 之和（对不上即 bug）；
3. 左列卡片加高后无空洞，左右列顶/底边缘对齐；
4. 右侧告警圆环面板与改版前一致。
目检完杀掉的是**本次启动的 dev 实例 PID**（`kill $APP_PID`），绝不按名字 pkill。

- [ ] **Step 4: 若目检发现问题** → 修复后重跑 Step 1-3，修复单独提交 `fix: ...`；无问题则本任务无提交。
