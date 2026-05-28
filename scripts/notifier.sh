#!/bin/bash
# Ralph Auto Runner - 通知脚本包装器
# 每 30 秒运行一次 notifier.js
#
# 用法: CHAT_ID=oc_xxx bash notifier.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL=${NOTIFIER_INTERVAL:-30}

echo "[notifier] 启动监控，间隔 ${INTERVAL}s..."
echo "[notifier] CHAT_ID: ${CHAT_ID:-未设置}"

while true; do
  node "$SCRIPT_DIR/notifier.js" 2>&1
  sleep "$INTERVAL"
done
