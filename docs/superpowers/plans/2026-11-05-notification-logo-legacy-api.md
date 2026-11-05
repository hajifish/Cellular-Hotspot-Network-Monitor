# 系统通知带 logo（老通知接口）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 4 类系统通知改走 NSUserNotification 老通知接口（经 ObjC 桥），横幅自带应用图标（与 Token Usage 一致），移除 UNUserNotificationCenter 全部依赖。

**Architecture:** 新增 SPM ObjC 库 target `TMNotify`（对 clang 可见、对 Swift 不可见的老接口在此编译期直调，照抄 mac-notification-sys 0.6.15 的 objc/notify.m 机制）；Swift 侧 `SystemNotifier` 包装（注入 seam + 点击路由）；替换 `TrafficMonitorApp` 2 处、`UpdateService` 2 处调用点；删除 UN 授权请求、delegate、import。

**Tech Stack:** Swift 5.9 (SPM, CLT 无 Xcode)、Objective-C (AppKit)、os.Logger。机制已由 2026-11-05 探针实验目检证实（横幅带 logo）；spec 见 `docs/superpowers/specs/2026-11-05-notification-logo-design.md`（v2）。

## Global Constraints

- 平台 macOS 14+；本机仅 CLT 工具链（无 Xcode）——XCTest/swift-testing 不可用，测试走内置自测（`TRAFFICMONITOR_SELFTEST=1`）。
- 代码注释中文为主，风格对齐现有文件（`///` 文档注释 + Why 说明）。
- Logger subsystem 一律 `local.shin.TrafficMonitor`。
- 不新增任何外部依赖；`make-app.sh` / `make-icon.sh` / 图标资源**零改动**。
- 工作分支 `feature/notification-logo`（已存在）；提交信息末尾加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。
- 目检规则：打包后直接跑产物二进制（`./Traffic Monitor.app/Contents/MacOS/TrafficMonitor`），不用 `open`、不 pkill、不碰装机版。
- 每步验证命令必须真实运行并看到预期输出才算过。

---

### Task 1: TMNotify ObjC 桥 target

**Files:**
- Create: `Sources/TMNotify/include/TMNotify.h`
- Create: `Sources/TMNotify/TMNotify.m`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: C 接口 `bool tm_notification_available(void)`、`void tm_post_notification(const char *title, const char *body, const char *identifier, bool sound)`、`void tm_set_activation_handler(void (*handler)(const char *identifier, int activation_type))`——Task 2 的 Swift 包装按此签名调用。

- [ ] **Step 1: 写入头文件**

创建 `Sources/TMNotify/include/TMNotify.h`：

```c
#ifndef TMNOTIFY_H
#define TMNOTIFY_H
#include <stdbool.h>

/// NSUserNotification 老通知接口桥（照抄 mac-notification-sys 0.6.15 objc/notify.m 机制）。
/// 该接口对 clang 编译期可见、对 Swift 模块不可见，故须经 ObjC 桥 target 转接。
/// 老接口通知按应用 bundle 归属、横幅自带应用图标，无证书要求（2026-11-05 实验证实）。

/// 老接口运行时是否可用（Apple 未来移除时的检测点）
bool tm_notification_available(void);

/// 投递一条系统通知（title/body/identifier 均为 UTF-8 C 字符串；sound 播放系统默认音）
void tm_post_notification(const char *title, const char *body,
                          const char *identifier, bool sound);

/// 注册通知点击回调（identifier 为通知标识，activation_type 为 NSUserNotificationActivationType 原始值）
void tm_set_activation_handler(void (*handler)(const char *identifier, int activation_type));

#endif /* TMNOTIFY_H */
```

- [ ] **Step 2: 写入实现**

创建 `Sources/TMNotify/TMNotify.m`：

