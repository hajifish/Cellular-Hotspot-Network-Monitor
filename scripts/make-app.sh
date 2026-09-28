#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"

APP="Traffic Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/TrafficMonitor" "$APP/Contents/MacOS/TrafficMonitor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TrafficMonitor</string>
    <key>CFBundleIdentifier</key><string>local.shin.TrafficMonitor</string>
    <key>CFBundleName</key><string>Traffic Monitor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "Built ./$APP"
