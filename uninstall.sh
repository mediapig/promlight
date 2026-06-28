#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/Applications/PromLight"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }

# ── 停止 daemon ───────────────────────────────────────────────
echo "停止 PromLight daemon ..."
if pgrep -x "PromLight" > /dev/null 2>&1; then
    pkill -x "PromLight" || true
    info "Daemon 已停止"
else
    warn "Daemon 未在运行，跳过"
fi

# ── 移除 Claude Code hooks ────────────────────────────────────
PYTHON=$(command -v python3 2>/dev/null || true)
if [ -n "$PYTHON" ] && [ -f "$CLAUDE_SETTINGS" ]; then
    echo "移除 Claude Code hooks ($CLAUDE_SETTINGS) ..."
    CLAUDE_SETTINGS="$CLAUDE_SETTINGS" $PYTHON << 'PYEOF'
import json, os

settings_path = os.path.expanduser(os.environ["CLAUDE_SETTINGS"])
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
for event in list(hooks.keys()):
    hooks[event] = [
        e for e in hooks[event]
        if not any("agent_hook.py" in h.get("command", "") for h in e.get("hooks", []))
    ]
    if not hooks[event]:
        del hooks[event]

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("  Hooks 已移除")
PYEOF
    info "Hooks 已清理"
else
    warn "未找到 python3 或 settings.json，跳过 hooks 清理（请手动编辑 $CLAUDE_SETTINGS）"
fi

# ── 删除安装目录 ──────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
    echo
    echo "将删除 $INSTALL_DIR"
    read -r -p "确认删除？[y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf -- "$INSTALL_DIR"
        info "安装目录已删除"
    else
        warn "已跳过，安装目录保留"
    fi
else
    warn "$INSTALL_DIR 不存在，跳过"
fi

echo
echo "✅ 卸载完成。重启 Claude Code 后 hooks 失效。"
