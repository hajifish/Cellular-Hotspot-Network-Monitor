# Traffic Monitor

macOS 菜单栏流量监测：从启动时刻起累计 Wi-Fi 与 USB 共享 iPhone 的流量，实时显示速率。

## 运行

    ./scripts/make-app.sh
    open "Traffic Monitor.app"

菜单栏出现 `↑.. ↓..` 实时速率；点开可看 Wi-Fi / iPhone Share 分类累计、开始时间，支持重置（⌘R）、**打开主页（⌘0）**、**流量告警**与退出（⌘Q）。

## 流量告警

菜单「流量告警」选择阈值（关闭 / 1 / 2 / 5 / 10 / 20 GB / 自定义，如 `5 GB`、`500 MB`）。总流量（上行+下行）达到阈值时：播放柔和钟声 + 系统通知横幅（未授权通知时回退为应用内弹窗）。每个阈值只提醒一次，「重置计数」或换档后重新武装；阈值选择会记住（UserDefaults）。

## 开发

主页窗口包含：运行时长、两张接口卡片（接口名、实时速率、累计收发）与近 120 秒的滚动速率折线图（上传/下载双线，自适应浅色/深色模式）。

## 开发

    swift build                                  # 构建
    TRAFFICMONITOR_SELFTEST=1 swift run TrafficMonitor   # 运行全部 65 项自测
    TRAFFICMONITOR_SHOWHOME=1 open "Traffic Monitor.app" # 启动即打开主页（诊断用）
    TRAFFICMONITOR_ALERT_MB=1 open "Traffic Monitor.app" # 启动即设 1MB 告警阈值（验证用）

接口分类规则：Wi-Fi 按接口类型 `IEEE80211`；iPhone USB 按硬件端口显示名含 "iPhone"（`SCNetworkInterfaceGetLocalizedDisplayName`）。字节计数走 `sysctl(NET_RT_IFLIST2)` 的 64 位 `if_data64`（与 `netstat -ib` 同源；`getifaddrs` 的 `ifa_data` 是 32 位 `if_data`，会回绕）。

## 环境说明

本机仅有 Command Line Tools（无 Xcode），因此：

- 测试内置在主程序里，以 `TRAFFICMONITOR_SELFTEST=1` 进入自测模式，退出码报告结果
- UI 用 AppKit（`NSStatusItem`）而非 SwiftUI `MenuBarExtra`——CLT 加载不了 SDK 内置的 SwiftUI 宏插件

设计文档见 `docs/superpowers/specs/`，实现计划见 `docs/superpowers/plans/`。
