#!/bin/bash
# Ralph Auto Runner - 查看运行状态

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "  Ralph Auto Runner - 状态"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# 检查进程状态
echo ""
echo "进程状态:"

check_pid() {
  local name="$1"
  local pidfile="$PROJECT_DIR/.$(echo $name | tr '[:upper:]' '[:lower:]').pid"
  if [ -f "$pidfile" ]; then
    local pid=$(cat "$pidfile")
    if kill -0 "$pid" 2>/dev/null; then
      echo "  ✓ $name: 运行中 (PID $pid)"
    else
      echo "  ✗ $name: 已停止 (PID $pid)"
    fi
  else
    echo "  - $name: 未启动"
  fi
}

check_pid "Ralph"
check_pid "Watchdog"
check_pid "Notifier"

# 读取心跳
echo ""
echo "心跳状态:"
node -e "
  const fs = require('fs');
  try {
    let raw = fs.readFileSync('$PROJECT_DIR/heartbeat.json', 'utf8').replace(/^﻿/, '');
    const hb = JSON.parse(raw);
    const now = Math.floor(Date.now() / 1000);
    const age = now - (hb.lastUpdate || 0);
    console.log('  状态: ' + (hb.status || 'unknown'));
    console.log('  当前任务: ' + (hb.currentStory || '-'));
    console.log('  迭代次数: ' + (hb.iteration || 0));
    console.log('  心跳更新: ' + age + ' 秒前');
    console.log('  已完成: ' + (hb.completedStories || []).length);
    console.log('  失败: ' + (hb.failedStories || []).length);
  } catch(e) {
    console.log('  无法读取 heartbeat.json');
  }
" 2>/dev/null

# 读取 checkpoint
echo ""
echo "检查点:"
node -e "
  const fs = require('fs');
  try {
    let raw = fs.readFileSync('$PROJECT_DIR/checkpoint.json', 'utf8').replace(/^﻿/, '');
    const cp = JSON.parse(raw);
    const keys = Object.keys(cp);
    console.log('  已完成 story: ' + keys.length);
    if (keys.length > 0) {
      const last = keys.sort().pop();
      const entry = cp[last];
      console.log('  最近完成: ' + last + ' -> ' + (entry.output || '-'));
    }
  } catch(e) {
    console.log('  无法读取 checkpoint.json');
  }
" 2>/dev/null

# 最近日志
echo ""
echo "最近进度 (最后 5 行):"
tail -5 "$PROJECT_DIR/progress.txt" 2>/dev/null | sed 's/^/  /' || echo "  无进度日志"

echo ""
echo "========================================="
