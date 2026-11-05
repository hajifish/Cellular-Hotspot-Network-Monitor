# 主页背景固化 + 里程碑门控 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 主页背景固化为内置图片（打包强制、运行时 fail-fast）；每 GB 里程碑提示改为仅在设置流量告警时启用。

**Architecture:** ①新 `DashboardBackgroundView`（CALayer `contents + .resizeAspectFill` + 黑色遮罩子视图）替换 `HomePageController` 的 `NSVisualEffectView`；图片经 `make-app.sh` 强制拷入 `Contents/Resources/`。②里程碑门控沿用项目「静态编排函数 + SelfTest」模式：新增 `MenuBarController.milestoneReached(totalBytes:alertThreshold:tracker:)`，`applyAlertThreshold` 增加 `inout MilestoneTracker` 参数负责设阈值时 resync。

**Tech Stack:** Swift 5.9 + AppKit（仅 CLT 工具链，无 Xcode；测试 = `TRAFFICMONITOR_SELFTEST=1` 内置自测）。

**Spec:** `docs/superpowers/specs/2026-11-05-fixed-background-image-design.md`（含 2026-11-05 追加的里程碑门控一节）

## Global Constraints

- 分支：`feature/fixed-background-image`（已创建，勿动 develop/main）
- 本机无 Xcode：不可用 XCTest/swift-testing/SwiftUI；自测唯一入口 `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`，exit 0 = 全过
- GUI 目检必须先 `./scripts/make-app.sh` 打包（裸二进制 GUI 会崩）
- 提交信息末尾加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`
- 用户已授权：执行全程不再向用户提问，遇到问题按 spec 的备选方案自行处置

---

### Task 1: 里程碑门控（TDD）

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（`applyAlertThreshold` 静态编排函数 ~346 行、实例包装 ~359 行、`restoreAlertThreshold` ~321 行、`checkMilestone` ~459 行）
- Test: `Sources/TrafficMonitor/SelfTest/TrafficMonitorAppTests.swift`

**Interfaces:**
- Consumes: `MilestoneTracker.update(totalBytes:) -> UInt64?`、`resync(totalBytes:)`、`next: UInt64`（`private(set)` 可读）、`step: UInt64`
- Produces: `MenuBarController.milestoneReached(totalBytes: UInt64, alertThreshold: UInt64?, tracker: inout MilestoneTracker) -> UInt64?`；`MenuBarController.applyAlertThreshold(_:syncReset:monitor:alert:milestone:)`（新增尾参 `milestone: inout MilestoneTracker`）

- [ ] **Step 1: 基线自测**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor >/tmp/selftest.log 2>&1; echo "exit=$?"; tail -2 /tmp/selftest.log`
Expected: `exit=0`，0 failures（记下总条数，最后一步对比应 +5）

- [ ] **Step 2: 签名扩展（纯机械，无行为变化）**

`TrafficMonitorApp.swift` 静态 `applyAlertThreshold`（替换原函数，含文档注释）：

```swift
    /// 应用告警阈值的编排核心（静态编排函数：不依赖 UI/持久化，会修改传入的 monitor/alert/milestone，自测直接调用）：
    /// 实际阈值 + 同步重置 → 先补一拍结算（模态弹窗期间采样停摆），再清零全部累计、以 0 为告警基线；
    /// 仅设置告警 → 保留累计并将全部当前累计计入新告警进度；
    /// bytes 为 nil（切「关闭」）时无论 syncReset 为何都不得动累计（守卫）；
    /// 设置实际阈值时里程碑对齐当前总量（关闭期间冻结的里程碑不补发旧通知，2026-11-05 需求）
    static func applyAlertThreshold(_ bytes: UInt64?, syncReset: Bool,
                                    monitor: TrafficMonitor, alert: TrafficAlert,
                                    milestone: inout MilestoneTracker) {
        if bytes != nil {
            // 调用前可能经历了 runModal 模态（采样定时器停摆）；
            // 先补一拍把这段时间的流量结算进旧周期，再重置/读基线
            monitor.tick()
        }
        if let bytes, syncReset {
            monitor.reset(nil)
        }
        alert.setThreshold(bytes, baselineBytes: syncReset ? meteredTotal(of: monitor) : 0)
        if bytes != nil {
            milestone.resync(totalBytes: meteredTotal(of: monitor))
        }
    }
```

实例包装（原 362 行）改为：

