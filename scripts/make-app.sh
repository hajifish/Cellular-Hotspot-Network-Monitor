#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"
./scripts/make-icon.sh

APP="Traffic Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/TrafficMonitor" "$APP/Contents/MacOS/TrafficMonitor"
cp ".build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "Assets/default-background.png" "$APP/Contents/Resources/default-background.png"
cp ".build/notification-icon.png" "$APP/Contents/Resources/notification-icon.png"
# 挡住「图在但损坏」：sips 解不出尺寸即非零退出（与缺图同级的打包失败）
sips -g pixelWidth "$APP/Contents/Resources/default-background.png" >/dev/null
sips -g pixelWidth "$APP/Contents/Resources/notification-icon.png" >/dev/null
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TrafficMonitor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.shin.TrafficMonitor</string>
    <key>CFBundleName</key><string>Traffic Monitor</string>
    <key>CFBundleDisplayName</key><string>Traffic Monitor</string>
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
