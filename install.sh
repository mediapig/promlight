#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Applications/PromLight"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ── 检测 python3 ──────────────────────────────────────────────
PYTHON=$(command -v python3 2>/dev/null || true)
[ -z "$PYTHON" ] && err "未找到 python3，请先安装 Python 3"
info "Python: $PYTHON ($($PYTHON --version 2>&1))"

# ── 复制文件 ──────────────────────────────────────────────────
echo
echo "安装到 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

cp -r "$REPO_DIR/PromLight.app" "$INSTALL_DIR/"
cp "$REPO_DIR/agent_hook.py"   "$INSTALL_DIR/"
cp "$REPO_DIR/events.json"     "$INSTALL_DIR/"

if [ ! -f "$INSTALL_DIR/devices.json" ]; then
    cp "$REPO_DIR/devices.json" "$INSTALL_DIR/"
    warn "已创建 devices.json，请按需编辑设备序列号"
else
    info "devices.json 已存在，跳过（如需更新请手动编辑）"
fi

info "文件已安装"

# ── 写入 Claude Code hooks ────────────────────────────────────
echo
echo "更新 Claude Code hooks ($CLAUDE_SETTINGS) ..."
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

INSTALL_DIR="$INSTALL_DIR" PYTHON="$PYTHON" CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
$PYTHON << 'PYEOF'
import json, os

install_dir    = os.environ["INSTALL_DIR"]
python_bin     = os.environ["PYTHON"]
settings_path  = os.path.expanduser(os.environ["CLAUDE_SETTINGS"])

settings = {}
if os.path.exists(settings_path):
    with open(settings_path, "r", encoding="utf-8") as f:
        settings = json.load(f)

hooks = settings.setdefault("hooks", {})

WITH_MATCHER    = {"PreToolUse", "PostToolUse", "PermissionRequest", "PermissionDenied", "Elicitation"}
WITHOUT_MATCHER = {"SessionStart", "UserPromptSubmit", "StopFailure", "Stop", "SessionEnd"}

for event in WITH_MATCHER | WITHOUT_MATCHER:
    cmd   = f"{python_bin} {install_dir}/agent_hook.py --agent claude {event}"
    entry = {"hooks": [{"type": "command", "command": cmd}]}
    if event in WITH_MATCHER:
        entry["matcher"] = "*"
    # 移除旧的 PromLight 条目，避免重复
    existing = [
        e for e in hooks.get(event, [])
        if not any("agent_hook.py" in h.get("command", "") for h in e.get("hooks", []))
    ]
    existing.append(entry)
    hooks[event] = existing

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("  Hooks 已写入")
PYEOF

info "Claude Code hooks 已配置"

# ── 启动 daemon ───────────────────────────────────────────────
echo
echo "启动 PromLight daemon ..."
# 若已在运行则先退出再重启，确保使用最新版本
if pgrep -x "PromLight" > /dev/null 2>&1; then
    pkill -x "PromLight" || true
    sleep 0.5
fi
open "$INSTALL_DIR/PromLight.app"
info "Daemon 已启动"

# ── 完成 ──────────────────────────────────────────────────────
echo
echo "✅ 安装完成"
echo "   Daemon  : $INSTALL_DIR/PromLight.app"
echo "   Hook    : $INSTALL_DIR/agent_hook.py"
echo "   灯光配置: $INSTALL_DIR/events.json"
echo "   设备配置: $INSTALL_DIR/devices.json"
echo
echo "   重启 Claude Code 后 hooks 生效。"
