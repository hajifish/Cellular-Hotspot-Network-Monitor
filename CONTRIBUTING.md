# 参与贡献 Cellular Hotspot Network Monitor

感谢你有兴趣参与贡献！本文档覆盖开发环境搭建、分支模型与 Pull Request 要求。

*简体中文 | [English](CONTRIBUTING.en.md)*

## 项目概览

Traffic Monitor 是单 target 的 SwiftPM 可执行程序，AppKit UI
（`NSStatusItem` + `NSWindow`），无第三方依赖，克隆即可构建：

```bash
git clone git@github.com:hajifish/Cellular-Hotspot-Network-Monitor.git
cd Cellular-Hotspot-Network-Monitor
swift build
```

### 环境要求

- macOS 14 (Sonoma) 或更高
- Swift 5.9 工具链 —— 仅需 Apple Command Line Tools（`xcode-select --install`）；
  装有完整 Xcode 也可以，但并非必需

### 测试

CLT 工具链无法加载 XCTest，因此自测套件内置在主程序里，用环境变量开启。
它会无界面跑完全部自测并以退出码报告结果：

```bash
TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor
# ✔ N checks passed（退出码 0）；失败则打印明细并以非零码退出
```

如果你的改动影响行为，请同步扩展 `Sources/TrafficMonitor/SelfTest/` 中的
自测 —— 每个模块一个文件，普通函数注册到 `TestSupport.swift` 的小型测试骨架即可。

### 打包 App

```bash
./scripts/make-app.sh
open "Traffic Monitor.app"
```

## 分支模型（Gitflow）

项目采用 [Gitflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)。
`main` 与 `develop` 均受保护 —— 所有改动一律通过 Pull Request 进入。

```text
main      ──●──────────────●─────────●──▶  仅发布与版本 tag（v*）
            │              │         │
release/*   └──●──────●────┘         │
                              │     │
hotfix/*                      ●─────┼──▶  自 main 分出的紧急修复
                              │     │
develop   ──●──●──●──●──●──●──●──●──●──▶  集成分支
            │  │
feature/*   ●──┘   bugfix/*   ◀── 社区 PR 落在这里
```

| 分支 | 分出自 | 合入 | 用途 |
|---|---|---|---|
| `main` | — | — | 生产发布，打 `v*` tag |
| `develop` | `main`（发布时） | — | 集成分支，始终可构建 |
| `feature/<名称>` | `develop` | `develop` | 新功能 —— **社区 PR 指向 `develop`** |
| `bugfix/<名称>` | `develop` | `develop` | 非紧急缺陷修复 |
| `release/x.y.z` | `develop` | `main` + `develop` | 发布准备、版本号调整 |
| `hotfix/x.y.z` | `main` | `main` + `develop` | 已发布版本的紧急修复 |

典型贡献流程：

```bash
git switch develop
git pull
git switch -c feature/cooler-graph
# ...提交你的工作...
git push -u origin feature/cooler-graph
# 然后向 develop 发起 PR
```

## 提交信息

使用 [Conventional Commits](https://www.conventionalcommits.org/)，与现有历史一致：

```text
feat: status bar display modes, alert markers and menu styling
fix: clamp negative deltas after interface reset
docs: add contributing guide
chore: add .gitignore
```

类型：`feat`、`fix`、`docs`、`refactor`、`test`、`chore`、`ci`。
每个提交保持聚焦；维护者仅在必要时 squash。

## Pull Request 自检清单

- [ ] 分支为 `feature/*` 或 `bugfix/*`，基于最新 `develop`，PR 指向 **`develop`**
- [ ] 提交信息遵循 Conventional Commits
- [ ] `swift build` 通过
- [ ] `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` 通过，行为变更附了自测
- [ ] 用户可见变更已同步 `README.md` 与 `README.en.md`，并记入 `CHANGELOG.md`
      的 `[Unreleased]`
- [ ] CI 全绿

## 报告问题

请使用 issue 模板。报 bug 时请附上：macOS 版本、热点连接方式（USB 共享的
iPhone 机型与 iOS 版本，或 Wi-Fi），如有可能附上控制台日志：

```bash
log show --last 1h --predicate 'subsystem == "local.shin.TrafficMonitor"'
```

## 维护者须知

- **分支保护**（首次推送后在 GitHub 设置）：`main` 与 `develop` 禁直推、
  必须 PR、必须通过 `CI` 检查。
- **发布**：从 `develop` 分出 `release/x.y.z`，定稿 `CHANGELOG.md`，合入
  `main`，打 tag `vx.y.z`，再回合 `develop`。然后在 GitHub 基于 tag 发布
  Release——`Release` 工作流会自动打包 DMG/ZIP 并挂到 Release 页。
- **紧急修复**：从 `main` 分出 `hotfix/x.y.z`，合回 `main` 并打 tag，再回合
  `develop`。

## 许可证

提交贡献即表示你同意其按 [MIT 许可证](LICENSE) 授权。
