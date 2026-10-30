# 项目宪法（CLAUDE.md）

本文件是本仓库的工作原则，对每次 Claude Code 会话生效。

## 分支与工作流

- **本地开发默认分支为 `develop`**（对应 `origin/develop`）。
- 开发新功能的标准流程：
  1. 先从远端更新 `develop` 与 `main` 的内容（各自 `git pull`）；
  2. 从更新后的 `develop` 创建功能分支（命名 `feature/xxx`；修复 `fix/xxx`；重构 `refactor/xxx`）；
  3. 分支创建、设计文档、实现计划、执行等关键节点，**必须经人工检查和确认后才执行**。
- 文档：中文为主；面向英文读者的文档一律用 `*.en.md` 扩展名。
