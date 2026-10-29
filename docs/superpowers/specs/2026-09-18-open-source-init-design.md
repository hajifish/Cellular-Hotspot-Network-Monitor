# 开源初始化设计 — Cellular-Hotspot-Network-Monitor

日期：2026-09-18
状态：已确认（用户批准后实施）

## 背景与目标

项目准备发布到 `git@github.com:hajifish/Cellular-Hotspot-Network-Monitor.git`，
目标是把现有私有开发仓库整理为可接受社区 PR 的开源仓库：

1. 清理历史与工作区中不该公开的内容（构建产物）
2. 补齐开源社区文件（LICENSE / README / CONTRIBUTING / 模板 / CI）
3. 建立 Gitflow 分支模型，社区 PR 统一指向 `develop`
4. 全程**本地操作，不推送远程**，推送时机由维护者掌握

## 决策记录

| 决策点 | 结论 |
|---|---|
| 许可证 | MIT，版权行 `Copyright (c) 2026 Shin L (hajifish)` |
| 文档语言 | 英文为主（README.md / CONTRIBUTING / 模板），另附 `README.zh-CN.md` |
| 内部设计文档 | `docs/superpowers/` 保留公开，展示设计演进 |
| CI | GitHub Actions：`swift build`（debug+release）+ 内置自测 |
| 历史清理 | `git filter-repo` 重写：抹除 `.build/`、`Traffic Monitor.app/` |
| 日期统一 | 项目起始日期定为 **2026-09-18**：设计/计划文档文件名与内容统一改为 09-18，原始提交时间戳回写为 2026-09-18 → 2026-10-18 均匀分布 |
| 初始化提交 | 使用真实日期（开源整理发生在当天，不参与回写） |

## 历史清理详情

- 备份：`../Cellular-Hotspot-Network-Monitor-git-backup-20261029`（重写前整份 `.git` 拷贝，确认无误后可删）
- `git filter-repo --force`
  - `--path .build --invert-paths`、`--path 'Traffic Monitor.app' --invert-paths`：从全部提交抹除
  - `--path-rename`：4 份设计/计划文档 `2026-10-29-*` → `2026-09-18-*`
  - `--blob-callback`：所有文件内容 `2026-10-29` → `2026-09-18`
- 提交时间戳回写：`git commit-tree` 逐个重建（保留作者身份），15 个提交均匀分布在
  2026-09-18 09:41 → 2026-10-18 21:07（+0800），随后 reflog expire + gc
- 结果验收：15 个提交不变；跟踪文件 32 个（纯源码+文档）；`.git` 由 177MB 降至约 228K；
  历史与工作区无 `2026-10-29` 字样、无 `.build`/`.app` 路径

## 社区文件清单

| 文件 | 说明 |
|---|---|
| `README.md` | 英文重写：定位、功能、要求、构建、自测、原理、贡献指引 |
| `README.zh-CN.md` | 中文版，与英文版结构对齐，整合原 README 内容 |
| `LICENSE` | MIT |
| `CHANGELOG.md` | Keep a Changelog 格式，`[Unreleased]` 起步 |
| `CONTRIBUTING.md` | 开发环境、自测、Gitflow 分支模型、Conventional Commits、PR 清单、维护者手册 |
| `.github/PULL_REQUEST_TEMPLATE.md` | 类型核对（Gitflow）+ 自检清单 |
| `.github/ISSUE_TEMPLATE/bug_report.md` | 环境信息、复现步骤、日志取法 |
| `.github/ISSUE_TEMPLATE/feature_request.md` | 功能建议 |
| `.github/ISSUE_TEMPLATE/config.yml` | 允许空 issue |
| `.github/workflows/ci.yml` | push(main/develop) 与 PR 触发；macos-14；build + 自测 |
| `.gitignore` | `.build/`、`*.app`、`.DS_Store` 等 |

## Gitflow 分支模型

- `main`：仅发布提交与版本 tag（`v*`），受保护，禁直推
- `develop`：集成分支，受保护，禁直推
- `feature/*`：自 `develop` 分出，**社区 PR 一律回到 `develop`**
- `bugfix/*`：同上，修缺陷
- `release/x.y.z`：自 `develop` 分出 → 合入 `main` 并打 tag → 回合 `develop`
- `hotfix/x.y.z`：自 `main` 分出 → 合回 `main` 并打 tag → 回合 `develop`

CI 在 push(main/develop) 与指向二者的 PR 上运行；分支保护建议 PR 必须 CI 通过。

## 提交计划（本地，不推送）

1. `docs: add open-source initialization design doc`
2. `chore: add .gitignore`
3. `docs: rewrite README for open source; add Chinese edition`
4. `chore: add MIT license and changelog`
5. `docs: add contributing guide (Gitflow) and GitHub issue/PR templates`
6. `ci: add build and self-test workflow`

收尾：`git switch -c develop`（指向 main 同点）、`git remote add origin git@github.com:hajifish/Cellular-Hotspot-Network-Monitor.git`。

## 推送（维护者手动执行）

    git push -u origin main develop

推送后在 GitHub 设置分支保护：`main` 与 `develop` 禁直推、PR 前 CI 必须通过。

## 测试与验收

- `swift build` 成功；`TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` 全部通过（exit 0，当前 92 项）
- `git status` 干净；`git log` 分支模型就位（main + develop）；`git remote -v` 指向目标仓库
- 本会话**不执行任何推送**