```objc
#import "TMNotify.h"
#import <AppKit/AppKit.h>

// NSUserNotification 于 macOS 11 起标记过时；系统运行时保留（macOS 26 实测可用）。
// 与 mac-notification-sys 相同：编译期压掉过时警告，不做运行时反射。
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void (*g_tm_activation_handler)(const char *, int) = NULL;

@interface TMNotifyDelegate : NSObject <NSUserNotificationCenterDelegate>
@end

@implementation TMNotifyDelegate
// 点击/操作通知时回调（AppKit 保证主线程）
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
        didActivateNotification:(NSUserNotification *)notification {
    if (g_tm_activation_handler == NULL) return;
    const char *identifier = notification.identifier.UTF8String;
    g_tm_activation_handler(identifier != NULL ? identifier : "",
                            (int)notification.activationType);
}
@end

static TMNotifyDelegate *g_tm_delegate = nil;

bool tm_notification_available(void) {
    return NSClassFromString(@"NSUserNotificationCenter") != nil
        && NSClassFromString(@"NSUserNotification") != nil;
}

void tm_post_notification(const char *title, const char *body,
                          const char *identifier, bool sound) {
    if (!tm_notification_available()) return;
    @autoreleasepool {
        NSUserNotification *note = [[NSUserNotification alloc] init];
        note.title = [NSString stringWithUTF8String:title ?: ""];
        note.informativeText = [NSString stringWithUTF8String:body ?: ""];
        if (identifier != NULL) {
            note.identifier = [NSString stringWithUTF8String:identifier];
        }
        if (sound) {
            note.soundName = NSUserNotificationDefaultSoundName;
        }
        // 裸二进制（无 bundle）时 center 为 nil，objc 向 nil 发消息＝安全 no-op
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:note];
    }
}

void tm_set_activation_handler(void (*handler)(const char *, int)) {
    g_tm_activation_handler = handler;
    if (g_tm_delegate == nil) {
        g_tm_delegate = [[TMNotifyDelegate alloc] init];
    }
    [NSUserNotificationCenter defaultUserNotificationCenter].delegate = g_tm_delegate;
}
```

- [ ] **Step 3: Package.swift 挂载 target**

`Package.swift` 全量替换为：

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrafficMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // ObjC 桥：NSUserNotification 老通知接口对 Swift 模块不可见（AppKit swiftmodule
        // 已剔除），仅 clang 编译期可见——照抄 mac-notification-sys 的自带桥方案。
        .target(
            name: "TMNotify",
            path: "Sources/TMNotify",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        // 单可执行 target：自测代码内置于 SelfTest/ 目录，运行时以
        // TRAFFICMONITOR_SELFTEST=1 环境变量进入测试模式。
        // （本机仅有 CLT 工具链：XCTest 不可用，swift-testing 宏插件不稳定，
        //   executable→executable 的 @testable import 无法被显式模块扫描解析，
        //   单模块方案是唯一在 `swift build` 下完全确定的结构。）
        .executableTarget(
            name: "TrafficMonitor",
            dependencies: ["TMNotify"],
            path: "Sources/TrafficMonitor"
        ),
    ]
)
```

- [ ] **Step 4: 验证编译（debug + release）**

Run: `swift build 2>&1 | tail -3 && swift build -c release 2>&1 | tail -3`
Expected: 两次均出现 `Build complete!`，无 error（允许无害 warning）。

Run: `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor | tail -1`
Expected: `✔ ... checks passed`（既有自测不受影响）。

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/TMNotify
git commit -m "feat: TMNotify ObjC 桥——NSUserNotification 老通知接口编译期直调

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: SystemNotifier Swift 包装 + 自测

**Files:**
- Create: `Sources/TrafficMonitor/SystemNotifier.swift`
- Create: `Sources/TrafficMonitor/SelfTest/SystemNotifierTests.swift`
- Modify: `Sources/TrafficMonitor/SelfTest/TestSupport.swift:85`（注册套件）

**Interfaces:**
- Consumes: Task 1 的 `tm_notification_available()` / `tm_post_notification(_:_:_:_:)` / `tm_set_activation_handler(_:)`（Swift 导入签名）。
- Produces: `SystemNotifier.post(title:body:identifier:sound:)`（sound 默认 true）、`SystemNotifier.configureActivation(router:)`、`SystemNotifier.handleActivation(identifier:)`、注入点 `SystemNotifier.deliver: (String, String, String, Bool) -> Void`——Task 3/4 按此调用。

- [ ] **Step 1: 写失败的自测**

创建 `Sources/TrafficMonitor/SelfTest/SystemNotifierTests.swift`：

```swift
enum SystemNotifierTests {
    static func all() {
        postRoutesThroughDeliverSeam()
        activationRouterReceivesIdentifier()
    }

