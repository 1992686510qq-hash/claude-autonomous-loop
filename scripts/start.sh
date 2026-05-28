#!/bin/bash
# Ralph Auto Runner - 一键启动
#
# 用法: bash start.sh [--notify chat_id]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 解析参数
CHAT_ID=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --notify) CHAT_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "========================================="
echo "  Ralph Auto Runner - 启动"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 检查必要文件
if [ ! -f "$PROJECT_DIR/CLAUDE.md" ]; then
  echo "Error: CLAUDE.md 不存在，请先创建"
  exit 1
fi

if [ ! -f "$PROJECT_DIR/prd.json" ]; then
  echo "Error: prd.json 不存在，请先创建"
  exit 1
fi

# 初始化（如果需要）
bash "$SCRIPT_DIR/init.sh"

echo ""
echo "启动进程..."

# 启动看门狗（它会自动启动 Ralph）
nohup bash "$SCRIPT_DIR/watchdog.sh" > "$PROJECT_DIR/watchdog.log" 2>&1 &
WATCHDOG_PID=$!
echo "$WATCHDOG_PID" > "$PROJECT_DIR/.watchdog.pid"
echo "  ✓ Watchdog (PID: $WATCHDOG_PID)"

# 启动通知器（如果配置了 CHAT_ID）
if [ -n "$CHAT_ID" ]; then
  export CHAT_ID
  nohup bash "$SCRIPT_DIR/notifier.sh" > "$PROJECT_DIR/notifier.log" 2>&1 &
  NOTIFIER_PID=$!
  echo "$NOTIFIER_PID" > "$PROJECT_DIR/.notifier.pid"
  echo "  ✓ Notifier (PID: $NOTIFIER_PID, CHAT_ID: $CHAT_ID)"
else
  echo "  - Notifier 未启动（未配置 --notify chat_id）"
fi

echo ""
echo "启动完成！"
echo ""
echo "监控命令:"
echo "  bash scripts/status.sh    # 查看状态"
echo "  tail -f watchdog.log      # 看门狗日志"
echo "  tail -f ralph.log         # Ralph 日志"
echo "  tail -f progress.txt      # 进度日志"
echo ""
echo "停止命令:"
echo "  bash scripts/stop.sh"
