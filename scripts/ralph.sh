#!/bin/bash
# Ralph Auto Runner - 主循环调度器
# 每轮启动一个 claude 进程执行一个 story，直到全部完成
#
# 用法: bash ralph.sh [--tool claude] [max_iterations]
#       bash ralph.sh --max-tokens 50000000 --max-cost 50

set -e

# 解析参数
TOOL="claude"
MAX_ITERATIONS=100
MAX_TOKENS=0    # 0 = 不限制
MAX_COST_USD=0  # 0 = 不限制
USE_DAG=false
MAX_PARALLEL=3

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool) TOOL="$2"; shift 2 ;;
    --tool=*) TOOL="${1#*=}"; shift ;;
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    --max-cost) MAX_COST_USD="$2"; shift 2 ;;
    --dag) USE_DAG=true; shift ;;
    --max-parallel) MAX_PARALLEL="$2"; shift 2 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift ;;
  esac
done

# DAG 模式：委托给 dag-scheduler.sh
if [ "$USE_DAG" = true ]; then
  exec bash "$SCRIPT_DIR/dag-scheduler.sh" \
    ${MAX_TOKENS:+--max-tokens $MAX_TOKENS} \
    ${MAX_COST_USD:+--max-cost $MAX_COST_USD} \
    --max-parallel "$MAX_PARALLEL"
fi

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

CONTEXT_FILE="$PROJECT_DIR/.loop-context.md"

# Token 预算检查
check_budget() {
  if [ "$MAX_TOKENS" -eq 0 ] && [ "$MAX_COST_USD" -eq 0 ]; then
    return 0  # 无预算限制
  fi

  # 用 monitor.py 统计当前 token 消耗
  local stats
  stats=$(python "$SCRIPT_DIR/monitor/monitor.py" "$PROJECT_DIR" --once --json 2>/dev/null) || return 0

  local total_tokens
  total_tokens=$(echo "$stats" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('cumulative',{}).get('input',0)+d.get('cumulative',{}).get('output',0))" 2>/dev/null) || return 0

  if [ "$MAX_TOKENS" -gt 0 ] && [ "$total_tokens" -gt "$MAX_TOKENS" ]; then
    echo "[ralph] BUDGET_EXCEEDED: tokens=$total_tokens > max=$MAX_TOKENS"
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] BUDGET_EXCEEDED: tokens=$total_tokens > max=$MAX_TOKENS" >> "$PROGRESS_FILE"
    return 1
  fi

  # 粗略估算成本（mimo-v2.5-pro: 约 ¥0.002/千token）
  if [ "$MAX_COST_USD" -gt 0 ]; then
    local cost_usd
    cost_usd=$(echo "$total_tokens" | awk '{printf "%.2f", $1 * 0.000003}')
    if [ "$(echo "$cost_usd > $MAX_COST_USD" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
      echo "[ralph] BUDGET_EXCEEDED: cost=\$$cost_usd > max=\$$MAX_COST_USD"
      echo "[$(date '+%Y-%m-%dT%H:%M:%S')] BUDGET_EXCEEDED: cost=\$$cost_usd > max=\$$MAX_COST_USD" >> "$PROGRESS_FILE"
      return 1
    fi
  fi

  return 0
}

# 自动摘要：压缩上一轮的输出，注入下一轮上下文
summarize_iteration() {
  local iter=$1
  local output="$2"

  # 从 progress.txt 取最近 30 行作为摘要输入
  local recent
  recent=$(tail -30 "$PROGRESS_FILE" 2>/dev/null)

  # 调用轻量 Claude 做摘要（限制 500 token 输出）
  local summary
  summary=$(echo "用 2-3 句话总结以下任务执行的关键信息。只输出摘要，不要其他内容。

最近进度:
$recent

输出格式:
- 本轮完成了哪些任务
- 关键产出文件
- 遇到的问题（如有）" | claude --print 2>/dev/null | head -20) || return 0

  # 写入上下文文件
  if [ -n "$summary" ]; then
    echo "# 迭代 $iter 摘要 ($(date '+%Y-%m-%d %H:%M:%S'))" > "$CONTEXT_FILE"
    echo "" >> "$CONTEXT_FILE"
    echo "$summary" >> "$CONTEXT_FILE"
    echo "[ralph] 摘要已写入 $CONTEXT_FILE"
  fi
}

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
if [ "$MAX_TOKENS" -gt 0 ]; then echo "Token budget: $MAX_TOKENS"; fi
if [ "$MAX_COST_USD" -gt 0 ]; then echo "Cost budget: \$$MAX_COST_USD"; fi
echo "CLAUDE.md: $CLAUDE_FILE"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "==============================================================="

  # 检查 Token 预算
  if ! check_budget; then
    echo ""
    echo "========================================="
    echo "  Ralph stopped: budget exceeded"
    echo "  Iteration: $i / $MAX_ITERATIONS"
    echo "========================================="
    exit 2
  fi

  # 注入上下文摘要（如果有）
  CLAUDE_INPUT="$CLAUDE_FILE"
  if [ -f "$CONTEXT_FILE" ]; then
    CLAUDE_INPUT=$(mktemp)
    echo "# 上一轮摘要" > "$CLAUDE_INPUT"
    cat "$CONTEXT_FILE" >> "$CLAUDE_INPUT"
    echo "" >> "$CLAUDE_INPUT"
    echo "---" >> "$CLAUDE_INPUT"
    echo "" >> "$CLAUDE_INPUT"
    cat "$CLAUDE_FILE" >> "$CLAUDE_INPUT"
  fi

  # 启动 Claude 进程
  OUTPUT=$(claude --dangerously-skip-permissions --print < "$CLAUDE_INPUT" 2>&1 | tee /dev/stderr) || true

  # 清理临时文件
  if [ "$CLAUDE_INPUT" != "$CLAUDE_FILE" ]; then
    rm -f "$CLAUDE_INPUT"
  fi

  # 自动摘要
  summarize_iteration "$i" "$OUTPUT"

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
