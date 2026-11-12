#!/usr/bin/env bash
# 叮咚 × Claude Code：一行安装钩子
#   curl -fsSL https://raw.githubusercontent.com/xingqiux/dingdong/main/integrations/claude-code/install.sh | bash -s -- <服务器地址> <令牌>
#   ... | bash -s -- --uninstall
# 选项：--min-seconds N（一轮跑多久以上才通知「做完了」，默认 60）
# 会装到 ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json，原文件先备份；已有的其他 hooks 原样保留。
set -euo pipefail

RAW="https://raw.githubusercontent.com/xingqiux/dingdong/main/integrations/claude-code/claude-code-hook.py"
CONF_DIR="$HOME/.config/dingdong"
HOOK="$CONF_DIR/claude-code-hook.py"
ENV_FILE="$CONF_DIR/claude-code.env"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
MIN=60
ACTION=install
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) ACTION=uninstall ;;
    --min-seconds) MIN="$2"; shift ;;
    -h|--help) sed -n '2,6p' "$0" 2>/dev/null || true; exit 0 ;;
    *) POS+=("$1") ;;
  esac
  shift
done

command -v python3 >/dev/null || { echo "需要 python3（macOS 上运行 xcode-select --install 即可）" >&2; exit 1; }

merge() { # $1 = install|uninstall
  python3 - "$SETTINGS" "$1" "$HOOK" <<'PY'
import json, os, sys, shutil, time
path, action, hook = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
    shutil.copy(path, f"{path}.bak-dingdong-{time.strftime('%Y%m%d%H%M%S')}")
hooks = data.setdefault("hooks", {})
for event in ("Stop", "Notification"):
    groups = [g for g in hooks.get(event, [])
              if not any("claude-code-hook.py" in h.get("command", "") and "dingdong" in h.get("command", "")
                         for h in g.get("hooks", []))]
    if action == "install":
        groups.append({"hooks": [{"type": "command", "command": f"python3 {hook}", "timeout": 10, "async": True}]})
    if groups:
        hooks[event] = groups
    else:
        hooks.pop(event, None)
if not hooks:
    data.pop("hooks", None)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

if [ "$ACTION" = uninstall ]; then
  merge uninstall
  echo "✓ 已从 $SETTINGS 移除叮咚钩子（配置 ${ENV_FILE} 保留，可手动删除）"
  exit 0
fi

URL="${POS[0]:-${DINGDONG_URL:-}}"
TOKEN="${POS[1]:-${DINGDONG_TOKEN:-}}"
[ -n "$URL" ] && [ -n "$TOKEN" ] || { echo "用法: install.sh <服务器地址> <令牌>" >&2; exit 2; }
URL="${URL%/}"

mkdir -p "$CONF_DIR"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/claude-code-hook.py"
if [ -f "$SRC" ]; then cp "$SRC" "$HOOK"; else curl -fsSL "$RAW" -o "$HOOK"; fi
chmod 755 "$HOOK"
umask 077
cat > "$ENV_FILE" <<EOF
DINGDONG_URL=$URL
DINGDONG_TOKEN=$TOKEN
DINGDONG_MIN_SECONDS=$MIN
EOF
merge install

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/api/notify" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Claude Code 接上啦","body":"以后任务跑完或者需要你确认时，小猫会叫你。","source":"Claude Code","level":"success"}' || true)
echo "✓ 钩子已装到 $SETTINGS"
echo "  配置：${ENV_FILE}（超过 ${MIN} 秒的任务做完才通知）"
if [ "$code" = 201 ] || [ "$code" = 200 ]; then echo "✓ 已发一条测试通知"; else echo "⚠ 测试通知没发出去（HTTP $code），检查地址和令牌"; fi
echo "  重启 Claude Code 会话后生效。卸载：install.sh --uninstall"
