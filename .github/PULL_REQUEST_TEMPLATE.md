## Summary

<!-- What does this PR change, and why? -->

## Related issues

<!-- e.g. Fixes #12 -->

## PR type (Gitflow)

- [ ] `feature/*` → `develop`
- [ ] `bugfix/*` → `develop`
- [ ] `release/*` / `hotfix/*` → `main` (maintainers)

## Checklist

- [ ] Branch cut from the latest `develop`; PR targets `develop`
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] `swift build` succeeds
- [ ] `TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor` passes;
      self-tests added/updated for behavior changes
- [ ] Docs updated (`README.md` + `README.zh-CN.md`) and
      `CHANGELOG.md` `[Unreleased]` for user-facing changes