    static func postRoutesThroughDeliverSeam() {
        let original = SystemNotifier.deliver
        defer { SystemNotifier.deliver = original }
        var posted: [(String, String, String, Bool)] = []
        SystemNotifier.deliver = { title, body, identifier, sound in
            posted.append((title, body, identifier, sound))
        }
        SystemNotifier.post(title: "标题", body: "正文", identifier: "id-1", sound: false)
        TestRun.expectEqual(posted.count, 1, "post 经 seam 投递一次")
        if posted.count == 1 {
            let p = posted[0]
            TestRun.expectEqual(p.0, "标题", "title 透传")
            TestRun.expectEqual(p.1, "正文", "body 透传")
            TestRun.expectEqual(p.2, "id-1", "identifier 透传")
            TestRun.expectEqual(p.3, false, "sound 透传")
        }
    }

    static func activationRouterReceivesIdentifier() {
        var received: [String] = []
        SystemNotifier.configureActivation { received.append($0) }
        SystemNotifier.handleActivation(identifier: "update-v9.9.9")
        TestRun.expectEqual(received, ["update-v9.9.9"], "点击路由透传 identifier")
    }
}
```

`TestSupport.swift` 的 `SelfTest.run()` 中，`UpdatePresentation` 行后加一行：

```swift
        TestRun.suite("SystemNotifier") { SystemNotifierTests.all() }
```

- [ ] **Step 2: 跑自测确认失败**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor 2>&1 | tail -3`
Expected: 编译失败 `cannot find 'SystemNotifier' in scope`（测试先行，符号未定义）。

- [ ] **Step 3: 实现 SystemNotifier**

创建 `Sources/TrafficMonitor/SystemNotifier.swift`：

```swift
import Foundation
import os
import TMNotify

/// 系统通知统一出口：经 TMNotify 桥走 NSUserNotification 老接口。
/// 老接口通知按应用 bundle 归属、横幅自带应用图标（无证书要求；UNUserNotificationCenter
/// 对 ad-hoc 签名应用只给占位图标）。机制与 mac-notification-sys（Token Usage 同链路）
/// 一致，2026-11-05 探针实验目检证实。取舍：deliverNotification 无失败回调，投递失败
/// 不可检测（告警的 NSSound "Tink" 与菜单栏状态是必达兜底）。
enum SystemNotifier {
    private static let logger = Logger(subsystem: "local.shin.TrafficMonitor", category: "notify")

    /// 测试注入点：默认实现经桥投递（自测注入 no-op，避免测试二进制弹真通知）
    static var deliver: (String, String, String, Bool) -> Void = { title, body, identifier, sound in
        tm_post_notification(title, body, identifier, sound)
    }

    /// 投递系统通知；老接口运行时缺失（Apple 未来移除）时记日志后静默丢弃
    static func post(title: String, body: String, identifier: String, sound: Bool = true) {
        guard tm_notification_available() else {
            logger.error("legacy notification API unavailable, dropped: \(title, privacy: .public)")
            return
        }
        deliver(title, body, identifier, sound)
    }

    /// 点击路由表（C 回调无法捕获上下文，经静态表转发）
    private static var activationRouter: ((String) -> Void)?

    /// 注册点击路由并挂接桥回调。AppKit 保证回调在主线程；防御性再兜一次主队列。
    static func configureActivation(router: @escaping (String) -> Void) {
        activationRouter = router
        tm_set_activation_handler { identifier, _ in
            let id = identifier.map { String(cString: $0) } ?? ""
            if Thread.isMainThread {
                SystemNotifier.handleActivation(identifier: id)
            } else {
                DispatchQueue.main.async {
                    SystemNotifier.handleActivation(identifier: id)
                }
            }
        }
    }

    /// 桥回调落点（internal 供自测直接驱动）
    static func handleActivation(identifier: String) {
        activationRouter?(identifier)
    }
}
```

