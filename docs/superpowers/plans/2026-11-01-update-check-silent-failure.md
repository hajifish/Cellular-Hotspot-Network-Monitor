# 实施计划：更新检查静默失败修复

日期：2026-11-01
分支：`fix/update-check-silent-failure`（自 develop）
设计：[2026-11-01-update-check-silent-failure-design.md](../specs/2026-11-01-update-check-silent-failure-design.md)
约束：CLT 工具链（无 Xcode），XCTest/swift-testing 不可用 → 自测内置主程序
Run: `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`

## 批次 0：基线

- [x] develop/main 与远端同步，创建 fix 分支
- [x] 基线自测全绿：**242 项**（2026-11-01，网络相关项按环境跳过）

## 批次 1：失败可见性（TDD）

- [x] `UpdatePresentationTests` 先改预期（红）：`wantsCard(.failed) == true`、`menuCheckTitle(.failed) == "检查更新 · 失败"`、`cardContent(.failed).primary == "重试"` 且 notes 为错误文案
- [x] `UpdatePresentation.swift` 实现（绿）：
  - `wantsCard`：`.failed` → true
  - `menuCheckTitle`：`.failed` → 「检查更新 · 失败」
  - `cardContent`：`.failed` 增加 `primary: "重试"`（按钮动作复用 `updatePrimaryAction` 的 `default → checkNow()`，`HomePageController` 无需改动）
- [x] 自测全绿（红 4 处 → 绿，无回归）

## 批次 2：API 限流降级探测（TDD）

- [x] `UpdateCheckerTests` 新增纯函数断言（红）：`shouldFallbackToRedirectProbe`（403/429 是；超时/500 否）＋ `releaseInfo(fromRedirectURL:)`（v 前缀/无前缀 tag、资产名与下载 URL、非 tag 页 nil）
- [x] `UpdateChecker.swift` 实现（绿）：`fetchLatestRaw` 失败且限流 → `redirectProbe`（GET 网页端点，最终 URL 构造 ReleaseInfo）；解析逻辑独立为 `decodeLatestResponse` 便于直测
- [x] 新增实时集成 `liveRedirectProbe`：真实端点打穿，限流环境下亦成功（正是其存在意义）
- [x] 自测全绿：**262 项**（基线 242，净增 20）

## 批次 2.5：「已是最新」反馈（用户决策 2026-11-01）

- [x] `UpdatePresentationTests`：`menuCheckTitle(.upToDate) == "检查更新 · 已是最新"`；`.idle` 仍为「检查更新」
- [x] `UpdatePresentation.swift`：拆开 `.idle`/`.upToDate` 合并 case
- [x] `UpdateServiceTests`：手动 `checkNow(manual: true)` → upToDate 通知触发；自动（默认参数）→ 静默
- [x] `UpdateService.swift`：`checkNow(manual: Bool = false)`；`upToDateNotifier` 注入点；`postUpToDateNotification`（identifier 不带 `update-` 前缀，点击不跳主页）
- [x] 调用点：`checkUpdatesAction` 与主页「重试」均传 `manual: true`；启动/定时轮询维持默认
- [x] 自测全绿（249 → 262 项含批次 2）

## 批次 3：文档

- [x] `CHANGELOG.md`：`[Unreleased]` 新增两条 Added、一条 Fixed
- [x] 本计划勾选进度；README 无需变更（行为不变，仅失败可见性）

## 批次 4：验证与目检

- [ ] `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` 全绿，对照批次 0 基线项数
- [ ] `scripts/make-app.sh` 打包目检（裸二进制 GUI 会崩，须打包）：
  - 失败可见：断网或限流期打开主页 → 卡片展开显示原因 + 「重试」；菜单「检查更新 · 失败」
  - 降级探测：限流期（API 403）点检查更新 → 菜单「检查更新 · 有新版本」（当前 0.5.0 已是 latest，应为「已是最新」的静默路径；确认无回归即可，降级发现新版逻辑以纯函数与实时集成测试为准）
- [ ] 回归：告警弹窗、通知、主页其余卡片不受影响