```swift
        Self.applyAlertThreshold(bytes, syncReset: syncReset, monitor: monitor, alert: alert,
                                  milestone: &milestoneTracker)
```

`TrafficMonitorAppTests.swift` 中 5 处现有调用（`applyAlertThresholdKeepsTotalsWhenDecliningReset` / `...CountsExistingUsageWhenDecliningReset` / `...SyncResetZeroesTotalsAndBaseline` / `...KeepsTotalsWhenDisabling` / `...SettlesDialogTrafficBeforeReset`）逐一做同一机械修改——调用前加一行声明、调用处加尾参：

```swift
        var milestone = MilestoneTracker()
        MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: false,
                                              monitor: monitor, alert: alert,
                                              milestone: &milestone)
```

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor >/tmp/selftest.log 2>&1; echo "exit=$?"`
Expected: `exit=0`（尚无行为变化）

- [ ] **Step 3: 写失败测试**

`TrafficMonitorAppTests.swift`——`all()` 改为：

```swift
    static func all() {
        applyAlertThresholdKeepsTotalsWhenDecliningReset()
        applyAlertThresholdCountsExistingUsageWhenDecliningReset()
        applyAlertThresholdSyncResetZeroesTotalsAndBaseline()
        applyAlertThresholdKeepsTotalsWhenDisabling()
        applyAlertThresholdSettlesDialogTrafficBeforeReset()
        alertResetRequiresExplicitConfirmation()
        milestoneReachedSilentAndFrozenWithoutThreshold()
        milestoneReachedReportsCrossingsWhenArmed()
        applyAlertThresholdResyncsMilestoneOnArm()
        applyAlertThresholdSyncResetRestartsMilestoneFromOneGB()
        applyAlertThresholdLeavesMilestoneWhenDisabling()
    }
```

文件末尾追加测试体：

```swift
    /// 告警未设置：越过边界也不提示，且 tracker 冻结（next 不推进）
    static func milestoneReachedSilentAndFrozenWithoutThreshold() {
        var tracker = MilestoneTracker()
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 2_500_000_000,
                                                          alertThreshold: nil,
                                                          tracker: &tracker) == nil,
                       "no threshold → milestone silent")
        TestRun.expectEqual(tracker.next, MilestoneTracker.step, "tracker frozen while alert off")
    }

    /// 告警已设置：照常按 1 GB 边界报告
    static func milestoneReachedReportsCrossingsWhenArmed() {
        var tracker = MilestoneTracker()
        tracker.resync(totalBytes: 2_500_000_000) // 对齐到 3 GB 边界
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 3_000_000_000,
                                                          alertThreshold: 10 * MenuBarController.gigabyte,
                                                          tracker: &tracker) == 3 * MenuBarController.gigabyte,
                       "armed → 3GB boundary reported")
        TestRun.expect(MenuBarController.milestoneReached(totalBytes: 3_400_000_000,
                                                          alertThreshold: 10 * MenuBarController.gigabyte,
                                                          tracker: &tracker) == nil,
                       "between boundaries silent")
    }

    /// 设置阈值（不重置）：里程碑对齐到当前总量之上的第一个整 GB
    static func applyAlertThresholdResyncsMilestoneOnArm() {
        let monitor = makeMonitor() // 基线总量 180 字节
        monitor.update(from: [TrafficMonitorTests.sample("en0", .wifi, rx: 2_600_000_000, tx: 0)])
        var milestone = MilestoneTracker()
        _ = milestone.update(totalBytes: 1_200_000_000) // 旧状态停在 next = 2 GB
        let alert = TrafficAlert()
        MenuBarController.applyAlertThreshold(5 * MenuBarController.gigabyte, syncReset: false,
                                              monitor: monitor, alert: alert, milestone: &milestone)
        TestRun.expectEqual(milestone.next, 3 * MilestoneTracker.step,
                            "armed resyncs to first full GB above total")
    }

    /// 设置阈值 + 同步重置：累计清零，里程碑从 1 GB 重新起步
    static func applyAlertThresholdSyncResetRestartsMilestoneFromOneGB() {
        let monitor = makeMonitor()
        var milestone = MilestoneTracker()
        _ = milestone.update(totalBytes: 2_600_000_000)
        let alert = TrafficAlert()
        MenuBarController.applyAlertThreshold(MenuBarController.gigabyte, syncReset: true,
                                              monitor: monitor, alert: alert, milestone: &milestone)
        TestRun.expectEqual(milestone.next, MilestoneTracker.step, "sync reset → 1GB restart")
    }

    /// 切「关闭」：里程碑不动（保持冻结）
    static func applyAlertThresholdLeavesMilestoneWhenDisabling() {
        let monitor = makeMonitor()
        var milestone = MilestoneTracker()
        milestone.resync(totalBytes: 5_500_000_000) // next = 6 GB
        let alert = TrafficAlert()
        alert.setThreshold(MenuBarController.gigabyte, baselineBytes: 0)
        MenuBarController.applyAlertThreshold(nil, syncReset: false,
                                              monitor: monitor, alert: alert, milestone: &milestone)
        TestRun.expectEqual(milestone.next, 6 * MilestoneTracker.step, "disable leaves milestone frozen")
    }
