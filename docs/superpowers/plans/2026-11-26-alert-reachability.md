# 告警触达强化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 告警穿透全屏/专注模式触达用户：时间敏感 UN（横幅+声音同步）、应用内浮动横幅兜底、纯图标模式按告警状态着色、本地兜底音升级。

**Architecture:** SystemNotifier 通知出口加 timeSensitive 维度；新增 AlertBannerPanel 自绘浮窗组件（NSPanel，nonactivating + floating + fullScreenAuxiliary）；MenuBarController.fireAlert 三层触发（Basso 本地音 / timeSensitive UN / 浮窗）；状态栏纯图标 fallback 按 remainingColor 分档着色。

**Tech Stack:** Swift 5.9 / AppKit + UserNotifications / SwiftPM 单 target；自测内置主程序（`TRAFFICMONITOR_SELFTEST=1`）。

**Spec:** docs/superpowers/specs/2026-11-26-alert-reachability-design.md

## Global Constraints

- 通知一律走 UN（不回老接口——仓库铁律）
- 浮窗不夺焦点：styleMask 含 `.nonactivatingPanel`；`level = .floating`；`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`（后者是全屏空格上可见的关键）
- `timeSensitive` 仅告警（fireAlert）；里程碑预告与更新通知保持普通级
- 图标着色仅在纯图标 fallback 分支；告警未设置 = 传入 textColor；有列时不渲染图标（现状不变）
- 本地音 `NSSound(named: "Basso")` 单次，与投递结果解耦（现状模式）
- 浮窗 10 秒自动淡出、悬停暂停、点击打开主页（复用 openHome 路由语义）；纯函数（frame 计算、时长常量）进 SelfTest
- 自测命令 `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`，绿 = `✔ N checks passed`、failures==0（计数随网络环境浮动，以 failures==0 为准）
- 测试与实现同 commit；中文 conventional 提交 + `Co-Authored-By: Claude Code <noreply@anthropic.com>`
- 装机版保护：目检直接跑产物二进制、只杀自启 PID、defaults 动之前先快照、结束精确还原；不 open、不按名 pkill

## Review Focus

1. `.nonactivatingPanel` 缺失 → 浮窗弹出击中全屏游戏会抢焦点把玩家顶回桌面 → Task 3 测试断言 styleMask 包含该 flag + 目检确认无焦点切换。
2. `fullScreenAuxiliary` 缺失 → 全屏空间浮窗不显示（整层白做）→ 同上断言 + 目检。
3. `timeSensitive` 误加到预告/更新通知 → 骚扰升级 → Task 1 测试断言只有告警调用点传 true。
4. 浮窗计时器在面板关闭后仍 fire（复用/泄漏）→ show 前重置状态、dismiss 后使计时器失效 → Task 3 测试覆盖二次 show 场景。
5. 图标着色在「剩余」开关关闭时仍生效（它是状态指示非数据列）→ Task 2 测试断言与 showRemaining 无关。

---

### Task 1: SystemNotifier timeSensitive + 本地音升级

**Files:**
- Modify: `Sources/TrafficMonitor/SystemNotifier.swift`（deliver 闭包签名 + post 参数）
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（fireAlert：Tink→Basso、post 加 timeSensitive: true）
- Test: `Sources/TrafficMonitor/SelfTest/SystemNotifierTests.swift`

**Interfaces:**
- Produces:
  - `SystemNotifier.post(title: String, body: String, identifier: String, sound: Bool = true, timeSensitive: Bool = false, onFailure: ((Error) -> Void)? = nil)`
  - `SystemNotifier.deliver: (String, String, String, Bool, Bool, ((Error) -> Void)?) -> Void`（末尾新增 timeSensitive 位）
  - 默认实现：`timeSensitive ? content.interruptionLevel = .timeSensitive`（false 时不设置属性，维持系统默认 active）
