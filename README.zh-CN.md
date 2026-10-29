# Cellular Hotspot Network Monitor

[![CI](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

**Traffic Monitor** —— 原生 macOS 菜单栏应用，统计 Mac 通过 Wi-Fi 与 USB 共享
iPhone（蜂窝热点）产生的流量：菜单栏实时显示上行/下行速率，从启动时刻起累计
各接口收发总量，越过设定阈值时发出流量告警。

*[English](README.md) | 简体中文*

## 为什么做这个

macOS 能查每个 App 的网络用量，但当你用 USB 共享 iPhone 蜂窝网络时，「插上
这一路用了多少流量」没有简单的答案。Traffic Monitor 从启动时刻起按接口计数，
把答案放在菜单栏一点即达。

## 功能

- **菜单栏实时速率** —— `↑ ↓` 每秒刷新
- **状态栏显示** —— 主页顶部「状态栏显示」两个独立开关：**实时速率**（默认开）
  与**累计流量**（默认关），点击即切换并记住：
  - 只开实时速率 → `↑0.3KB/s ↓1.2KB/s`
  - 只开累计流量 → `↑2.3GB ↓8.1GB`
  - 两者都开 → **上下两行**（9pt 紧凑排布，节约横向空间）
  - 都关闭 → 状态栏只显示软件图标
- **分类累计** —— Wi-Fi 与 iPhone USB 各自的收/发累计与开始时间，⌘R 重置
- **流量告警** —— 阈值可选关闭 / 1 / 2 / 5 / 10 / 20 GB / 自定义（如 `5 GB`、
  `500 MB`）。达到阈值时播放柔和钟声 + 系统通知横幅（未授权通知时回退为应用内
  弹窗）。每个阈值只提醒一次，「重置计数」或换档后重新武装
- **主页窗口（⌘0）** —— 运行时长、两张接口卡片（接口名、实时速率、累计收发）、
  近 120 秒滚动速率折线图（上传/下载双线，自适应浅色/深色模式）
- **自身不访问网络** —— 只读内核接口计数器

## 环境要求

- macOS 14 (Sonoma) 或更高
- Swift 5.9 工具链 —— 仅需 Command Line Tools，**无需**完整 Xcode

## 构建与运行

```bash
swift build                                  # 构建
./scripts/make-app.sh                        # 生成 "Traffic Monitor.app"
open "Traffic Monitor.app"
```

或直接运行构建产物：

```bash
.build/debug/TrafficMonitor
```

### 诊断开关

| 环境变量 | 作用 |
|---|---|
| `TRAFFICMONITOR_SELFTEST=1` | 运行内置自测后退出（退出码报告结果，当前 92 项） |
| `TRAFFICMONITOR_SHOWHOME=1` | 启动即打开主页窗口 |
| `TRAFFICMONITOR_ALERT_MB=1` | 启动即设 1MB 告警阈值（验证告警链路用） |

## 实现原理

- 字节计数走 `sysctl(NET_RT_IFLIST2)` 的 64 位 `if_data64`（与 `netstat -ib`
  同源；`getifaddrs` 在 macOS 暴露的是 32 位 `if_data`，会回绕）。
- 接口分类：Wi-Fi 按接口类型 `IEEE80211`；iPhone USB 按硬件端口显示名含
  "iPhone"（`SCNetworkInterfaceGetLocalizedDisplayName`）。
- 速率为相邻两次采样的每秒增量；累计自上次重置起算。告警阈值记忆在
  `UserDefaults`。

## 开发

单一 SwiftPM 可执行 target，AppKit UI（`NSStatusItem` + `NSWindow`），无第三方依赖。

在 CLT 工具链下 XCTest 不可用，因此自测套件内置在主程序里，以
`TRAFFICMONITOR_SELFTEST` 环境变量进入。改动行为时请同步扩展
`Sources/TrafficMonitor/SelfTest/` 中的自测。

设计文档见 `docs/superpowers/specs/`，实现计划见 `docs/superpowers/plans/`。

## 参与贡献

欢迎贡献！项目采用
[Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)
分支模型：从 `develop` 分出 `feature/*` 或 `bugfix/*` 分支，PR 一律指向
`develop`。构建方法、提交规范与 PR 清单见
[CONTRIBUTING.md](CONTRIBUTING.md)（英文）。

## 许可证

[MIT](LICENSE) © Shin L (hajifish)