```

- [ ] **Step 4: 跑测试确认失败**

Run: `swift build 2>&1 | tail -3`
Expected: 编译错误 `type 'MenuBarController' has no member 'milestoneReached'`（RED）

- [ ] **Step 5: 实现门控**

`TrafficMonitorApp.swift`——`checkMilestone()`（原 459-461 行区域）改为：

```swift
    /// 每 1 GB 里程碑：自上次重置起累计每满 1 GB 提醒一条；
    /// 仅在设置了流量告警时启用（2026-11-05 需求），关闭告警即整体静默
    private func checkMilestone() {
        let totalBytes = currentMeteredTotal()
        guard let reached = Self.milestoneReached(totalBytes: totalBytes,
                                                  alertThreshold: alert.threshold,
                                                  tracker: &milestoneTracker) else { return }
```

（其后 `let gb = ...` 通知代码不变。）

同文件新增静态门控函数（放在 `checkMilestone` 上方）：

```swift
    /// 里程碑门控（静态编排）：告警未设置 → 整体静默且 tracker 冻结不推进；
    /// 已设置 → 透传 tracker.update（返回本次越过的边界，无则 nil）
    static func milestoneReached(totalBytes: UInt64, alertThreshold: UInt64?,
                                 tracker: inout MilestoneTracker) -> UInt64? {
        guard alertThreshold != nil else { return nil }
        return tracker.update(totalBytes: totalBytes)
    }
```

`restoreAlertThreshold()` 整体替换为：

```swift
    private func restoreAlertThreshold() {
        // 诊断/验证用：启动即设一个极低阈值（如 TRAFFICMONITOR_ALERT_MB=1）
        if let debugMB = ProcessInfo.processInfo.environment["TRAFFICMONITOR_ALERT_MB"],
           let value = Double(debugMB), value > 0 {
            alert.setThreshold(UInt64(value * Double(Self.megabyte)), baselineBytes: 0)
            milestoneTracker.resync(totalBytes: currentMeteredTotal())
            return
        }
        let stored = UserDefaults.standard.object(forKey: Self.alertDefaultsKey) as? Int64
        alert.setThreshold(stored.map { UInt64(max(0, $0)) }, baselineBytes: 0)
        if alert.threshold != nil {
            // 启动恢复即视为「已设置」：里程碑对齐当前累计，不按持久化旧量补发（2026-11-05）
            milestoneTracker.resync(totalBytes: currentMeteredTotal())
        }
    }
```

- [ ] **Step 6: 跑测试确认通过**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor >/tmp/selftest.log 2>&1; echo "exit=$?"; grep -ci "fail" /tmp/selftest.log; tail -2 /tmp/selftest.log`
Expected: `exit=0`，总条数 = 基线 + 5

- [ ] **Step 7: 提交**

```bash
git add Sources/TrafficMonitor/TrafficMonitorApp.swift Sources/TrafficMonitor/SelfTest/TrafficMonitorAppTests.swift
git commit -m "feat: 里程碑提示仅在设置告警时启用

告警关闭期间 tracker 冻结、重新设置后自下一个整 GB 起提醒；
启动恢复同样对齐，消除重启后按持久化累计补发旧里程碑。

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: 背景图资源与打包强制

**Files:**
- Create: `Assets/default-background.png`（复制自 `/Users/shin/dev/LLM-Token-Usage-Monitor-Desktop/public/default-background.png`）
- Modify: `scripts/make-app.sh:13`（icns 拷贝行之后）

**Interfaces:**
- Produces: 运行时资源名 `default-background`（png），位于 `.app/Contents/Resources/`，供 Task 3 的 `DashboardBackgroundView.loadBundledImage()` 读取

- [ ] **Step 1: 入库图片**

```bash
mkdir -p Assets
cp /Users/shin/dev/LLM-Token-Usage-Monitor-Desktop/public/default-background.png Assets/default-background.png
file Assets/default-background.png
```
Expected: `PNG image data, 1440 x 1200, 8-bit/color RGBA, non-interlaced`

- [ ] **Step 2: 打包脚本强制拷贝**

`scripts/make-app.sh` 在 `cp ".build/AppIcon.icns" ...` 行后加：

```bash
cp "Assets/default-background.png" "$APP/Contents/Resources/default-background.png"
```

（脚本已有 `set -euo pipefail`：源文件缺失 → cp 失败 → 打包以非零退出。负向验证在 Task 4。）

- [ ] **Step 3: 提交**

```bash
git add Assets/default-background.png scripts/make-app.sh
git commit -m "feat: 打包内置主页背景图（缺失即打包失败）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: 主页背景渲染

**Files:**
- Create: `Sources/TrafficMonitor/DashboardBackgroundView.swift`
- Modify: `Sources/TrafficMonitor/HomePageController.swift:3`（类文档注释）、`:100-106`（buildUI 开头）

**Interfaces:**
- Consumes: Task 2 的资源名 `default-background`
- Produces: `DashboardBackgroundView(frame:image:)`、`DashboardBackgroundView.loadBundledImage() -> CGImage`、`DashboardBackgroundView.scrimAlpha: CGFloat`

- [ ] **Step 1: 新建 DashboardBackgroundView.swift**

```swift
import AppKit

/// 主页固化背景：内置图片 aspect-fill 铺满（contentsGravity 自适应窗口高矮变化），
/// 其上叠黑色半透明遮罩保证白字可读。图片由 make-app.sh 强制打包进
/// Contents/Resources，缺失即视为打包损坏，fail-fast、无回退路径。
final class DashboardBackgroundView: NSView {
    /// 遮罩浓度：蓝青中亮背景图上的白字可读性（目检标定；0 = 无遮罩）
    static let scrimAlpha: CGFloat = 0.5

    init(frame: NSRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        let scrim = NSView()
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.scrimAlpha).cgColor
        scrim.autoresizingMask = [.width, .height]
        addSubview(scrim) // 最先加入：后续所有 UI 子视图都叠在遮罩之上
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 加载打包内置背景图；缺失 = 打包不完整，直接崩溃
    /// （自测路径在 GUI 启动前 exit，不受影响；裸二进制 GUI 本就不可运行）
    static func loadBundledImage() -> CGImage {
        guard let url = Bundle.main.url(forResource: "default-background", withExtension: "png"),
              let image = NSImage(contentsOfFile: url.path)?
                  .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fatalError("背景图资源缺失：打包不完整（应有 Contents/Resources/default-background.png）")
        }
        return image
    }
}
```

- [ ] **Step 2: HomePageController 接入**

类文档注释（第 3 行）改为：

```swift
/// 主页窗口：固化图片背景仪表盘（aspect-fill + 深色遮罩），左列（汇总条 + 接口卡片堆叠）+ 右侧总累计告警圆环 + 可折叠的 120 秒速率图
```

buildUI 开头（原 100-106 行）替换为：

```swift
    private func buildUI() {
        // 固化背景：内置图片 aspect-fill + 黑色遮罩（2026-11-05 需求，替代原 hudWindow 玻璃）
        let content = DashboardBackgroundView(frame: NSRect(x: 0, y: 0, width: 720, height: 470),
                                              image: DashboardBackgroundView.loadBundledImage())
        window.contentView = content
```

（其后 `content.addSubview(...)` 等全部不动——局部变量名保持 `content`。）

- [ ] **Step 3: 构建 + 自测回归**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor >/tmp/selftest.log 2>&1; echo "exit=$?"; tail -2 /tmp/selftest.log`
Expected: `exit=0`（无纯函数改动，条数不变）

- [ ] **Step 4: 打包 + 目检**

```bash
./scripts/make-app.sh
(TRAFFICMONITOR_SHOWHOME=1 "./Traffic Monitor.app/Contents/MacOS/TrafficMonitor" >/tmp/tm-run.log 2>&1 & echo $! >/tmp/tm-bg.pid)
sleep 3
screencapture -x /tmp/tm-bg-check.png
kill "$(cat /tmp/tm-bg.pid)" 2>/dev/null || true
```

然后 Read `/tmp/tm-bg-check.png` 逐项核对：
① 背景为蓝青色模糊图铺满窗口（非纯黑/纯玻璃）② 无变形拉伸 ③ 白字（图例、卡片标题）可读 ④ 窗口圆角正常。
若背景空白/黑色（层备份视图 `layer.contents` 被 AppKit 清除的罕见情形）→ 执行下方备选实现后重跑本步。

**备选实现（draw 版，替换 Step 1 文件内容）：**

```swift
import AppKit

/// 主页固化背景（draw 实现）：图片 aspect-fill + 黑色遮罩。
final class DashboardBackgroundView: NSView {
    static let scrimAlpha: CGFloat = 0.5
    private let image: CGImage

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// aspect-fill 目标矩形（纯函数）：图片等比缩放至完全覆盖 bounds，居中裁切
    static func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ rect: NSRect) {
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.clip(to: bounds)
        ctx?.draw(image, in: Self.aspectFillRect(imageSize: CGSize(width: image.width, height: image.height),
                                                 in: bounds))
        ctx?.restoreGState()
        NSColor.black.withAlphaComponent(Self.scrimAlpha).setFill()
        bounds.fill()
    }

    static func loadBundledImage() -> CGImage {
        guard let url = Bundle.main.url(forResource: "default-background", withExtension: "png"),
              let image = NSImage(contentsOfFile: url.path)?
                  .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fatalError("背景图资源缺失：打包不完整（应有 Contents/Resources/default-background.png）")
        }
        return image
    }
}
```

（采用备选实现时，同步在 `MilestoneTrackerTests.swift` 同级补 `aspectFillRect` 自测并注册到 `SelfTest.run()`，保持「纯函数，可测」约定。）

- [ ] **Step 5: 提交**

```bash
git add Sources/TrafficMonitor/DashboardBackgroundView.swift Sources/TrafficMonitor/HomePageController.swift
git commit -m "feat: 主页背景固化为内置图片

