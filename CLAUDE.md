# 项目宪法（CLAUDE.md）

本文件是本仓库的工作原则，对每次 Claude Code 会话生效。

## 分支与工作流

- **本地开发默认分支为 `develop`**（对应 `origin/develop`）。
- 开发新功能的标准流程：
  1. 先从远端更新 `develop` 与 `main` 的内容（各自 `git pull`）；
  2. 从更新后的 `develop` 创建功能分支（命名 `feature/xxx`；修复 `fix/xxx`；重构 `refactor/xxx`）；
  3. 分支创建、设计文档、实现计划、执行等关键节点，**必须经人工检查和确认后才执行**。
- 文档：中文为主；面向英文读者的文档一律用 `*.en.md` 扩展名。

## 发布与收尾

- 发布流程（功能合并进 `develop` 后）：
  1. 在 `develop` 提交 `chore: prepare x.y.0 release`（CHANGELOG `[Unreleased]` 归版为 `[x.y.0] - 日期`）；
  2. 创建 `develop` → `main` 的发布 PR 并合并；
  3. 在 main 合并提交上打 tag `vx.y.0` 并先推送 tag，再 `gh release create vx.y.0`（**不带 `--target`**，带了会 422）；
  4. Release published 自动触发打包工作流挂载 DMG/ZIP；已安装的旧版本走应用内更新升级到新版本做真实验证。
- 发布完成后的本地清理（每次发布后执行）：删除已合并的功能分支（本地与远端）、移除遗留 worktree、快进本地 `main`，**主仓库检出回到 `develop` 并与远端同步**，清掉临时构建产物（仓库根目录的 `*.app`）。
