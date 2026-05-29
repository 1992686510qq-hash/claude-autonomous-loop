#!/bin/bash
# Ralph Auto Runner - DAG 依赖调度器
# 支持 dependsOn 字段，无依赖的任务并行执行
#
# 用法: bash dag-scheduler.sh [--max-tokens N] [--max-cost N] [--max-parallel N]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_FILE="$PROJECT_DIR/CLAUDE.md"
PRD_FILE="$PROJECT_DIR/prd.json"
CHECKPOINT_FILE="$PROJECT_DIR/checkpoint.json"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"
HEARTBEAT_FILE="$PROJECT_DIR/heartbeat.json"
CONTEXT_FILE="$PROJECT_DIR/.loop-context.md"
PID_DIR="$PROJECT_DIR/.dag-pids"

MAX_TOKENS=0
MAX_COST_USD=0
MAX_PARALLEL=3

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    --max-cost) MAX_COST_USD="$2"; shift 2 ;;
    --max-parallel) MAX_PARALLEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# 初始化
mkdir -p "$PID_DIR"
mkdir -p "$(dirname "$PROGRESS_FILE")"
[ -f "$PROGRESS_FILE" ] || { echo "# Ralph DAG Progress" > "$PROGRESS_FILE"; echo "---" >> "$PROGRESS_FILE"; }

# 用 node 读取 prd.json 和 checkpoint.json 的工具函数
read_prd() {
  node -e "
    const fs = require('fs');
    const prd = JSON.parse(fs.readFileSync('$PRD_FILE', 'utf8'));
    const cp = (() => { try { return JSON.parse(fs.readFileSync('$CHECKPOINT_FILE', 'utf8')); } catch(e) { return {}; } })();
    const stories = prd.userStories || prd.stories || [];
    console.log(JSON.stringify(stories.map(s => ({
      id: s.id,
      title: s.title,
      priority: s.priority,
      passes: s.passes || false,
      dependsOn: s.dependsOn || [],
      done: !!cp[s.id]
    }))));
  " 2>/dev/null
}

# 找出所有 ready 的 story（passes=false 且 dependsOn 全部 done）
find_ready() {
  node -e "
    const stories = JSON.parse(process.argv[1]);
    const doneIds = new Set(stories.filter(s => s.done || s.passes).map(s => s.id));
    const running = new Set(process.argv[2] ? process.argv[2].split(',') : []);
    const ready = stories.filter(s =>
      !s.done && !s.passes &&
      !running.has(s.id) &&
      s.dependsOn.every(d => doneIds.has(d))
    );
    console.log(JSON.stringify(ready.map(s => s.id)));
  " "$(read_prd)" "$(ls "$PID_DIR" 2>/dev/null | tr '\n' ',')" 2>/dev/null
}

# 检查是否全部完成
check_all_done() {
  node -e "
    const stories = JSON.parse(process.argv[1]);
    const allDone = stories.every(s => s.done || s.passes);
    console.log(allDone ? 'DONE' : 'PENDING');
  " "$(read_prd)" 2>/dev/null
}

