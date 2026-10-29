# 发布打包设计 — 可安装软件包 + GitHub Release 自动构建

日期：2026-09-18
状态：已确认（用户批准后实施）

## 目标

1. 本地一条命令产出可独立安装的软件包（DMG 拖拽安装 + ZIP 即用）
2. GitHub 上**发布 Release 即自动打包**并把安装包挂回该 Release
3. 仅支持 macOS；打包仅覆盖 Apple Silicon (arm64)（用户决策）

## 决策记录

| 决策点 | 结论 |
|---|---|
| 安装物格式 | DMG（拖拽安装）+ ZIP（即用 / Homebrew Cask 兼容）双格式 |
| CPU 架构 | 仅 arm64（Apple Silicon）；README 环境要求需注明 |
| 触发方式 | `release: types: [published]`；另开 `workflow_dispatch` 手动试跑 |
| 签名 | 沿用 make-app.sh 的 ad-hoc 签名（无 Developer ID，README 注明 Gatekeeper 首开方式；将来加签名/公证只改 workflow 与脚本参数） |
| 版本号 | 以 Release tag 为准，去 `v` 前缀注入 `CFBundleShortVersionString` / `CFBundleVersion` |
| 与在途工作隔离 | 新增 `scripts/package-release.sh` 与 workflow，不修改 make-app.sh；README/CHANGELOG 的文档同步等并行会话未提交改动落盘后再做 |

## `scripts/package-release.sh`

用法：`./scripts/package-release.sh <version> [输出目录=dist]`

1. 调 `scripts/make-app.sh`（release 构建 + 图标 + ad-hoc 签名）
2. `PlistBuddy` 注入版本号（去 `v` 前缀）→ 重新 `codesign --force -s -`（plist 变更使旧签名失效）
3. ZIP：`ditto -c -k --keepParent`（保留签名/扩展属性，Cask 兼容）
4. DMG：暂存目录放入 `.app` + `/Applications` 替身 → `hdiutil create -format UDZO`
5. 产物：`dist/TrafficMonitor-<version>.zip` / `.dmg`

全程系统工具（PlistBuddy / ditto / hdiutil），零第三方依赖。

## `.github/workflows/release.yml`

- 触发：release published；workflow_dispatch（手动验证）
- `permissions: contents: write`（上传附件用 `GITHUB_TOKEN`）
- macos-14（arm64 原生）：
  1. `swift build -c release` + `TRAFFICMONITOR_SELFTEST=1 .build/release/TrafficMonitor`（发布前自测把关）
  2. `./scripts/package-release.sh "$GITHUB_REF_NAME" dist`
  3. release 事件：`gh release upload <tag> dist/*.zip dist/*.dmg --clobber`
  4. 手动触发：`actions/upload-artifact`（只验证不出货）

## Gitflow 发布流程（维护者）

release/x.y.z 定稿 → 合入 `main` 并打 tag → 在 GitHub 基于 tag **发布 Release**（写好说明）→ 工作流自动打包并把 DMG/ZIP 挂上 Release。

## 验收

- 本地：`./scripts/package-release.sh 0.1.0` 产出 zip+dmg；DMG 挂载后含 `.app` 与 `Applications` 替身；zip 解压后 `codesign -dv` 通过；Info.plist 版本号 = 0.1.0
- CI：workflow 语法与权限就绪（真实触发待首次发布验证）
- 不触碰并行会话在途文件；文档同步（README 安装小节、arm64 要求、CONTRIBUTING 发布流程、CHANGELOG 条目）在其落盘后补提交
