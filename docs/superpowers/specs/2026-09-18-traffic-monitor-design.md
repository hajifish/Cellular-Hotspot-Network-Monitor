# Traffic Monitor — 设计文档

日期：2026-09-18
状态：已批准

## 目标

一个简洁的 macOS 菜单栏小应用，记录从启动时刻起的流量使用情况，区分 Wi-Fi 流量与通过 USB 共享的 iPhone 蜂窝流量。不追求持久化和进程级明细。

## 已确认的需求决策

1. **形态**：菜单栏小应用（SwiftUI `MenuBarExtra`），无 Dock 图标。
2. **菜单栏显示**：总量 + 实时速率，如 `↑2.3 ↓0.1 GB`。
3. **计数周期**：启动即从零开始计数，菜单内手动「重置」。数据不落盘。
4. **采集方式**：`getifaddrs()` 系统调用，每秒轮询各网卡累计字节数，差值算速率。无特殊权限、无第三方依赖。

## 架构

Swift Package（无 .xcodeproj），单 target，macOS 13+。附带打包脚本将编译产物组装为 `Traffic Monitor.app`（Info.plist 设 `LSUIElement = true`）。

### 组件

**1. `TrafficSampler`（采集）**
- 每秒调用 `getifaddrs()`，读取所有 `AF_LINK` 接口的累计收/发字节数。
- 接口分类（通过 SystemConfiguration `SCNetworkInterface` 查硬件端口描述）：
  - iPhone 接口：硬件端口描述为 "iPhone USB" 的 BSD 名（通常是 en5）
  - Wi-Fi 接口：硬件端口描述为 "Wi-Fi" 的 BSD 名
  - 其他接口（以太网、utun、awdl0、lo0 等）一律忽略
- 输出：`InterfaceSnapshot`（接口名 → (rx, tx)），与上次快照做差值得每秒增量。

**2. `UsageStore`（累计状态）**
- 纯内存状态：`startTime` + Wi-Fi/iPhone 各自的 (rx, tx) 累计字节。
- 方法：`record(delta:)` 累加、`reset()` 清零重置开始时间。
- 差值为负（iPhone 拔插导致计数器清零）时按 0 处理。

**3. 菜单栏 UI（SwiftUI）**
- 菜单栏标题：当前总速率 `↑x ↓y`（自适应单位）。
- 菜单内容：
  ```
  开始时间   10:42
  ─────────────
  Wi-Fi    ↑ 1.2 GB  ↓ 4.5 GB
  iPhone   ↑ 80 MB   ↓ 620 MB
  ─────────────
  重置计数
  退出
  ```

### 数据流

`Timer(1s) → getifaddrs 快照 → 差值 → UsageStore → @Observable 刷新 UI`

## 边界情况

- getifaddrs 调用失败：跳过该秒，数据不动。
- iPhone 断开：速率归 0，累计保留。
- 接口计数器回绕/清零：负差值钳位为 0。

## 测试

XCTest 覆盖纯逻辑：差值计算、负差值钳位、字节单位格式化、UsageStore 累计/重置。`getifaddrs` 调用封装为协议 `InterfaceSampling`，测试注入假快照。UI 层不做单测。

## 实现偏差（2026-09-18 实现时确认）

1. **UI 层改用 AppKit（`NSStatusItem` + `NSMenu`）** 而非 SwiftUI `MenuBarExtra`：本机仅有 Command Line Tools 工具链，加载不了 SDK 内置的 SwiftUI 宏插件（`@State` 等），Observation 宏不受影响。功能与设计稿一致。
2. **字节计数用 `sysctl(NET_RT_IFLIST2)` 而非 `getifaddrs`**：实测发现 `getifaddrs` 的 `ifa_data` 是 32 位 `if_data`（4GB 回绕、字段偏移与 `if_data64` 不匹配）；`NET_RT_IFLIST2` 是 `netstat -ib` 的数据源，64 位计数。
3. **测试框架**：CLT 环境无 XCTest、swift-testing 宏插件不稳定。自测代码内置于主程序，`TRAFFICMONITOR_SELFTEST=1` 进入测试模式（45 项断言），`/sbin/ping` 网关的实时集成测试保证计数器读到真实流量。