- Task 3 消费 post 的 timeSensitive 位（浮窗与 UN 解耦，不经过 post）。

- [ ] **Step 1: 写失败测试**（SystemNotifierTests：注入 deliver 捕获参数，断言 timeSensitive 位透传；现有用例签名适配）

```swift
static func timeSensitiveFlagPassesThrough() {
    var captured: (String, String, String, Bool, Bool) = ("", "", "", true, false)
    SystemNotifier.deliver = { t, b, i, s, ts, _ in captured = (t, b, i, s, ts) }
    defer { SystemNotifier.resetDeliverForTesting() }  // 或按现有恢复模式
    SystemNotifier.post(title: "t", body: "b", identifier: "id", sound: false, timeSensitive: true)
    TestRun.expect(captured.4, "timeSensitive 位透传")
    SystemNotifier.post(title: "t", body: "b", identifier: "id", sound: false)
    TestRun.expect(!captured.4, "缺省为普通级")
}
```

- [ ] **Step 2: 跑测试确认失败**（编译错：签名不匹配）
- [ ] **Step 3: 实现** deliver/post 签名扩展 + 默认实现按位设 `interruptionLevel`；fireAlert 改 `NSSound(named: "Basso")?.play()`（注释说明升级原因：Tink 太轻被游戏音频掩盖）+ post 加 `timeSensitive: true`
- [ ] **Step 4: 全量自测回归**（failures==0，退出码 0）
- [ ] **Step 5: Commit** `feat: 告警通知时间敏感级 + 本地兜底音升级 Basso`

---

### Task 2: 纯图标模式告警着色

**Files:**
- Modify: `Sources/TrafficMonitor/StatusBarFormatter.swift`（新增纯函数）
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（updateStatusBarContent fallback 分支着色）
- Test: `Sources/TrafficMonitor/SelfTest/StatusBarFormatterTests.swift`

**Interfaces:**
- Produces:
  - `StatusBarFormatter.iconFallbackColor(threshold: UInt64?, fired: Bool, progressBytes: UInt64, textColor: NSColor) -> NSColor`——threshold nil/0 → textColor；否则 `remainingColor(percent: remainingPercent(...) ?? 0, textColor: textColor)`
  - 该函数与 `StatusBarPrefs.showRemaining` **无关**（状态指示，非数据列）

- [ ] **Step 1: 写失败测试**

```swift
static func iconFallbackColorBands() {
    let gb = UInt64(1_000_000_000)
    TestRun.expect(StatusBarFormatter.iconFallbackColor(threshold: nil, fired: false,
                   progressBytes: 100, textColor: .white) == .white, "未设置 → 传入色")
    TestRun.expect(nearWhite(StatusBarFormatter.iconFallbackColor(threshold: 20 * gb, fired: false,
                   progressBytes: 15 * gb, textColor: .white)), "25% 剩余 → 白")
    TestRun.expect(near(StatusBarFormatter.iconFallbackColor(threshold: 20 * gb, fired: false,
                   progressBytes: 18 * gb, textColor: .white), .systemOrange), "10% 剩余 → 橙")
    TestRun.expect(near(StatusBarFormatter.iconFallbackColor(threshold: 20 * gb, fired: true,
                   progressBytes: 0, textColor: .white), .systemRed), "已触发 → 红")
}
```

（near 辅助用现有 rgbs 模式；`nearWhite` 即与 .white 近似比较。）

- [ ] **Step 2: 确认红 → Step 3: 实现**（updateStatusBarContent fallback：图标 tint 改由该函数计算，alert 数据来自 MenuBarController 现有 `alert`/`currentMeteredTotal()`）→ **Step 4: 自测回归** → **Step 5: Commit** `feat: 纯图标模式状态栏图标随告警状态着色`

---

### Task 3: AlertBannerPanel 浮动横幅

