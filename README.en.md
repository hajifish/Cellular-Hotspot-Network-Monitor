# Cellular Hotspot Network Monitor

<p align="center">
  <img src="docs/assets/logo.svg" alt="Traffic Monitor logo: upstream / downstream traffic" width="110">
</p>

[![CI](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

*[简体中文](README.md) | English*

<p align="center">
  <img src="docs/assets/banner.svg" alt="Traffic Monitor: iPhone USB hotspot → live menu-bar rates → traffic alerts" width="760">
</p>

> ### 📱 Tethering your Mac to your phone's cellular plan? The scary part is silently blowing through the cap.
>
> **Traffic Monitor lives in your menu bar and watches every MB for you:**
> Wi-Fi and USB-tethered iPhone traffic are metered separately with live
> per-second rates; the moment your total crosses a threshold — **with
> per-GB alerting supported by default** (1 / 2 / 5 / 10 / 20 GB presets,
> one alert per threshold) — you get a soft chime plus a system
> notification. Your data budget, at a glance — no more guessing.

## Screenshots

<p align="center">
  <img src="docs/assets/screenshot-home.png" alt="Home window: session summary, interface cards, 120s rate graph" width="640"><br>
  <em>Home window: session summary, per-interface cards (with independent reset), rolling 120-second rate graph</em>
</p>
<p align="center">
  <img src="docs/assets/screenshot-menubar.png" alt="Menu bar dropdown: per-module totals with merged sum" width="420"><br>
  <em>Menu bar dropdown: Wi-Fi / iPhone totals plus an "All" row, switchable display modes</em>
</p>

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
- **Traffic alerts** — based on the **merged total of all modules'
  cumulative upload + download**; thresholds off / 1 / 2 / 5 / 10 / 20 GB or
  custom values (`5 GB`, `500 MB`), presented as a plan budget: once armed,
  the menu and home window show the remainder ("剩 X · 已用 Y%" = X left · Y%
  used). On crossing: a soft chime plus a system notification (in-app
  dialog if notifications are not authorized) and the ring turns red.
  Fires once per threshold and re-arms on reset or change
- **Home window (⌘0)** — interface cards on the left (name, live rates,
  totals, reset) and a **merged-total ring gauge** on the right (ring =
  alert progress: plain when unset / orange arc while armed / red when
  fired), plus a rolling 120-second upload/download rate graph that adapts
  to light and dark mode
- **Auto-update** — detects new releases via GitHub Releases (automatic
  check after launch and every 6 hours; manual check from the menu).
  A new version triggers a system notification plus a "Software Update"
  card in the home window; the app downloads it with progress, verifies
  it, and swaps itself on your confirmation — rolling back automatically
  if the swap fails
- **No network access of its own** — it only reads kernel interface
  counters; GitHub is contacted only to check for and download updates

## Requirements

- Apple Silicon (arm64) Mac
- macOS 14 (Sonoma) or later
- Swift 5.9 toolchain — Apple Command Line Tools are sufficient, full Xcode
  is **not** required

## Install

Grab the DMG (drag to Applications) or ZIP (unpack and run) from the
[Releases](https://github.com/hajifish/Cellular-Hotspot-Network-Monitor/releases)
page — publishing a release triggers CI to build and attach both packages
(Apple Silicon only).

> The app is ad-hoc signed (not notarized). If Gatekeeper blocks the first
> launch: right-click the app → "Open", or run
> `xattr -d com.apple.quarantine "/Applications/Traffic Monitor.app"`.

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
| `TRAFFICMONITOR_SELFTEST=1` | Run the built-in self-test suite and exit (exit code reports the result; check count varies slightly with network conditions, ~200+ checks) |
| `TRAFFICMONITOR_SHOWHOME=1` | Open the home window immediately on launch |
| `TRAFFICMONITOR_ALERT_MB=1` | Pre-set a 1 MB alert threshold for verifying the alert path |
| `TRAFFICMONITOR_AUTOUPDATE=1` | Auto-download when a new version is found and skip the confirm dialog (for verifying the update path) |

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