# 检查是否有正在运行的进程
running_count() {
  local count=0
  for pidfile in "$PID_DIR"/*; do
    [ -f "$pidfile" ] || continue
    local pid=$(cat "$pidfile" 2>/dev/null)
    if kill -0 "$pid" 2>/dev/null; then
      count=$((count + 1))
    else
      rm -f "$pidfile"
    fi
  done
  echo $count
}

# 清理已完成的进程
cleanup_finished() {
  for pidfile in "$PID_DIR"/*; do
    [ -f "$pidfile" ] || continue
    local pid=$(cat "$pidfile" 2>/dev/null)
    local story_id=$(basename "$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pidfile"
      echo "[dag] $story_id 进程结束 (PID $pid)"
    fi
  done
}

# 启动一个 story
launch_story() {
  local story_id=$1

  # 检查是否已在运行
  if [ -f "$PID_DIR/$story_id" ]; then
    return 0
  fi

  echo "[dag] 启动 $story_id"

  # 构建输入（注入上下文摘要）
  local claude_input="$CLAUDE_FILE"
  if [ -f "$CONTEXT_FILE" ]; then
    claude_input=$(mktemp)
    echo "# 上一轮摘要" > "$claude_input"
    cat "$CONTEXT_FILE" >> "$claude_input"
    echo "" >> "$claude_input"
    echo "---" >> "$claude_input"
    cat "$CLAUDE_FILE" >> "$claude_input"
  fi

  # 在后台启动 claude
  (
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$claude_input" 2>&1) || true

    # 写完成标记
    echo "$OUTPUT" > "$PID_DIR/$story_id.output"

    # 检查是否成功
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>\|checkpoint\|done"; then
      echo "done" > "$PID_DIR/$story_id.status"
    else
      echo "fail" > "$PID_DIR/$story_id.status"
    fi
  ) &

  local pid=$!
  echo "$pid" > "$PID_DIR/$story_id"

  # 清理临时文件
  if [ "$claude_input" != "$CLAUDE_FILE" ]; then
    rm -f "$claude_input"
  fi
}

# Token 预算检查
check_budget() {
  if [ "$MAX_TOKENS" -eq 0 ] && [ "$MAX_COST_USD" -eq 0 ]; then
    return 0
  fi
  local stats
  stats=$(python "$SCRIPT_DIR/monitor/monitor.py" "$PROJECT_DIR" --once --json 2>/dev/null) || return 0
  local total_tokens
  total_tokens=$(echo "$stats" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('cumulative',{}).get('input',0)+d.get('cumulative',{}).get('output',0))" 2>/dev/null) || return 0
  if [ "$MAX_TOKENS" -gt 0 ] && [ "$total_tokens" -gt "$MAX_TOKENS" ]; then
    echo "[dag] BUDGET_EXCEEDED: tokens=$total_tokens > max=$MAX_TOKENS"
    return 1
  fi
  return 0
}

# ─── 主循环 ─────────────────────────────────────────────

echo "========================================="
echo "  Ralph DAG Scheduler"
echo "  Max parallel: $MAX_PARALLEL"
if [ "$MAX_TOKENS" -gt 0 ]; then echo "  Token budget: $MAX_TOKENS"; fi
echo "========================================="

while true; do
  # 检查预算
  if ! check_budget; then
    echo "[dag] 预算超限，停止调度"
    break
  fi

  # 清理已完成的进程
  cleanup_finished

  # 检查是否全部完成
  STATUS=$(check_all_done)
  if [ "$STATUS" = "DONE" ]; then
    echo ""
    echo "========================================="
    echo "  All stories completed!"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
    exit 0
  fi

  # 计算当前运行数
  RUNNING=$(running_count)

  # 找出 ready 的 story
  READY=$(find_ready)
  READY_COUNT=$(echo "$READY" | python -c "import sys,json; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo 0)

  if [ "$READY_COUNT" -gt 0 ] && [ "$RUNNING" -lt "$MAX_PARALLEL" ]; then
    # 启动 ready 的 story（最多启动到 MAX_PARALLEL）
    local launched=0
    for story_id in $(echo "$READY" | python -c "import sys,json; [print(s) for s in json.loads(sys.stdin.read())]" 2>/dev/null); do
      if [ "$RUNNING" -ge "$MAX_PARALLEL" ]; then
        break
      fi
      launch_story "$story_id"
      RUNNING=$((RUNNING + 1))
      launched=$((launched + 1))
      sleep 2  # 启动间隔，避免同时触发 429
    done

    if [ "$launched" -gt 0 ]; then
      echo "[dag] 启动了 $launched 个任务，当前运行: $RUNNING"
    fi
  fi

  # 更新心跳
  node -e "
    const fs = require('fs');
    const hb = (() => { try { return JSON.parse(fs.readFileSync('$HEARTBEAT_FILE', 'utf8')); } catch(e) { return {}; } })();
    hb.lastUpdate = Math.floor(Date.now()/1000);
    hb.status = 'running';
    hb.runningCount = $RUNNING;
    hb.readyCount = $READY_COUNT;
    fs.writeFileSync('$HEARTBEAT_FILE', JSON.stringify(hb, null, 2));
  " 2>/dev/null

  # 等待 10 秒再检查
  sleep 10
done

# 清理
rm -rf "$PID_DIR"
exit 2
