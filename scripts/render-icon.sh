#!/usr/bin/env bash
# 用 App 里的猫咪矢量图重新生成图标：client/Resources/AppIcon.icns 和 docs/icon.png
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/client"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)/Dingdong"
TMP="$(mktemp -d)"
"$BIN" --render-icon "$TMP/icon_1024.png" 1024
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z $d $d "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p "$ROOT/client/Resources" "$ROOT/docs"
iconutil -c icns "$SET" -o "$ROOT/client/Resources/AppIcon.icns"
sips -z 512 512 "$TMP/icon_1024.png" --out "$ROOT/docs/icon.png" >/dev/null
rm -rf "$TMP"
echo "✓ client/Resources/AppIcon.icns, docs/icon.png"
