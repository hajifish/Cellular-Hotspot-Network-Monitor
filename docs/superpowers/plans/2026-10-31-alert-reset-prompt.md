# 设置流量告警时可选同步重置计量 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每次设置新流量告警阈值（非「关闭」）时弹窗询问是否同步重置所有模块累计流量并重新计量。

**Architecture:** 全部改动集中在 `MenuBarController`（TrafficMonitorApp.swift）：`applyAlertThreshold` 在应用非 nil 阈值前先经 `askSyncReset()` 弹窗询问，答「是」则先 `monitor.reset(nil)` 再设阈值（基线自然为 0）。里程碑/速率历史/状态栏刷新全部复用现有 `onReset` + observer 机制，不改任何模型代码。

**Tech Stack:** Swift + AppKit（NSAlert 菜单栏应用，macOS CLT 工具链，无 Xcode/XCTest）。

**Spec:** `docs/superpowers/specs/2026-10-31-alert-reset-prompt-design.md`

## Global Constraints

- 平台 macOS 14+；工具链为 CLT（无 Xcode）：XCTest/swift-testing 不可用，自测内置主程序，命令 `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`
- 本功能无新增自测项（spec 已定）：验证 = 全量自测无回归 + `scripts/make-app.sh` 打包后人工目检（裸二进制 GUI 会崩，必须打包跑）
- 不改 `TrafficAlert` / `TrafficMonitor` / `UsageStore` 模型代码
- 弹窗文案与按钮逐字使用 spec 定稿：messageText `是否同步重置累计流量？`；按钮 `同步重置`（第一）/ `仅设置告警`（第二）
- 文档中文为主；提交信息用约定式前缀（feat/docs）
- 分支：`feature/alert-reset-prompt`（已从 develop 创建）

---

### Task 1: askSyncReset 弹窗与 applyAlertThreshold 接线

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift:236-248`（`applyAlertThreshold`）及其后新增 `askSyncReset`

**Interfaces:**
- Consumes: `monitor.reset(_ category: InterfaceCategory? = nil)`（既有）、`alert.setThreshold(_ bytes: UInt64?, baselineBytes: UInt64)`（既有）、`currentMeteredTotal() -> UInt64`（既有）
- Produces: `private func askSyncReset() -> Bool`（仅本文件内部使用，无外部依赖方）

- [ ] **Step 1: 跑全量自测确认基线全绿**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`
Expected: `swift build` 无报错；自测全部通过（约 230 项），退出码 0

- [ ] **Step 2: 修改 applyAlertThreshold 并新增 askSyncReset**

将 `Sources/TrafficMonitor/TrafficMonitorApp.swift` 中现有的：

```swift
private func applyAlertThreshold(_ bytes: UInt64?, persist: Bool) {
    // 告警进度从设置时刻的流量重新起算
    alert.setThreshold(bytes, baselineBytes: currentMeteredTotal())
    if persist {
        if let bytes {
            UserDefaults.standard.set(Int64(bytes), forKey: Self.alertDefaultsKey)
            requestNotificationAuthorization()
        } else {
            UserDefaults.standard.removeObject(forKey: Self.alertDefaultsKey)
        }
    }
    refreshAlertMenuStates()
}
```

替换为（并在其后紧邻新增 `askSyncReset`）：

```swift
private func applyAlertThreshold(_ bytes: UInt64?, persist: Bool) {
    // 设置实际阈值时询问是否同步清零全部累计、重新计量（切「关闭」不问）
    if bytes != nil, askSyncReset() {
        monitor.reset(nil) // onReset 已自动重置告警基线并对齐里程碑
    }
    // 告警进度从设置时刻的流量重新起算（刚重置过则基线为 0）
    alert.setThreshold(bytes, baselineBytes: currentMeteredTotal())
    if persist {
        if let bytes {
            UserDefaults.standard.set(Int64(bytes), forKey: Self.alertDefaultsKey)
            requestNotificationAuthorization()
        } else {
            UserDefaults.standard.removeObject(forKey: Self.alertDefaultsKey)
        }
    }
    refreshAlertMenuStates()
}

/// 设置新告警阈值时询问是否同步重置所有累计流量并重新计量
private func askSyncReset() -> Bool {
    let dialog = NSAlert()
    dialog.messageText = "是否同步重置累计流量？"
    dialog.informativeText = "将清零所有模块（Wi-Fi + iPhone）的累计流量并重新开始计时，速率曲线与里程碑同步归零，告警进度从 0 起算。此操作不可撤销。\n选择「仅设置告警」则保留现有累计与计时，告警进度从当前时刻起算。"
    dialog.addButton(withTitle: "同步重置")
    dialog.addButton(withTitle: "仅设置告警")
    NSApp.activate(ignoringOtherApps: true)
    return dialog.runModal() == .alertFirstButtonReturn
}
```

