# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Menu bar traffic monitoring for Wi-Fi and USB-tethered iPhone (cellular hotspot):
  live up/down rates and per-interface totals since launch, resettable via ⌘R.
- Status bar display modes: two independent toggles (live rates / totals),
  including a compact two-row layout when both are shown, or icon-only.
- Traffic threshold alerts: presets (1/2/5/10/20 GB) or custom values ("5 GB",
  "500 MB"); soft chime plus system notification (in-app dialog fallback).
  Fires once per threshold and re-arms on reset or change.
- Home window (⌘0): runtime, interface cards, and a rolling 120-second
  upload/download rate graph that adapts to light and dark mode.
- Built-in self-test suite (run with `TRAFFICMONITOR_SELFTEST=1`; exit code
  reports the result).
