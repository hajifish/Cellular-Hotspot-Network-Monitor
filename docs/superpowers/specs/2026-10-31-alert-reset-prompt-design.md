# 设置流量告警时可选同步重置计量 — 设计文档

日期：2026-10-31
状态：已确认（设计经用户逐节批准）

## 背景与目标

设置新告警阈值时，计量口径常需要同步翻新（如新的计费周期）。当前「设告警」与「重置计量」是两个割裂的操作，用户要分别去菜单和主页操作。本功能在每次设置新告警阈值时询问是否同步重置所有累计流量并重新计量。

## 交互流程

```
用户设置新告警阈值（非「关闭」）
  ├─ 预设档位：点击与当前不同的档位
  └─ 自定义：输入有效值并点「设置」
        ↓
弹窗询问（NSAlert，每次都问）
  ├─ 「同步重置」→ monitor.reset(nil) → 设新阈值（基线 = 0）
  └─ 「仅设置告警」→ 只设新阈值（基线 = 当前总量，现状行为）
```

不弹问的情形：

- 切到「关闭」：仅解除告警，无重置语义；
- 预设点击当前已选档位：现有 guard 直接 return；
- 启动恢复（`restoreAlertThreshold`）与 `TRAFFICMONITOR_ALERT_MB` 调试路径：直接 `setThreshold`，不经此流程。

## 弹窗文案（对齐主页重置弹窗风格）

- **messageText**：`是否同步重置累计流量？`
- **informativeText**：`将清零所有模块的累计流量并重新开始计时，速率曲线与里程碑同步归零，告警进度从 0 起算。此操作不可撤销。\n选择「仅设置告警」则保留现有累计与计时，告警进度从当前时刻起算。`
- **按钮**：`同步重置`（第一按钮，回车）/ `仅设置告警`（Esc）——与「确认重置」「立即重启」的主动作居首惯例一致。

## 代码改动（初版：TrafficMonitorApp.swift，约 30 行；后续演进见本节末）

```swift
private func applyAlertThreshold(_ bytes: UInt64?, persist: Bool) {
    if bytes != nil, askSyncReset() {
        monitor.reset(nil)   // reset 本体清速率历史；onReset 自动：告警基线挪到新总量、里程碑对齐
    }
    alert.setThreshold(bytes, baselineBytes: currentMeteredTotal()) // 重置后总量为 0，基线自然为 0
    // persist 与 refreshAlertMenuStates 维持现状
}

private func askSyncReset() -> Bool { /* NSAlert，文案见上 */ }
```

要点：

- **先 reset 后 set**：`onReset` 会把告警基线挪到新总量（0），随后的 `setThreshold(baselineBytes: currentMeteredTotal())` 取到的也是 0，顺序天然无 bug；
- 里程碑、通知、状态栏刷新全部走现有 `onReset` + observer 机制，零额外代码；
- 不改 `TrafficAlert`、`TrafficMonitor`、`UsageStore` 任何模型代码。
- **后续演进（Issue #10 / #12）**：编排核心提取为静态函数 `MenuBarController.applyAlertThreshold(_:syncReset:monitor:alert:)` 并补自测；模态弹窗返回后由编排函数先 `monitor.tick()` 结算弹窗期流量，再重置/读基线。详见 `docs/superpowers/plans/2026-10-31-issues-10-15-batch.md`；上方代码块为初版设计快照。

## 边界行为

- 累计为 0 时也照常弹问（「每次都问」，行为可预期；此时「同步重置」仅重启计时）；
- 「同步重置」选择不持久化，下次设置照常再问；
- 自定义重设同值：保留现有「重新武装」语义（清除已触发状态、基线重算），照常弹问。

## 测试与验证

- **自测**：模型层语义已有覆盖（`resetZeroesRatesAndStore`、`setThresholdRearmsFromNewBaseline`、`resetRebasesToCurrentTotal`、`onReset notified`）。初版判定为 UI 编排、无新增自测项；Issue #12 后已将编排核心提取为静态函数，新增 `TrafficMonitorAppTests`（12 条断言，覆盖守卫、阈值写入、基线口径、曲线归零、onReset 与弹窗期结算）；
- **目检**：`make-app.sh` 打包后验证：① 预设 + 同步重置 ② 预设 + 仅设置 ③ 自定义 + 同步重置 ④ 切「关闭」不弹 ⑤ 同步重置后里程碑自新累计起算、状态栏与主页归零；
- **文档**：CHANGELOG `[Unreleased]` 加条目；`docs/metering-semantics.md` 计时口径节补「设置告警时的同步重置」入口一句。

## 明确不做

- 重置选择的持久化/记忆（每次都问）；
- 常驻偏好项或自定义弹窗内嵌复选框（已在方案对比中否决）；
- 为弹窗流程引入可测协调层（方案 B，改动面与回归风险不成比例；Issue #12 改用静态编排函数提取这一更轻的形式）。
