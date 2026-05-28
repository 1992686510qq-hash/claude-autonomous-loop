#!/bin/bash
# Ralph Auto Runner - 主循环调度器
# 每轮启动一个 claude 进程执行一个 story，直到全部完成
#
# 用法: bash ralph.sh [--tool claude] [max_iterations]

set -e

# 解析参数
TOOL="claude"
MAX_ITERATIONS=100

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool) TOOL="$2"; shift 2 ;;
    --tool=*) TOOL="${1#*=}"; shift ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift ;;
  esac
done

if [[ "$TOOL" != "claude" ]]; then
  echo "Error: 目前只支持 --tool claude"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_FILE="$PROJECT_DIR/CLAUDE.md"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"

if [ ! -f "$CLAUDE_FILE" ]; then
  echo "Error: CLAUDE.md 不存在于 $PROJECT_DIR"
  exit 1
fi

# 初始化进度文件
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
echo "CLAUDE.md: $CLAUDE_FILE"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==============================================================="

  # 启动 Claude 进程
  OUTPUT=$(claude --dangerously-skip-permissions --print < "$CLAUDE_FILE" 2>&1 | tee /dev/stderr) || true

  # 检测完成信号
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "========================================="
    echo "  Ralph completed all tasks!"
    echo "  Iteration: $i / $MAX_ITERATIONS"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
    exit 0
  fi

  # 检测 429 限流
  if echo "$OUTPUT" | grep -qi "429\|rate.limit\|too many requests"; then
    echo "[ralph] 检测到 429 限流，等待 30 秒..."
    sleep 30
  fi

  echo ""
  echo "Iteration $i complete. Continuing..."
  sleep 10
done

echo ""
echo "========================================="
echo "  Ralph reached max iterations ($MAX_ITERATIONS)"
echo "  Check $PROGRESS_FILE for status"
echo "========================================="
exit 1