- [ ] **Step 4: 跑自测确认通过**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor | tail -4`
Expected: `Build complete!`；输出含 `── SystemNotifier` 与 `ok`；末行 `✔ ... checks passed`（总数较 Task 1 基线 +6 左右）。

- [ ] **Step 5: Commit**

```bash
git add Sources/TrafficMonitor/SystemNotifier.swift Sources/TrafficMonitor/SelfTest/SystemNotifierTests.swift Sources/TrafficMonitor/SelfTest/TestSupport.swift
git commit -m "feat: SystemNotifier 包装——老通知接口 Swift 出口 + 点击路由 + 自测

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: TrafficMonitorApp 接入（里程碑/告警）+ UN 代码移除

**Files:**
- Modify: `Sources/TrafficMonitor/TrafficMonitorApp.swift`（imports :4、类声明 :118、授权请求 :197-198、delegate 挂接 :219、checkMilestone/fireAlert/showFallbackAlert/requestNotificationAuthorization :488-547、UN delegate 扩展 :631-651）

**Interfaces:**
- Consumes: `SystemNotifier.post(title:body:identifier:sound:)`、`SystemNotifier.configureActivation(router:)`（Task 2）。
- Produces: 无（叶子改动；`openHome()` 沿用既有方法）。

- [ ] **Step 1: 移除 import 与 delegate 一致性**

`import UserNotifications`（第 4 行）整行删除。

类声明（第 118 行）：

```swift
final class MenuBarController: NSObject, NSMenuDelegate, UNUserNotificationCenterDelegate {
```

改为：

```swift
final class MenuBarController: NSObject, NSMenuDelegate {
```

- [ ] **Step 2: 授权请求与 delegate 挂接替换**

第 197-198 行：

```swift
        // 里程碑与告警都依赖系统通知，首次启动请求授权（已授权则静默返回）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
```

改为（老接口无需授权，探针已证）：

```swift
        // 老通知接口无需授权请求（2026-11-05 探针实验证实），首次启动不再弹系统授权框
```

第 219 行：

```swift
        UNUserNotificationCenter.current().delegate = self
```

改为：

```swift
        // 老通知接口点击路由：更新类通知（"update-" 前缀）点击后打开主页（沿用 UN 时代行为）
        SystemNotifier.configureActivation { [weak self] identifier in
            guard identifier.hasPrefix("update-") else { return }
            self?.openHome()
        }
```

- [ ] **Step 3: checkMilestone 改走 SystemNotifier**

`checkMilestone()` 内投递段：

```swift
        let content = UNMutableNotificationContent()
        content.title = "Traffic Monitor 流量里程碑"
        content.body = "累计已用 \(ByteFormat.string(totalBytes))。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            // 里程碑仅为提示性质，不弹兜底；但投递失败要留日志，否则排查无从下手
            if let error {
                Task { @MainActor in
                    self?.logger.error("milestone notification failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
```

改为：

```swift
        SystemNotifier.post(title: "Traffic Monitor 流量里程碑",
                            body: "累计已用 \(ByteFormat.string(totalBytes))。",
                            identifier: UUID().uuidString)
```

