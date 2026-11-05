# 系统通知内嵌 logo — 设计文档

日期：2026-11-05
状态：已确认（方案 A 经用户批准；分支 feature/notification-logo）

## 背景与目标

应用现有的 4 类系统通知（流量里程碑、流量告警、新版本可用、已是最新版本）都能正常显示，但横幅里没有应用 logo（左侧为系统占位图标）。参照应用（钉钉 DingTalk 等）的通知能显示 logo，其机制为**正式开发者证书签名**——macOS 通知横幅左侧的应用图标位只归属受信签名应用。

本机证据（2026-11-05 实测）：

| 应用 | 签名 | Team ID |
|---|---|---|
| 钉钉 | 正式证书 | `XN6U3EV979` |
| Kimi | 正式证书 | `2J9472RW75` |
| Traffic Monitor | adhoc（`make-app.sh` 中 `codesign -s -`） | 未设置 |

**目标**：不购买证书的前提下，让每条系统通知的横幅中出现应用 logo（通知内容图片附件，显示于横幅右侧缩略图位），与 App 图标同源同视觉。

## 方案对比（含否决项）

| 方案 | 结论 |
|---|---|
| **A. UNNotificationAttachment 内嵌 logo** | **采用**。附件是通知内容的一部分，与代码签名无关；免费、随包分发、对所有用户生效 |
| B. Apple Developer Program（$99/年） | 否决（2026-10-31 首次评估放弃，本次复核维持）：根治左侧图标位，但年费 + 证书管理 + CI 注入，对个人工具偏重。与 A 不冲突，留作后路 |
| C. 本机自签名证书 | 否决：仅自己机器可能生效，分发产物签名不受信，不比 ad-hoc 好且添乱 |

## 设计

### 资产与打包（沿用 icns 同一母版，视觉同源）

- `make-icon.sh`：渲染 1024 母版后，额外 `sips -z 256 256` 产出 `.build/NotificationLogo.png`（与 AppIcon 同源，同比例处理）；
- `make-app.sh`：`cp` 进 `Contents/Resources/`，并沿用 `sips -g pixelWidth` 校验模式（源缺失即打包失败，与 `default-background.png` 同级保障）；`package-release.sh` 经 `make-app.sh` 构建，自动继承。

### 运行时（新文件 `Sources/TrafficMonitor/NotificationLogo.swift`）

```swift
enum NotificationLogo {
    /// 给通知内容挂 logo 附件；URL 为 nil 或附件创建失败时原样返回（静默降级）
    static func attach(to content: UNMutableNotificationContent,
                       logoURL: URL? = Bundle.main.url(forResource: "NotificationLogo", withExtension: "png"))
        -> UNMutableNotificationContent
}
```

- 成功路径：`UNNotificationAttachment(identifier: "logo", url: logoURL, options: nil)` 挂到 `content.attachments`；
- 降级路径：URL 为 nil（裸二进制/自测环境无 Resources）、或附件初始化抛错 → 返回原 content，通知照发，行为与现状一致；
- 参数默认值绑定 `Bundle.main`，生产调用点零改动即可注入。

### 接入点（4 处通知统一接入）

- `TrafficMonitorApp.swift`：`checkMilestone()`、`fireAlert()`；
- `UpdateService.swift`：新版本通知、已是最新通知。

### 边界行为

- 裸二进制（`swift run` / 自测主程序）：无 bundle 资源 → 静默无附件，不崩、不阻断通知发送；
- 装机版经应用内更新升级：附件资源随新包就位，无需用户操作；
- **已知风险**：macOS 26 对 ad-hoc 应用的附件渲染需目检实证；若不渲染，降级路径即现状（无回归），如实记录并停在该结论，不做伪装方案；
- 左侧占位图标位不在本功能处理范围（见「明确不做」）。

## 测试与验证

- **自测**（新增 `NotificationLogoTests`，可注入 URL 两条用例）：
  - `logoURL = nil` → 返回原内容、无附件、不崩；
  - 临时目录写入小 PNG 后传入 → `content.attachments` 含 1 个附件、类型 `image/png`；
- **目检**（`make-app.sh` 打包后，用户亲测）：
  - 跑产物二进制（与装机版共存，不动装机版），菜单触发「检查更新」→「已是最新版本」通知横幅右侧出现 logo；
  - 流量告警通知同样确认一条（横幅不变形、文案不截断）；
- **打包校验**：`make-app.sh` 每次构建都先跑 `make-icon.sh` 重新生成 `.build/NotificationLogo.png`（`set -euo pipefail` 下生成失败即打包失败），`cp` 后的 `sips` 尺寸校验兜底损坏文件，与 `default-background.png` 同一模式；
- **文档**：CHANGELOG `[Unreleased]` 加条目。

## 明确不做

- 左侧图标位根治（需开发者证书，方案 B 留后路）；
- 开机自启/启动欢迎通知（新功能，与本次无关）；
- 通知其他样式改动（标题、声音、横幅样式均维持现状）。
