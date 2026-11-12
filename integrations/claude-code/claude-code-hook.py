#!/usr/bin/env python3
"""叮咚 × Claude Code：任务跑完、或者需要你确认时，推一条通知到 Mac 菜单栏。

由 Claude Code 的 hooks 调用（Stop / Notification），从 stdin 读事件 JSON。
配置在 ~/.config/dingdong/claude-code.env：
    DINGDONG_URL=https://ding.example.com
    DINGDONG_TOKEN=dds_xxx          # 在叮咚「接入 AI」里给 Claude Code 建的令牌
    DINGDONG_MIN_SECONDS=60         # 一轮对话跑了多久以上才通知「做完了」
只用标准库；出任何错都静默退出，绝不影响 Claude Code。
"""
import json
import os
import pathlib
import re
import sys
import time
import urllib.request
from datetime import datetime

CONFIG = pathlib.Path(os.environ.get("DINGDONG_CONFIG", "~/.config/dingdong/claude-code.env")).expanduser()


def load_config():
    cfg = {"DINGDONG_MIN_SECONDS": "60"}
    try:
        for line in CONFIG.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    for k in ("DINGDONG_URL", "DINGDONG_TOKEN", "DINGDONG_MIN_SECONDS"):
        if os.environ.get(k):
            cfg[k] = os.environ[k]
    return cfg


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def is_real_prompt(entry):
    """用户亲手发的消息（不是工具结果、不是系统注入的元信息）"""
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isSidechain"):
        return False
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        return not content.lstrip().startswith(("<command-", "<local-command", "<system-reminder"))
    if isinstance(content, list):
        kinds = {c.get("type") for c in content if isinstance(c, dict)}
        return "tool_result" not in kinds and ("text" in kinds or "image" in kinds)
    return False


def read_transcript(path):
    """返回 (会话标题, 最近一次用户提问的时间戳, Claude 最后一段文字)"""
    custom, ai, prompt_ts, last_text = None, None, None, None
    try:
        with open(path, "rb") as f:
            lines = f.read().splitlines()
    except (OSError, TypeError):
        return None, None, None
    for raw in lines:  # 用户自己起的标题优先，其次是自动生成的
        if b'"customTitle"' in raw or b'"aiTitle"' in raw:
            try:
                e = json.loads(raw)
            except ValueError:
                continue
            custom = e.get("customTitle") or custom
            ai = e.get("aiTitle") or ai
    for raw in reversed(lines):
        if b'"type":"user"' not in raw and b'"type":"assistant"' not in raw:
            continue
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if last_text is None and e.get("type") == "assistant" and not e.get("isSidechain"):
            content = (e.get("message") or {}).get("content")
            if isinstance(content, list):
                texts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
                if any(t.strip() for t in texts):
                    last_text = "\n".join(texts)
        if is_real_prompt(e):
            prompt_ts = parse_ts(e.get("timestamp", ""))
            break
    return custom or ai, prompt_ts, last_text


def tidy(text, limit):
    text = re.sub(r"```.*?```", " ", text or "", flags=re.S)       # 去掉代码块
    text = re.sub(r"[`*_#>|]+", "", text)                           # 去掉 markdown 符号
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)            # 链接只留文字
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def human_duration(sec):
    sec = int(sec)
    if sec < 60:
        return f"{sec} 秒"
    if sec < 3600:
        return f"{sec // 60} 分钟"
    return f"{sec // 3600} 小时 {sec % 3600 // 60} 分"


def send(cfg, title, body, level):
    url = cfg.get("DINGDONG_URL", "").rstrip("/")
    token = cfg.get("DINGDONG_TOKEN", "")
    if not url or not token:
        return
    req = urllib.request.Request(
        url + "/api/notify",
        data=json.dumps({"title": title, "body": body, "source": "Claude Code", "level": level}).encode(),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json",
                 "User-Agent": "dingdong-claude-code-hook"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=6).read()


def main():
    event = json.load(sys.stdin)
    cfg = load_config()
    name = event.get("hook_event_name", "")
    project = os.path.basename((event.get("cwd") or "").rstrip("/")) or "Claude Code"
    title, prompt_ts, last_text = read_transcript(event.get("transcript_path"))
    where = tidy(title or project, 40)

    if name == "Stop":
        if event.get("stop_hook_active"):
            return
        elapsed = time.time() - prompt_ts if prompt_ts else None
        if elapsed is None or elapsed < float(cfg.get("DINGDONG_MIN_SECONDS", 60)):
            return  # 短问答不打扰
        summary = tidy(event.get("last_assistant_message") or last_text or "", 140)
        body = f"用时 {human_duration(elapsed)}" + (f" · {summary}" if summary else "")
        send(cfg, f"做完了 · {where}", body, "success")
    elif name == "Notification":
        kind = event.get("notification_type", "")
        if kind in ("auth_success",):
            return
        msg = tidy(event.get("message", ""), 160)
        needs_permission = kind == "permission_prompt" or "permission" in msg.lower()
        head = "需要你确认" if needs_permission else "在等你回复"
        send(cfg, f"{head} · {where}", msg or head, "warning")


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 — 通知失败也不能影响 Claude Code
        pass
    sys.exit(0)
