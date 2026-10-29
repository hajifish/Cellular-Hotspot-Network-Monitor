#!/bin/bash
# 打包发布产物：release 构建 .app → 注入版本号 → ZIP + DMG，输出到 dist/。
# 用法: ./scripts/package-release.sh <version> [output-dir]
#   version  取 Release tag（容忍 v 前缀，如 v0.1.0 → 0.1.0）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: package-release.sh <version> [output-dir]}"
VERSION="${VERSION#v}"
OUT="${2:-dist}"

./scripts/make-app.sh

APP="Traffic Monitor.app"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
codesign --force -s - "$APP"

mkdir -p "$OUT"
rm -f "$OUT/TrafficMonitor-$VERSION.zip" "$OUT/TrafficMonitor-$VERSION.dmg"

# ZIP：ditto 保留签名与扩展属性（Homebrew Cask 兼容格式）
ditto -c -k --keepParent "$APP" "$OUT/TrafficMonitor-$VERSION.zip"

# DMG：拖拽安装布局（.app + Applications 替身）
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Traffic Monitor $VERSION" \
  -srcfolder "$STAGE" -ov -format UDZO \
  "$OUT/TrafficMonitor-$VERSION.dmg" >/dev/null

echo "打包完成:"
ls -lh "$OUT/TrafficMonitor-$VERSION.zip" "$OUT/TrafficMonitor-$VERSION.dmg"