CALayer resizeAspectFill 铺满 + 黑色 50% 遮罩，替代 hudWindow 玻璃；
图片缺失即 fatalError（打包脚本已保证存在）。

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: 打包负向校验 + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`（`[Unreleased]` 节）

**Interfaces:**
- Consumes: Task 2 的打包脚本、Task 1+3 的全部改动

- [ ] **Step 1: 负向校验（打包缺图必须失败）**

```bash
mv Assets/default-background.png /tmp/default-background.png
./scripts/make-app.sh >/tmp/make-app-neg.log 2>&1; echo "exit=$?"
mv /tmp/default-background.png Assets/default-background.png
tail -2 /tmp/make-app-neg.log
```
Expected: `exit≠0`，日志含 `cp: ... Assets/default-background.png: No such file or directory`（release 构建有缓存时很快）

- [ ] **Step 2: 正向复核**

Run: `./scripts/make-app.sh && ls -la "Traffic Monitor.app/Contents/Resources/"`
Expected: 末尾打印 `Built ./Traffic Monitor.app`；Resources 下同时有 `AppIcon.icns` 与 `default-background.png`

- [ ] **Step 3: CHANGELOG**

`[Unreleased]` 节填入：

```markdown
## [Unreleased]

### 新增 (Added)

- 主页背景固化为内置蓝青色模糊图（aspect-fill 铺满 + 半透明深色遮罩）；图片由打包脚本强制内置，缺失直接打包失败

### 变更 (Changed)

- 每 GB 里程碑提示改为仅在设置了流量告警时启用：关闭告警即停用（关闭期间冻结不推进、用量不补发提醒）；重新设置告警后自当前累计的下一个整 GB 起继续提醒（重启恢复亦对齐，不再按持久化累计补发旧里程碑）
```

- [ ] **Step 4: 提交**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG 记录背景固化与里程碑门控

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## 完成标准

- `TRAFFICMONITOR_SELFTEST=1` exit 0，条数 = 基线 + 5（或备选实现 +6）
- 打包目检 4 项全过（或备选实现后重跑全过）
- 负向校验 exit ≠ 0，正向打包产物含背景图
- 分支上 4 个提交（里程碑门控 / 资源+脚本 / 渲染 / CHANGELOG），spec 已含追加需求
- **不推送、不建 PR**（发布/合并由用户另行触发）
