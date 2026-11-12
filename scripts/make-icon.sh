#!/bin/bash
# 从 docs/assets/logo.svg 生成 macOS AppIcon.icns（输出到 .build/AppIcon.icns）。
# 仅用系统自带工具：qlmanage(WebKit 渲染 SVG，滤镜/渐变保真) + sips + iconutil。
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="docs/assets/logo.svg"
TMP=".build/icon-master.png"
OUT=".build/AppIcon.iconset"
ICNS=".build/AppIcon.icns"

mkdir -p .build "$OUT"
rm -f "$OUT"/*.png "$TMP"

# 渲染 1024 母版
qlmanage -t -s 1024 -o .build "$SRC" >/dev/null 2>&1
mv ".build/$(basename "$SRC").png" "$TMP"

# 缩放出 iconset 全部 10 个尺寸
for spec in "icon_16x16:16" "icon_16x16@2x:32" "icon_32x32:32" "icon_32x32@2x:64" \
            "icon_128x128:128" "icon_128x128@2x:256" "icon_256x256:256" "icon_256x256@2x:512" \
            "icon_512x512:512" "icon_512x512@2x:1024"; do
    name="${spec%%:*}"; px="${spec##*:}"
    sips -z "$px" "$px" "$TMP" --out "$OUT/$name.png" >/dev/null
done
rm -f "$TMP"

iconutil -c icns "$OUT" -o "$ICNS"
echo "Generated $ICNS"
