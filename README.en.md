# Cellular Hotspot Network Monitor

[![CI](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

**Traffic Monitor** — a native macOS menu bar app that tracks the data your Mac
pushes over Wi-Fi and over a USB-tethered iPhone (cellular hotspot): live
up/down rates in the menu bar, per-module cumulative totals, and a traffic
alert when you cross a limit you set.

*[简体中文](README.md) | English*

## Why

macOS tells you per-app network usage, but when you share your iPhone's
cellular connection over USB it gives no simple answer to "how much of my
mobile plan have I used since I plugged in?". Traffic Monitor counts from the
moment it starts, per interface, and puts the answer one click away.

## Features

- **Menu bar rates** — live rates and totals each render as a compact
  two-line ↑/↓ group, side by side when both are enabled, refreshed every
  second; with both off, only the app icon is shown
- **Display toggles** — two independent toggles at the top-right of the home
  window: live rates (on by default) and totals (off by default); your
  choice is remembered
- **Per-interface totals** — receive/transmit totals and an **independent
  start time** for each of Wi-Fi and iPhone USB
- **Per-module reset** — each interface card has a reset button (top-right);
  after confirmation it clears only that module's counters and clock, and
  any reset re-arms the traffic alert
- **Traffic alerts** — thresholds off / 1 / 2 / 5 / 10 / 20 GB or custom
  values (`5 GB`, `500 MB`). On crossing: a soft chime plus a system
  notification (in-app dialog if notifications are not authorized). Fires
  once per threshold and re-arms on reset or change
- **Home window (⌘0)** — interface cards (name, live rates, totals, reset)
  and a rolling 120-second upload/download rate graph that adapts to light
  and dark mode
- **No network access of its own** — it only reads kernel interface counters

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 toolchain — Apple Command Line Tools are sufficient, full Xcode
  is **not** required

## Build and run

```bash
swift build                                  # build
./scripts/make-app.sh                        # produce "Traffic Monitor.app"
open "Traffic Monitor.app"
```

Or run the build product directly:

```bash
.build/debug/TrafficMonitor
```

### Diagnostics flags

| Environment variable | Effect |
|---|---|
| `TRAFFICMONITOR_SELFTEST=1` | Run the built-in self-test suite and exit (exit code reports the result; currently 99 checks) |
| `TRAFFICMONITOR_SHOWHOME=1` | Open the home window immediately on launch |
| `TRAFFICMONITOR_ALERT_MB=1` | Pre-set a 1 MB alert threshold for verifying the alert path |

## How it works

- Byte counters come from `sysctl(NET_RT_IFLIST2)` — 64-bit `if_data64`, the
  same source as `netstat -ib`. (`getifaddrs` exposes only the 32-bit
  `if_data` on macOS, which wraps around.)
- Interfaces are classified as **Wi-Fi** by interface type `IEEE80211`, and as
  **iPhone USB** by a localized hardware-port display name containing
  "iPhone" (`SCNetworkInterfaceGetLocalizedDisplayName`).
- Rates are per-second deltas between samples; each module's totals and start
  time are independent, and a reset affects only its own module. Threshold
  state is persisted in `UserDefaults`.

## Development

The project is a single SwiftPM executable target with an AppKit UI
(`NSStatusItem` + `NSWindow`) — no third-party dependencies.

Under the Command Line Tools toolchain, XCTest is unavailable, so the
self-test suite is built into the executable and selected with the
`TRAFFICMONITOR_SELFTEST` flag. Please extend it in
`Sources/TrafficMonitor/SelfTest/` when you change behavior.

Design documents and implementation plans live in `docs/superpowers/`.

## Contributing

Contributions are welcome! The project follows a
[Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)
branching model: branch `feature/*` or `bugfix/*` off `develop` and open pull
requests against `develop`. See [CONTRIBUTING.en.md](CONTRIBUTING.en.md)
(Chinese edition: [CONTRIBUTING.md](CONTRIBUTING.md)) for build instructions,
conventions, and the PR checklist.

## License

[MIT](LICENSE) © Shin L (hajifish)
