#!/bin/bash
# Ralph Auto Runner - 看门狗
# 监控 heartbeat.json，超时自动重启 ralph.sh
#
# 用法: bash watchdog.sh [timeout_seconds] [check_interval]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HEARTBEAT_FILE="$PROJECT_DIR/heartbeat.json"
RALPH_PID_FILE="$PROJECT_DIR/.ralph.pid"
RALPH_LOG="$PROJECT_DIR/ralph.log"
WATCHDOG_LOG="$PROJECT_DIR/watchdog.log"

TIMEOUT=${1:-600}       # 默认 600 秒（10 分钟）
INTERVAL=${2:-60}       # 默认 60 秒检查一次

# 获取心跳时间戳（自动处理毫秒/秒）
get_heartbeat_time() {
  local ts
  ts=$(node -e "
    const fs = require('fs');
    try {
      let raw = fs.readFileSync('$HEARTBEAT_FILE', 'utf8').replace(/^﻿/, '');
      const hb = JSON.parse(raw);
      console.log(hb.lastUpdate || 0);
    } catch(e) { console.log(0); }
  " 2>/dev/null || echo 0)

  # 如果超过 12 位，认为是毫秒，转为秒
  if [ ${#ts} -gt 12 ]; then
    echo $((ts / 1000))
  else
    echo "$ts"
  fi
}

# 获取心跳状态
get_heartbeat_status() {
  node -e "
    const fs = require('fs');
    try {
      let raw = fs.readFileSync('$HEARTBEAT_FILE', 'utf8').replace(/^﻿/, '');
      const hb = JSON.parse(raw);
      const done = (hb.completedStories || []).length;
      const status = hb.status || 'unknown';
      const story = hb.currentStory || '-';
      console.log(status + '|' + story + '|' + done);
    } catch(e) { console.log('error|-|0'); }
  " 2>/dev/null || echo "error|-|0"
}

# 启动 Ralph
start_ralph() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动 Ralph..."
  nohup bash "$SCRIPT_DIR/ralph.sh" --tool claude 100 > "$RALPH_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$RALPH_PID_FILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ralph started, PID: $pid"
}

# 检查 Ralph 是否在运行
is_ralph_running() {
  if [ -f "$RALPH_PID_FILE" ]; then
    local pid=$(cat "$RALPH_PID_FILE")
    kill -0 "$pid" 2>/dev/null && return 0
  fi
  return 1
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog 启动"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 超时阈值: ${TIMEOUT}s | 检查间隔: ${INTERVAL}s"

# 如果 Ralph 没在运行，启动它
if ! is_ralph_running; then
  start_ralph
fi

while true; do
  sleep "$INTERVAL"

  NOW=$(date '+%s')
  LAST=$(get_heartbeat_time)
  DIFF=$((NOW - LAST))

  # 读取状态
  IFS='|' read -r STATUS STORY DONE_COUNT <<< "$(get_heartbeat_status)"

  if is_ralph_running; then
    # Ralph 在运行
    if [ "$DIFF" -gt "$TIMEOUT" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: 心跳超时 ${DIFF}s > ${TIMEOUT}s，重启 Ralph..."
      local pid=$(cat "$RALPH_PID_FILE" 2>/dev/null)
      kill "$pid" 2>/dev/null || true
      sleep 2
      start_ralph
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK | $STATUS | $STORY | done: $DONE_COUNT | heartbeat: ${DIFF}s ago"
    fi
  else
    # Ralph 不在运行
    if [ "$DIFF" -gt "$TIMEOUT" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Ralph 进程不在运行，心跳超时，重启..."
      start_ralph
    else
      # 刚完成或刚停止，等待一下看看是不是正常退出
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ralph 进程不在运行，心跳 ${DIFF}s 前更新，等待确认..."
      sleep 30
      if ! is_ralph_running; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 确认 Ralph 已停止，重启..."
        start_ralph
      fi
    fi
  fi
done
