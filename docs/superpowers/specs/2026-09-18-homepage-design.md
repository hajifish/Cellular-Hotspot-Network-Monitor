# 主页窗口 — 设计文档

日期：2026-09-18
状态：已定稿（用户授权免确认，按偏好压缩流程）

## 目标

为主页增加一个独立窗口，展示比菜单栏更全面的流量信息。保持简洁：无进程明细、无持久化历史。

## 内容

1. **总览行**：开始时间、已运行时长。
2. **两张接口卡片**（Wi-Fi、iPhone）：接口 BSD 名、当前 ↑↓ 速率、累计 ↑↓ 字节。
3. **实时速率滚动曲线**：最近 120 秒，上传/下载两条折线，右端对齐最新值。
4. 菜单新增「打开主页 ⌘0」；窗口关闭仅隐藏，再次打开复用。

## 架构

- `RateHistory`（新，纯逻辑）：固定 120 条的环形缓冲，每秒一条 (rxDelta, txDelta)；由 `TrafficMonitor.update(from:)` 每秒喂入；`reset()` 时清空。可单测。
- `HomePageController`（新）：NSWindow + NSViewController；顶部总览 NSTextField；两张 NSBox 卡片；`RateGraphView` 自绘。持有 monitor 引用，订阅 `onChange` 刷新；`menuNeedsUpdate` 时同步一次。
- `RateGraphView`（新，NSView 子类）：`draw(_:)` 画双折线，x 轴为时间（右=最新），y 轴自适应最大值；浅色/深色模式用系统语义色。
- `MenuBarController`：新增「打开主页」菜单项与控制器持有/显示逻辑。

## 数据流

`Timer(1s) → update(from:) → UsageStore + RateHistory → onChange → HomePage 刷新（文字 + 重绘）`

## 明确不做

进程级流量（需 NetworkExtension 权限）、跨启动持久化、每日统计、图表缩放交互。

## 测试

`RateHistory` 的推入/窗口长度/最新值/重置清空 + `TrafficMonitor` 喂数据后 history 增长（进内置 SelfTest）；UI 不做单测，运行后用 `CGWindowListCopyWindowInfo` 验证窗口存在。
