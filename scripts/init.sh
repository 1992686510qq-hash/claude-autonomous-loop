#!/bin/bash
# Ralph Auto Runner - 初始化
# 创建必要的状态文件和目录

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "初始化 Ralph Auto Runner..."
echo "项目目录: $PROJECT_DIR"

# 创建输出目录
mkdir -p "$PROJECT_DIR/output"
mkdir -p "$PROJECT_DIR/scripts"
mkdir -p "$PROJECT_DIR/examples"
mkdir -p "$PROJECT_DIR/docs"

# 初始化 heartbeat.json
if [ ! -f "$PROJECT_DIR/heartbeat.json" ]; then
  cat > "$PROJECT_DIR/heartbeat.json" << 'EOF'
{
  "lastUpdate": 0,
  "currentStory": null,
  "iteration": 0,
  "status": "init",
  "completedStories": [],
  "failedStories": []
}
EOF
  echo "  ✓ heartbeat.json"
else
  echo "  - heartbeat.json 已存在，跳过"
fi

# 初始化 checkpoint.json
if [ ! -f "$PROJECT_DIR/checkpoint.json" ]; then
  echo '{}' > "$PROJECT_DIR/checkpoint.json"
  echo "  ✓ checkpoint.json"
else
  echo "  - checkpoint.json 已存在，跳过"
fi

# 初始化 progress.txt
if [ ! -f "$PROJECT_DIR/progress.txt" ]; then
  cat > "$PROJECT_DIR/progress.txt" << EOF
# Ralph Progress Log
Started: $(date)
---
EOF
  echo "  ✓ progress.txt"
else
  echo "  - progress.txt 已存在，跳过"
fi

# 检查依赖
echo ""
echo "检查依赖..."

if command -v claude &> /dev/null; then
  echo "  ✓ claude ($(claude --version 2>/dev/null | head -1))"
else
  echo "  ✗ claude 未安装 (npm install -g @anthropic-ai/claude-code)"
fi

if command -v node &> /dev/null; then
  echo "  ✓ node ($(node --version))"
else
  echo "  ✗ node 未安装 (https://nodejs.org/)"
fi

if command -v jq &> /dev/null; then
  echo "  ✓ jq ($(jq --version))"
else
  echo "  ⚠ jq 未安装（可选，watchdog 用 node 替代）"
fi

if command -v lark-cli &> /dev/null; then
  echo "  ✓ lark-cli ($(lark-cli --version 2>/dev/null | head -1))"
else
  echo "  ⚠ lark-cli 未安装（可选，飞书通知需要）"
fi

echo ""
echo "初始化完成！"
echo ""
echo "下一步:"
echo "  1. 编辑 prd.json 定义任务"
echo "  2. 编辑 CLAUDE.md 写执行指令"
echo "  3. 运行 bash scripts/start.sh 启动"
