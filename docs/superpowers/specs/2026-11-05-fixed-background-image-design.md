# 主页背景图固化 — 设计文档

日期：2026-11-05
状态：已确认（呈现方式、强制打包语义经用户批准）

## 背景与目标

主页窗口背景目前是 `NSVisualEffectView(.hudWindow)` 深色玻璃（`HomePageController.buildUI`）。本功能将背景**固化**为指定图片：无任何用户配置项，资源随包分发，打包脚本强制校验，运行时缺失即 fail-fast。

图片来源：LLM-Token-Usage-Monitor-Desktop 仓库的 `public/default-background.png`（1440×1200，8-bit RGBA，蓝青色调重度模糊，中等亮度），入本仓库为 `Assets/default-background.png`。同为本人项目资产，无第三方许可问题。

## 呈现方式（用户已确认）

图片 aspect-fill 铺满窗口 + 黑色半透明遮罩（初始 50%，目检按白字可读性微调）；现有卡片仍为白色 6% 半透明 `NSBox` 浮于遮罩之上，整体延续深色仪表盘风格。

## 方案对比（含否决项）

| 方案 | 结论 |
|---|---|
| **CALayer 直接渲染**（`layer.contents` + `contentsGravity = .resizeAspectFill`） | **采用**。约 30 行；窗口变高变矮时自动跟随填充，零布局代码 |
| `NSImageView` | 否决：原生只有 fit/拉伸，无 aspect-fill，需手算裁剪 frame 且 resize 需同步 |
| 手写 `draw(_:)` | 否决（保留为备选）：代码量最大，每次 resize 全量重绘。若层备份视图上 `layer.contents` 被 AppKit 清除（罕见），退回此方案并提取 `aspectFillRect(imageSize:in:)` 纯函数补自测 |
| 保留 `NSVisualEffectView` 其上叠图 | 否决：玻璃被全幅图片完全遮盖，多一层无用视图 |
| 加载失败回退玻璃背景 | **用户明确否决**：改为打包强制 + 运行时 fatalError，见下 |

## 设计

### 资源与打包（强制）

- 图片入 git：`Assets/default-background.png`（设计资产，区别于 `.build/` 下的生成物 icns）；
- `make-app.sh` 增加 `cp Assets/default-background.png "$APP/Contents/Resources/"`。脚本已有 `set -euo pipefail`，源文件缺失**打包直接失败**；
- `package-release.sh` 经 `make-app.sh` 构建，自动继承校验。

### 渲染（`HomePageController.buildUI`）

- 新增 `DashboardBackgroundView: NSView`（`wantsLayer = true`）：
  - 根层：`layer.contents = CGImage`、`contentsGravity = .resizeAspectFill`、`masksToBounds = true`；
  - 遮罩：黑色 `alpha ≈ 0.5` 的铺满子视图（autoresizing 跟随），加在所有 UI 之前；
- contentView 由 `NSVisualEffectView` 换为 `DashboardBackgroundView`，现有全部子视图 addSubview 顺序不变；
- 窗口 `titled + fullSizeContentView + titlebarAppearsTransparent` 维持，系统圆角/阴影不变。

### 加载（运行时强制，无回退）

```swift
guard let url = Bundle.main.url(forResource: "default-background", withExtension: "png"),
      let image = NSImage(contentsOfFile: url.path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("背景图资源缺失：打包不完整") }
```

打包脚本已保证存在，仅损坏包触发。自测路径在 GUI 启动前 `exit`（`TestSupport.swift`），不受影响。

### 尺寸适配

窗口基础 720×470；收起速率图表 −126（→344），展开更新卡 +84（→554）。`contentsGravity` 自动适配，无布局代码。图片 1.2:1 vs 窗口 1.53:1，aspect-fill 上下裁切，模糊图裁切无视觉损失。

## 边界行为

- 遮罩浓度以目检微调为准（初值 0.5）；
- `swift run` 裸跑 GUI 本就崩溃（既有事实），fail-fast 不引入新行为；
- 菜单栏（纯文字）、告警弹窗（系统 NSAlert 样式）不受影响。

## 测试与验证

- **自测**：无新增项——CALayer 方案下无可测纯函数，布局语义由 `contentsGravity` 承担（若实现退回 `draw(_:)` 方案，则补 `aspectFillRect` 自测）；
- **目检**（`make-app.sh` 打包后）：① 图片铺满、无变形拉伸 ② 白字（图例、次要灰字）可读 ③ 收起图表/展开更新卡时背景自动填充无拉伸 ④ 菜单栏与告警弹窗不受影响；
- **打包校验目检**：临时移走 `Assets/default-background.png` 跑 `make-app.sh`，确认脚本失败退出；
- **文档**：CHANGELOG `[Unreleased]` 加条目。

## 追加需求（2026-11-05 用户确认）：里程碑提示门控

**现状**：`MilestoneTracker` 自上次重置起每满 1 GB 发一条系统通知（`checkMilestone()` 每秒驱动），与告警状态无关。

**新语义**：仅当告警阈值已设置（`alert.threshold != nil`）时才发每 GB 提示；告警关闭则该功能整体取消：

- 关闭期间 tracker 不推进（不调 `update`），状态冻结；
- 重新设置告警（nil → 非 nil）时 `resync` 到当前总量之上的第一个整 GB——关闭期间消耗的 GB 不补发通知；
- 启动恢复（`restoreAlertThreshold`）出非 nil 阈值时同样 `resync`——顺带消除重启后按持久化累计补发旧里程碑的既有怪癖；
- 同步重置路径（`applyAlertThreshold` syncReset）复位后 `resync(0)` → 1 GB 起步，与 `onReset` 既有行为一致（幂等）。

**实现**（沿用静态编排函数模式，对齐 `applyAlertThreshold`）：

```swift
/// 里程碑门控：告警未设置则整体静默（tracker 冻结不推进）
static func milestoneReached(totalBytes: UInt64, alertThreshold: UInt64?,
                             tracker: inout MilestoneTracker) -> UInt64?
```

- `applyAlertThreshold` 增加 `milestone: inout MilestoneTracker` 参数，`bytes != nil` 时在 tick/重置之后 `resync(meteredTotal)`；
- `checkMilestone()`/`restoreAlertThreshold()` 改走上述静态函数/直接 resync。

**自测**（TrafficMonitorAppTests）：门控静默且 tracker 冻结、阈值已设时正常越界报告、设阈值（不重置/同步重置）后里程碑对齐、关闭不动里程碑。

## 明确不做

- 背景图可配置/用户自选（“固化”语义，无偏好项）；
- 菜单栏、告警弹窗的背景定制；
- 图片运行时预处理（缩放缓存等，720pt 窗口直接渲染无压力）；
- 里程碑步长/开关的独立偏好项（完全跟随告警设置，无独立入口）。