说明：`selectAlertPreset` 的同值 guard 与 `showCustomAlertThreshold` 的既有流程不动——两类入口都会走到 `applyAlertThreshold`，自动获得一致的弹窗行为；启动恢复 `restoreAlertThreshold` 直接调 `alert.setThreshold`，不受影响。

- [ ] **Step 3: 构建并跑全量自测确认无回归**

Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`
Expected: 构建无报错（新代码不涉及模型层，自测项数不变，全部通过，退出码 0）

- [ ] **Step 4: Commit**

```bash
git add Sources/TrafficMonitor/TrafficMonitorApp.swift
git commit -m "feat: 设置流量告警时可选同步重置所有累计流量"
```

（提交信息末尾附 `Co-Authored-By: Claude Code <noreply@anthropic.com>`）

---

### Task 2: 文档（CHANGELOG 与计量语义说明）

**Files:**
- Modify: `CHANGELOG.md`（`[Unreleased]` 节）
- Modify: `docs/metering-semantics.md:5-10`（「计时口径」节）

**Interfaces:**
- Consumes: 无代码依赖，纯文档
- Produces: 无

- [ ] **Step 1: CHANGELOG `[Unreleased]` 加条目**

把：

```markdown
## [Unreleased]

```

替换为：

```markdown
## [Unreleased]

### 新增 (Added)

- 设置流量告警时弹窗询问是否同步重置所有模块累计流量并重新计量
  （清零累计、重新计时、速率曲线与里程碑归零）；切到「关闭」不询问
```

- [ ] **Step 2: metering-semantics.md 补重置入口一句**

在「计时口径」节末尾（`- 计时窗口与流量累计互相独立……` 一行之后）追加：

```markdown
- 「重置计量」入口有二：主页模块卡片的 ↺ 按钮（单模块），以及设置新流量告警时弹窗选择「同步重置」（全部模块一并清零、重新计时）。
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md docs/metering-semantics.md
git commit -m "docs: 记录设置告警时的同步重置入口与更新日志"
```

（提交信息末尾附 `Co-Authored-By: Claude Code <noreply@anthropic.com>`）

---

### Task 3: 打包并人工目检（需用户参与）

**Files:**
- 无源码改动；产出 `Traffic Monitor.app`（仓库根目录，构建产物不入库）

**Interfaces:**
- Consumes: Task 1 的完整功能
- Produces: 目检结论（通过/问题清单）

- [ ] **Step 1: 打包**

Run: `./scripts/make-app.sh`
Expected: `swift build -c release` 成功，生成 `Traffic Monitor.app`

- [ ] **Step 2: 启动并逐项目检（open "Traffic Monitor.app"，与用户一起确认）**

| # | 操作 | 预期 |
|---|------|------|
| ① | 流量栏 > 流量告警 > 选「500 MB」→ 点「同步重置」 | 弹窗出现；确认后状态栏/主页累计归零、「已运行」重计、速率曲线清空、告警进度 0/500 MB |
| ② | 再选「1 GB」→ 点「仅设置告警」（或按 Esc） | 累计与计时保留；告警进度从当前时刻起算 |
| ③ | 自定义… 输入 3 GB → 点「同步重置」 | 同 ① 行为 |
| ④ | 选「关闭」 | 不弹窗，告警解除 |
| ⑤ | 同步重置后跑流量至超阈值 | 告警按新基线触发；里程碑自新累计起算 |
| ⑥ | 点击当前已选中的预设档位 | 不弹窗（同值 no-op） |

- [ ] **Step 3: 目检通过后清理构建产物**

Run: `rm -rf "Traffic Monitor.app"`
Expected: 仓库根目录无 `.app` 残留

---

## Self-Review 记录

- Spec 覆盖：交互流程/弹窗文案/代码改动/边界行为 → Task 1；测试与验证 → Task 1 Step 1/3 + Task 3；文档 → Task 2。无遗漏。
- 占位符扫描：所有代码步骤均为完整代码，无 TBD/TODO。
- 类型一致性：`askSyncReset() -> Bool`、`monitor.reset(nil)`、`setThreshold(_:baselineBytes:)` 与既有签名一致。
