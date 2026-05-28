#!/bin/bash
# Ralph Auto Runner - 一键停止

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "停止 Ralph Auto Runner..."

# 停止 Notifier
if [ -f "$PROJECT_DIR/.notifier.pid" ]; then
  PID=$(cat "$PROJECT_DIR/.notifier.pid")
  kill "$PID" 2>/dev/null && echo "  ✓ Notifier (PID $PID) 已停止" || echo "  - Notifier 已不在运行"
  rm -f "$PROJECT_DIR/.notifier.pid"
fi

# 停止 Watchdog
if [ -f "$PROJECT_DIR/.watchdog.pid" ]; then
  PID=$(cat "$PROJECT_DIR/.watchdog.pid")
  kill "$PID" 2>/dev/null && echo "  ✓ Watchdog (PID $PID) 已停止" || echo "  - Watchdog 已不在运行"
  rm -f "$PROJECT_DIR/.watchdog.pid"
fi

# 停止 Ralph
if [ -f "$PROJECT_DIR/.ralph.pid" ]; then
  PID=$(cat "$PROJECT_DIR/.ralph.pid")
  kill "$PID" 2>/dev/null && echo "  ✓ Ralph (PID $PID) 已停止" || echo "  - Ralph 已不在运行"
  rm -f "$PROJECT_DIR/.ralph.pid"
fi

# 停止所有相关 claude 进程（可选，谨慎使用）
# pkill -f "claude.*dangerously-skip-permissions" 2>/dev/null || true

echo ""
echo "已停止所有进程。"
echo "进度已保存在 checkpoint.json，下次启动会自动恢复。"
