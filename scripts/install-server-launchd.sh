#!/usr/bin/env bash
# 把服务端装成本机后台服务（登录后自动启动，崩了自动拉起）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$HOME/Library/Application Support/Dingdong"
BIN="$DATA/dingdong-server"
PLIST="$HOME/Library/LaunchAgents/local.dingdong.server.plist"
mkdir -p "$DATA"
(cd "$ROOT/server" && go build -o "$BIN" .)
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.dingdong.server</string>
  <key>ProgramArguments</key><array>
    <string>$BIN</string><string>-addr</string><string>127.0.0.1:8787</string>
    <string>-data</string><string>$DATA</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$DATA/server.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/local.dingdong.server" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 1
echo "✓ 服务已启动: http://127.0.0.1:8787"
echo "  token: $(cat "$DATA/token")"