**Files:**
- Create: `Sources/TrafficMonitor/AlertBannerPanel.swift`
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（fireAlert 触发浮窗；MenuBarController 持有）
- Test: `Sources/TrafficMonitor/SelfTest/AlertBannerPanelTests.swift`（新建；TestSupport 登记 suite）

**Interfaces:**
- Produces:
  - `AlertBannerPanel`（@MainActor）：`init()`；`show(title: String, body: String, onClick: @escaping () -> Void)`；`dismiss()`
  - `static let displayDuration: TimeInterval = 10`
  - `nonisolated static func bannerFrame(screenFrame: NSRect, bannerSize: NSSize) -> NSRect`（顶部居中、菜单栏下方 8pt；纯函数可测）
  - 内部 NSPanel：styleMask `[.borderless, .nonactivatingPanel]`、level `.floating`、collectionBehavior `[.canJoinAllSpaces, .fullScreenAuxiliary]`、wantsLayer 圆角深色卡（与主页背景语言一致：近黑底、白字、AppIcon + 标题 + 正文）
  - 悬停暂停：NSTrackingArea mouseEntered 取消计时、mouseExited 重新调度；show 前重置旧计时器（二次 show 无泄漏）
  - 淡出：NSAnimationContext alpha → 0 后 orderOut 并复位

- [ ] **Step 1: 写失败测试**（AlertBannerPanelTests：①bannerFrame 水平居中且 y = screen.maxY − 8 − height；②displayDuration == 10；③二次 show 状态重置——show/dismiss/show 后 isPanelVisible 语义正确或等价可测断言；TestSupport.swift 登记 `TestRun.suite("AlertBannerPanel") { ... }`）
- [ ] **Step 2: 确认红** → **Step 3: 实现**（组件 + fireAlert 接线 `alertBanner.show(title: "Traffic Monitor 流量告警", body: "已用 \(used)，达到 \(limit)。", onClick: { [weak self] in self?.openHome() })`；MenuBarController 懒持有）
- [ ] **Step 4: 自测回归** → **Step 5: Commit** `feat: 告警浮动横幅（不夺焦点、跨全屏空间、悬停暂停、点击开主页）`

---

### Task 4: 全量自测 + 打包演示 + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`（[Unreleased] 增补：告警时间敏感级突破专注/全屏 + 横幅同步声音、告警浮动横幅、纯图标模式告警着色、兜底音 Basso）
- 目检不提交产物（`Traffic Monitor.app` 保持 gitignored）

**步骤：**
- [ ] **Step 1: 全量自测**（failures==0 退出码 0）
- [ ] **Step 2: 打包并自演示**：`swift build -c release && scripts/make-app.sh`；defaults 快照后设全关（totals/rates/remaining 均 false）→ `TRAFFICMONITOR_ALERT_MB=1` 启动（持久累计 >> 1MB，首拍即触发）→ 截图捕获浮窗 + 红色图标（10 秒窗口内）；再设 totals=1 rates=0 remaining=1 复核有列场景；完毕 `kill` 自启 PID、defaults 精确还原（快照原值写回/不存在的 delete）
- [ ] **Step 3: 留住一个调试实例供用户现场观看**（新 PID 写 /tmp/tm-demo.pid，告知用户告警已演示、面板 10 秒窗口）
- [ ] **Step 4: Commit** `docs: CHANGELOG [Unreleased] 增补告警触达强化`

## Self-Review 记录

- 覆盖：spec 四目标 ↔ Task 1（timeSensitive+Basso）/ Task 3（浮窗）/ Task 2（图标着色）/ Task 4（验证留档）；非目标未越界（预告不提级 = Task 1 测试、无模态）
- 签名一致：`post(sound:timeSensitive:onFailure:)`、`iconFallbackColor(threshold:fired:progressBytes:textColor:)`、`bannerFrame(screenFrame:bannerSize:)` 各任务间一致
- Review Focus 5 条：1/2/4 → Task 3；3 → Task 1；5 → Task 2