- [ ] **Step 4: fireAlert 改走 SystemNotifier，删兜底弹窗**

`fireAlert(usedBytes:)` 全函数替换为：

```swift
    private func fireAlert(usedBytes: UInt64) {
        let used = ByteFormat.string(usedBytes)
        let limit = ByteFormat.string(alert.threshold ?? 0)
        logger.info("alert fired: used=\(used, privacy: .public) threshold=\(limit, privacy: .public)")
        // "滴"一声是必达通道：老通知接口无失败回调，通知本身不可确证送达
        NSSound(named: "Tink")?.play()
        SystemNotifier.post(title: "Traffic Monitor 流量告警",
                            body: "已用 \(used)，达到 \(limit)。",
                            identifier: UUID().uuidString)
    }
```

紧随其后的两个方法整体删除：`showFallbackAlert(used:limit:)`（应用内兜底弹窗——老接口无失败回调，触发条件不复存在）与 `requestNotificationAuthorization()`（老接口无需授权）。

- [ ] **Step 5: 删除 UN delegate 扩展**

文件末尾 `extension MenuBarController { ... }` 中两个 `userNotificationCenter` 方法（didReceive / willPresent，约 631-651 行）整体删除（didReceive 的 openHome 路由已由 Step 2 的 activation router 承接；willPresent 的前台显示为 UN 专属语义，老接口横幅本就照常显示）。

- [ ] **Step 6: 验证**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor | tail -2`
Expected: `Build complete!`；`✔ ... checks passed`（TrafficMonitorApp 套件不涉通知投递细节，应保持全绿）。

Run: `grep -c "UserNotifications\|UNUserNotification" Sources/TrafficMonitor/TrafficMonitorApp.swift`
Expected: `0`

- [ ] **Step 7: Commit**

```bash
git add Sources/TrafficMonitor/TrafficMonitorApp.swift
git commit -m "feat: 里程碑/告警通知改走老接口（带应用图标），移除 UN 授权与 delegate

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: UpdateService 接入（新版本/已是最新）

**Files:**
- Modify: `Sources/TrafficMonitor/UpdateService.swift`（import :3、seam 注释 :45-47、postUpdateNotification :125-142、postUpToDateNotification :144-160）

**Interfaces:**
- Consumes: `SystemNotifier.post(title:body:identifier:)`（Task 2）。
- Produces: 无（seam `versionAvailableNotifier` / `upToDateNotifier` 签名不变，既有 UpdateServiceTests 不动）。

- [ ] **Step 1: 移除 import，更新 seam 注释**

第 3 行 `import UserNotifications` 整行删除。

seam 注释（45-47 行）：

```swift
    /// 测试注入点：发现新版本时的系统通知（UNUserNotificationCenter 在无 bundle 的
    /// 自测二进制里会直接抛异常，故不可用默认实现直接跑自测）
```

改为：

```swift
    /// 测试注入点：发现新版本时的系统通知（老通知接口在裸二进制下 center 为 nil、
    /// 安全 no-op，默认实现本可直跑；注入仅避免自测弹真通知）
```

- [ ] **Step 2: 替换两个静态投递函数**

`postUpdateNotification(_:)` 全函数替换为（保留原「前缀联动」注释语义）：

```swift
    static func postUpdateNotification(_ release: ReleaseInfo) {
        SystemNotifier.post(title: "Traffic Monitor 有新版本",
                            body: "\(release.tagName) 可更新（当前 \(AppVersion.current)）。",
                            identifier: "update-\(release.tagName)")
    }
```

`postUpToDateNotification()` 全函数替换为：

