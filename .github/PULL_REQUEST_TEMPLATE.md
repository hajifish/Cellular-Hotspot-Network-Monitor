<!-- 提交前请阅读 CONTRIBUTING.md（English: CONTRIBUTING.en.md） -->

## 摘要 Summary

<!-- 这个 PR 改了什么、为什么改？/ What does this PR change, and why? -->

## 关联 issue Related issues

<!-- 例如：Fixes #12 -->

## PR 类型 Type（Gitflow）

- [ ] `feature/*` → `develop`
- [ ] `bugfix/*` → `develop`
- [ ] `release/*` / `hotfix/*` → `main`（维护者 maintainers）

## 自检清单 Checklist

- [ ] 分支基于最新 `develop`，PR 指向 `develop`（branch cut from latest `develop`）
- [ ] 提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] `swift build` 通过（passes）
- [ ] `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` 通过；行为变更已附/更新自测
      （self-tests added or updated for behavior changes）
- [ ] 用户可见变更已同步 `README.md` 与 `README.en.md`，并记入 `CHANGELOG.md` 的 `[Unreleased]`
      （docs and changelog updated for user-facing changes）
