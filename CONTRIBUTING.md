# Contributing to Cellular Hotspot Network Monitor

Thanks for your interest in contributing! This document covers the
development setup, the branching model, and what we expect from a pull
request.

## Project overview

Traffic Monitor is a single-target SwiftPM executable with an AppKit UI
(`NSStatusItem` + `NSWindow`). There are no third-party dependencies, so a
clone builds as-is:

```bash
git clone git@github.com:hajifish/Cellular-Hotspot-Network-Monitor.git
cd Cellular-Hotspot-Network-Monitor
swift build
```

### Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 toolchain — Apple Command Line Tools are sufficient
  (`xcode-select --install`); a full Xcode install works too but is not
  required

### Testing

The CLT toolchain cannot load XCTest, so the self-test suite is built into
the executable and enabled with an environment variable. It runs the full
suite headlessly and exits — the exit code reports the result:

```bash
TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
# ✔ N checks passed   (exit 0), or failures + non-zero exit
```

If your change affects behavior, please extend the self-tests in
`Sources/TrafficMonitor/SelfTest/` — one file per module, plain functions
registered with the small harness in `TestSupport.swift`.

### Building the app bundle

```bash
./scripts/make-app.sh
open "Traffic Monitor.app"
```

## Branching model (Gitflow)

The project follows [Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow).
`main` and `develop` are protected — all changes arrive via pull request.

```text
main      ──●──────────────●─────────●──▶  releases & tags (v*) only
            │              │         │
release/*   └──●──────●────┘         │
                              │     │
hotfix/*                      ●─────┼──▶  critical fixes from main
                              │     │
develop   ──●──●──●──●──●──●──●──●──●──▶  integration branch
            │  │
feature/*   ●──┘   bugfix/*   ◀── community PRs land here
```

| Branch | Cut from | Merged into | Purpose |
|---|---|---|---|
| `main` | — | — | Production releases, tagged `v*` |
| `develop` | `main` (at release) | — | Integration branch; always buildable |
| `feature/<name>` | `develop` | `develop` | New features — **community PRs target `develop`** |
| `bugfix/<name>` | `develop` | `develop` | Non-urgent fixes |
| `release/x.y.z` | `develop` | `main` + `develop` | Release prep, version bump |
| `hotfix/x.y.z` | `main` | `main` + `develop` | Urgent fixes to a released tag |

Typical contribution:

```bash
git switch develop
git pull
git switch -c feature/cooler-graph
# ... commit your work ...
git push -u origin feature/cooler-graph
# then open a PR against develop
```

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/), matching
the existing history:

```text
feat: status bar display modes, alert markers and menu styling
fix: clamp negative deltas after interface reset
docs: add contributing guide
chore: add .gitignore
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.
Keep each commit focused; the maintainers squash only when necessary.

## Pull request checklist

- [ ] Branch is `feature/*` or `bugfix/*`, cut from the latest `develop`,
      and the PR targets **`develop`**
- [ ] Commits follow Conventional Commits
- [ ] `swift build` succeeds
- [ ] `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` passes, with
      self-tests added or updated for behavior changes
- [ ] User-facing changes are reflected in both `README.md` and
      `README.zh-CN.md`, and noted under `[Unreleased]` in `CHANGELOG.md`
- [ ] CI is green

## Reporting issues

Please use the issue templates. For bugs, include the macOS version, how the
hotspot is connected (USB-tethered iPhone model + iOS version, or Wi-Fi), and
console output if available:

```bash
log show --last 1h --predicate 'subsystem == "local.shin.TrafficMonitor"'
```

## Maintainer notes

- **Branch protection** (set on GitHub after the first push): `main` and
  `develop` — no direct pushes, require PRs, require the `CI` check to pass.
- **Releases**: cut `release/x.y.z` from `develop`, finalize `CHANGELOG.md`,
  merge to `main`, tag `vx.y.z`, back-merge into `develop`.
- **Hotfixes**: cut `hotfix/x.y.z` from `main`, merge back to `main`, tag,
  then back-merge into `develop`.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).