```swift
    /// 手动检查确认已是最新：轻量通知告知即可。identifier 不带 "update-" 前缀，
    /// 点击不跳主页（无升级内容可看）。
    /// 注意：是否跳主页的判定在 MenuBarController 的 SystemNotifier activation
    /// router 里按 "update-" 前缀检查——"uptodate" 与 "update-" 一字之差，
    /// 重命名 identifier 时两处必须同步，防静默破坏
    static func postUpToDateNotification() {
        SystemNotifier.post(title: "Traffic Monitor 已是最新版本",
                            body: "当前 \(AppVersion.current) 即最新发布版。",
                            identifier: "uptodate-check",
                            sound: false)
    }
```

- [ ] **Step 3: 验证**

Run: `swift build 2>&1 | tail -2 && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor | tail -2`
Expected: `Build complete!`；`✔ ... checks passed`。

Run: `grep -c "UserNotifications\|UNUserNotification" Sources/TrafficMonitor/UpdateService.swift`
Expected: `0`

Run: `grep -rn "UserNotifications\|UNUserNotification" Sources/ | grep -v SelfTest`
Expected: 仅 SystemNotifier.swift:6 一处——文档注释里的历史说明（解释为何不用 UN），非 import/非 API 调用；代码级 UN 依赖为 0。

- [ ] **Step 4: Commit**

```bash
git add Sources/TrafficMonitor/UpdateService.swift
git commit -m "feat: 更新类通知改走老接口（带应用图标），移除 UN 依赖

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 5: CHANGELOG + 全量验证 + 打包交目检

**Files:**
- Modify: `CHANGELOG.md`（[Unreleased] → ### 变更 (Changed)）

**Interfaces:**
- Consumes: Task 1-4 全部产出。
- Produces: 可目检的 `./Traffic Monitor.app` 产物（用户亲测后由用户决定 PR）。

- [ ] **Step 1: CHANGELOG 条目**

`[Unreleased]` 的 `### 变更 (Changed)` 列表末尾追加一行：

```markdown
- 系统通知（流量里程碑/流量告警/新版本/已是最新）改走系统兼容通知通道：横幅显示应用图标（与 Token Usage 一致）；首次启动不再请求通知权限
```

- [ ] **Step 2: 全量验证（与 CI 同口径）**

Run: `swift build && swift build -c release && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor | tail -1`
Expected: `Build complete!` ×2；末行 `✔ N checks passed`（N = 基线 + 约 6）。

- [ ] **Step 3: 打包**

Run: `./scripts/make-app.sh`
Expected: 末行 `Built ./Traffic Monitor.app`（脚本零改动——图标/资源/签名流程原样）。

- [ ] **Step 4: 用户目检（亲测，不碰装机版）**

启动 `./Traffic Monitor.app/Contents/MacOS/TrafficMonitor`（直接跑二进制，与装机版共存），核对 4 点：

1. 菜单「检查更新」→「已是最新版本」横幅出现且**左侧为应用 logo**（非灰色占位）；
2. 横幅带默认提示音；
3. （若期间有新版本通知）点击通知 → 打开主页更新卡片；
4. 启动时**不再弹**系统通知授权框。

任一不过 → 回到对应 Task 修；全过 → 通知用户分支已就绪，等用户明确指令再发 PR（项目规则：PR/发版须用户亲口说）。

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: CHANGELOG 记录通知通道切换（老接口带应用图标）

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Self-Review 记录

- **Spec 覆盖**：桥 target（设计 §1）→ Task 1；SystemNotifier（§2）→ Task 2；4 调用点 + UN 移除（§3/§4）→ Task 3/4；CHANGELOG/目检（测试与验证）→ Task 5。风险条款（无失败回调、未来移除检测）已内嵌于代码注释与 logger。
- **占位符扫描**：无 TBD/TODO；所有代码步骤含完整代码。
- **类型一致性**：`post(title:body:identifier:sound:)` 签名在 Task 2/3/4 一致；`"update-"` 前缀路由语义（Task 3 Step 2 与 Task 4 Step 2）互相咬合并保留联动注释；C 接口三函数在 Task 1 产出与 Task 2 消费一致。
