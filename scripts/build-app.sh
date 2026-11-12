#!/usr/bin/env bash
# 打包菜单栏客户端为 dist/Dingdong.app
#   VERSION=1.2.0 UNIVERSAL=1 ./scripts/build-app.sh   # 发布用：Intel + Apple 芯片通用
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.0.0-dev}"
cd "$ROOT/client"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi
APP="$ROOT/dist/Dingdong.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Dingdong" "$APP/Contents/MacOS/Dingdong"
[ -f "$ROOT/client/Resources/AppIcon.icns" ] && cp "$ROOT/client/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Dingdong</string>
  <key>CFBundleDisplayName</key><string>叮咚</string>
  <key>CFBundleIdentifier</key><string>local.dingdong.menubar</string>
  <key>CFBundleExecutable</key><string>Dingdong</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>local.dingdong.connect</string>
    <key>CFBundleURLSchemes</key><array><string>dingdong</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ $APP ($VERSION)"
