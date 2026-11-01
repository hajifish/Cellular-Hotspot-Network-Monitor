# 更新检查静默失败修复设计 — 失败可见性 + API 限流降级探测

日期：2026-11-01
状态：待确认
前置设计：[2026-10-29-auto-update-design.md](2026-10-29-auto-update-design.md)（本次为其失败处理矩阵与限额假设的修订）

## 背景（本次事故时间线）

1. v0.5.0（含「设置告警时可选同步重置累计流量」功能）于 2026-10-31 23:59 发布。
2. 本机运行 0.4.0，启动 10s 首查 + 每 6h 轮询 + 手动「检查更新」全部命中 GitHub API **403 限流**：机器出口为共享 VPN 节点，未认证 API 配额（60 次/时/IP）长期被共用者耗尽（实测 `x-ratelimit-remaining: 0`）。
3. 403 → `.failed` 状态在 UI 上**完全不可见**：菜单标题对 `.failed` 与 `.idle` 同文案；主页卡片 `wantsCard(.failed)` 返回 false 整体收起（`cardContent(.failed)` 准备好的错误文案永远不可达）；失败不发系统通知。
4. 用户感知为「检查更新点了没反应」「新功能丢失」，实际是 0.4.0 从未升级。

前置设计的两处假设被本次事故推翻：

- 失败处理矩阵「API 超时 / 断网 / 403 限流 → 计入 failed，**主页显示原因 + 重试**」——**主页显示原因未实现**（卡片被收起），属实现与设计背离，本次恢复。
- 「无鉴权 API 限额 60 次/时/IP，每实例每天约 4 次检查绰绰有余」——共享出口 IP 场景下该假设不成立，需降级通道。

## 决策记录

| 决策点 | 结论 |
|---|---|
| 失败可见性（主页） | `wantsCard(.failed)` 改为 true：检查失败时展开主页卡片，显示错误原因 + 「重试」主按钮（恢复前置设计矩阵原意；按钮复用现有 `updatePrimaryAction` 的 `default → checkNow()` 分支，零接线） |
| 失败可见性（菜单） | `menuCheckTitle(.failed)` → 「检查更新 · 失败」。对 2026-10-30「菜单栏不展示任何更新内容」决策的再放宽：available 状态已有「· 有新版本」先例，且菜单仅在用户下拉时可见，非常驻打扰 |
| 限流降级通道 | API 命中 403/429 时，二段探测 `GET https://github.com/{repo}/releases/latest`（**网页端点，不走 API 配额**）：URLSession 默认跟随 302，最终 `response.url` 形如 `…/releases/tag/{tagName}`，从中解析 tag |
| 降级通道的 ReleaseInfo | 构造最小信息：`tagName` = 解析值；`htmlUrl` = tag 页；`body` = nil（发布说明不可得，卡片备注自动回退为「上次检查时间」）；`assets` = 按命名规则构造的单个 zip（`TrafficMonitor-{去v版本}.zip`，下载地址 `releases/download/{tag}/…`），与 `selectAsset` 的优先匹配规则及打包工作流的确定性命名一致 |
| 降级失败的口径 | 探测自身也失败（断网等）→ 传播探测的错误文案计入 `.failed`（此时失败已可见，不再静默） |
| upToDate 的手动反馈 | 菜单条目标题 `.upToDate` → 「检查更新 · 已是最新」（与「· 有新版本」「· 失败」同一套口径）；**仅手动触发**的检查得出 upToDate 时额外发一条系统通知「已是最新版本 x.y.z」（用户决策 2026-11-01）。自动检查（启动 10s / 每 6h）静默，不打扰；通知 identifier 不带 `update-` 前缀，点击不跳主页（无内容可看） |
| 自动检查退避/抖动、ETag 条件请求、认证请求 | **不做**。降级通道已消除配额依赖；认证需嵌入凭据不现实 |

## 兼容性与风险

| 风险 | 评估 |
|---|---|
| 构造的下载 URL 指向不存在的资产（CI 打包失败/未上传） | 下载失败回到 `available` 并显示错误，可重试或打开发布页；资产命名由 `package-release.sh` 确定，确定性高 |
| 网页端点探测被网络环境拦截 | 计入 `.failed` 且可见；两条通道全断时错误文案如实展示 |
| `ReleaseAsset.size` 未知（填 0） | 下载进度用响应 `content-length` 实测值，`size` 字段仅作展示/测试，无消费者 |
| 版本校验 | `stageApp(expectedVersion:)` 用 `numericComponents` 比较，tag 带 `v` 与包内无 `v` 一致（已验证），降级通道构造的 tag 原样透传，不受影响 |

## 测试（并入 `TRAFFICMONITOR_SELFTEST`）

- `UpdatePresentationTests`：`wantsCard(.failed) == true`；`menuCheckTitle(.failed) == "检查更新 · 失败"`；`menuCheckTitle(.upToDate) == "检查更新 · 已是最新"`（`.idle` 维持「检查更新」）；`cardContent(.failed)` 的 `primary == "重试"`、notes 含错误文案。
- `UpdateServiceTests`：手动 `checkNow(manual: true)` 得出 upToDate → 触发 upToDate 通知（注入 spy 断言）；自动检查（默认参数）得出 upToDate → 不触发。
- `UpdateCheckerTests` 新增纯函数直测：`shouldFallbackToRedirectProbe`（403/429 是、超时/5xx 否）；`releaseInfo(fromRedirectURL:repository:)`（`/releases/tag/v1.2.3` → tag `v1.2.3`、资产名 `TrafficMonitor-1.2.3.zip`、下载 URL 正确；非 tag 页 URL → nil）。
- 实时集成：`liveRedirectProbe` 请求真实 `github.com/…/releases/latest`，断言最终 URL 可解析出 tag（网络不可用环境跳过，与 `liveGithubLatest` 同风格）。

## 验收

1. `swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` 全绿，自测项数净增。
2. GUI 目检（`make-app.sh` 打包后）：限流场景打开主页 → 卡片展开显示「GitHub 接口限流…」+「重试」；菜单条目显示「检查更新 · 失败」。
3. 端到端：0.4.0/0.5.0 旧版本在限流环境下经降级通道发现 0.6.0+ 并完成应用内升级（随下次真实发布验证）。
