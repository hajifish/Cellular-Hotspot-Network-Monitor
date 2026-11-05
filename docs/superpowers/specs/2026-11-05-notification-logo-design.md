# 系统通知带 logo — 设计文档（v2）

日期：2026-11-05
状态：已确认（机制经探针实验目检证实；v1 附件缩略图方案作废）

## 背景与目标

应用 4 类系统通知（流量里程碑、流量告警、新版本可用、已是最新版本）目前走 UNUserNotificationCenter，横幅左侧为系统占位图标、无应用 logo。

参照应用 **LLM-Token-Usage-Monitor-Desktop**（装机名 "Token Usage"，同为无证书 ad-hoc 签名）的通知带 logo，其链路：`tauri-plugin-notification → notify-rust → mac-notification-sys 0.6.15 → 自带 ObjC 桥（objc/notify.m）`——经 **NSUserNotification（老通知接口）** 投递。老接口的通知按应用 bundle 归属、天然携带应用图标，**与签名无关**。

目标：本应用 4 处通知改走同一老接口（Swift 侧经 ObjC 桥），横幅带应用 logo，体验与 Token Usage 一致。

## 实验证据（2026-11-05 本机实测）

- Token Usage.app：`Signature=adhoc`，通知显示 logo（用户目击）；
- 探针 bundle（TrafficProbe.app / `local.shin.TrafficProbe` / ad-hoc / AppIcon 与装机版同源）：clang 直调 NSUserNotification 投递 → **横幅出现且带 logo（用户目检确认）**；
- CLT SDK：NSUserNotification 头文件**对 clang 可见**（`-Wno-deprecated-declarations` 下编译通过，含 `identifier` 属性、`NSUserNotificationCenterDelegate`、`activationType`）；但 Swift 模块层不可见（AppKit swiftmodule 已剔除）→ **需 ObjC 桥，不能纯 Swift 直调**；
- 运行时反射路径不稳（裸进程 `defaultUserNotificationCenter` 返回 nil、KVC 路径 SIGBUS）→ 否决反射方案，采用编译期 ObjC 桥（与 mac-notification-sys 同构）。

## 方案对比（含否决项）

| 方案 | 结论 |
|---|---|
| **ObjC 桥直调 NSUserNotification**（照抄 mac-notification-sys 机制） | **采用**。编译期可见、运行时已证；无证书要求 |
| UNNotificationAttachment 附件缩略图（v1 方案） | 作废：logo 出现在右侧内容位而非应用图标位，与参照体验不一致；且需新增资产管线，更复杂 |
| Apple 开发者证书（$99/年） | 否决：参照应用已证明无证书也能带 logo，无必要 |
| 运行时反射调老接口（纯 Swift） | 否决：实验证明不稳定 |

## 设计

### 1. ObjC 桥 target：`TMNotify`（SPM clang library target）

- `Sources/TMNotify/include/TMNotify.h`（public C 接口）+ `Sources/TMNotify/TMNotify.m`；
- `.m` 顶部 `#pragma clang diagnostic ignored "-Wdeprecated-declarations"`（压掉过时警告，不动 manifest flags）；
- API：

```c
bool tm_notification_available(void);   // NSClassFromString 探测（Apple 未来移除时的检测点）
void tm_post_notification(const char *title, const char *body,
                          const char *identifier, bool sound);
void tm_set_activation_handler(void (*handler)(const char *identifier, int activation_type));
```

- delegate 常驻（static 实例），`didActivateNotification` → 回调 identifier 与 activationType；
- `Package.swift`：新增 `.target`（ObjC，linkerSettings 链 AppKit），主 target 依赖之。

### 2. Swift 包装：`SystemNotifier`（新文件 `Sources/TrafficMonitor/SystemNotifier.swift`）

- `post(title:body:identifier:sound:)`：桥可用时投递；不可用记 error 日志后静默返回（无回退通道，见风险）；
- 启动时注册 activation handler：identifier 前缀 `"update-"` → `openHome()`（复刻现 UN `didReceive` 行为）；
- 测试注入 seam：`var deliver: (String, String, String, Bool) -> Void`（默认实现调桥），对齐 UpdateService notifier seam 风格。

### 3. 调用点替换（4 处）

- `TrafficMonitorApp.checkMilestone()` / `fireAlert()` → `SystemNotifier`；NSSound "Tink" 保留；`showFallbackAlert` **删除**（老接口无失败回调——Token Usage 源码注释声明了同一取舍）；
- `UpdateService.postUpdateNotification` / `postUpToDateNotification` → `SystemNotifier`；identifier 语义不变（`"update-<tag>"` 点击开主页、`"uptodate-check"` 不开）。

### 4. UNUserNotificationCenter 全量移除

- `requestAuthorization`（首次启动不再弹授权框——老接口无需授权，探针已证）；
- MenuBarController 的 UNUserNotificationCenterDelegate（didReceive / willPresent）→ 由 activation handler 取代；
- `import UserNotifications` ×2。

## 风险（如实）

- Apple 在未来 macOS 移除老接口运行时 → 通知静默失效；`tm_notification_available` + 日志可检测。参照应用同样暴露此风险（作者已接受）。届时再评估（UN 回退或证书）；
- 老接口横幅在通知中心历史 / 专注模式的呈现与新接口可能有细微差别——目检覆盖；
- `deliverNotification` 无失败回调：告警"必达性"由 NSSound（始终播放）+ 菜单栏状态兜底（现状已有）。

## 测试与验证

- **自测**：SystemNotifier seam wiring 用例（注入 deliver 断言参数；桥本体不进自测，避免测试二进制弹真通知）；既有 UpdateService 注入用例不变；
- **目检**（`make-app.sh` 打包后跑产物二进制，不碰装机版，用户亲测）：
  1. 菜单「检查更新」→「已是最新版本」横幅带 logo；
  2. 通知声音正常（默认音；告警 Tink 叠加与现状一致）；
  3. 点击更新类通知 → 打开主页；
  4. 首次启动不再弹通知授权框。
- **CI**：GitHub Actions macOS runner 上 SPM 编译 ObjC target（常规支持，无新增外部依赖）；
- **文档**：CHANGELOG `[Unreleased]` 加条目。

## 明确不做

- UN 双通道回退（保持与参照同构，单通道）；
- 开发者证书 / 公证；
- 通知文案、声音、横幅样式改动；
- 开机自启 / 启动欢迎通知。
