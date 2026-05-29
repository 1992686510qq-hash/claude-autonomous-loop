# Ralph Auto Runner

> 基于 Claude Code 的长时间自主任务执行框架

让 AI Agent 自主执行数十甚至上百个任务，无需人工干预，支持自动重启、进度监控、飞书通知。

## 它能做什么

- **批量任务自主执行**: 定义 70+ 个任务，AI 自动逐个完成
- **断点恢复**: 进程崩溃后自动从上次中断处继续
- **看门狗监控**: 10 分钟无响应自动重启
- **飞书通知**: 每完成一个任务推送消息
- **子 Agent 并行**: 大任务自动拆分为多个子 Agent 并行处理
- **429 限流保护**: 自动检测 API 限流并等待重试
- **Token 监控**: 实时统计 token 使用量（扫描模式 / 代理模式）
- **时间轴记录**: 每个 story 的开始/子Agent/结束事件，生成运行报告

## 架构

```
┌─────────────────────────────────────┐
│  ralph.sh（任务调度器）              │
│  bash 循环，每轮启动一个 claude 进程 │
└─────────────┬───────────────────────┘
              │ 每轮
┌─────────────▼───────────────────────┐
│  claude.exe（执行者）                │
│  读指令 → 找任务 → 执行 → 写结果    │
│  可能启动子 Agent 并行处理           │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│  子 Agent（并行）                    │
│  分片处理大目录/大文件               │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  watchdog.sh（看门狗）               │
│  每 60 秒检查心跳，超时自动重启      │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  notifier.js（飞书通知）             │
│  每 30 秒检查完成状态，推送消息      │
└─────────────────────────────────────┘
```

## 快速开始

### 1. 安装依赖

```bash
# Claude Code CLI
npm install -g @anthropic-ai/claude-code

# jq（JSON 处理）
# Linux/Mac: apt install jq / brew install jq
# Windows: 下载 jq.exe 到 PATH

# Node.js（通知功能需要）
# https://nodejs.org/
```

### 2. 初始化项目

```bash
git clone <your-repo>
cd ralph-auto-runner

# 初始化状态文件
bash scripts/init.sh
```

### 3. 配置任务

编辑 `prd.json`，定义你的任务列表：

```json
{
  "userStories": [
    {
      "id": "US-001",
      "title": "任务标题",
      "description": "任务描述",
      "acceptanceCriteria": ["完成条件1", "完成条件2"],
      "priority": 1,
      "passes": false
    }
  ]
}
```

### 4. 编写指令

编辑 `CLAUDE.md`，写清楚 AI Agent 每轮迭代要做什么。

### 5. 启动

```bash
# 启动看门狗 + Ralph
bash scripts/start.sh

# 查看状态
bash scripts/status.sh

# 停止
bash scripts/stop.sh
```

### 6.（可选）配置飞书通知

```bash
# 1. 创建飞书群，获取 chat_id
# 2. 编辑 scripts/notifier.js 中的 CHAT_ID
# 3. 启动通知
bash scripts/notifier.sh
```

## 文件说明

```
├── CLAUDE.md              # AI Agent 每轮迭代的指令模板
├── prd.json               # 任务列表（用户故事）
├── scripts/
│   ├── ralph.sh           # 主循环：调度 Claude 进程
│   ├── watchdog.sh        # 看门狗：监控心跳，超时重启
│   ├── notifier.js        # 飞书通知：完成时推送消息
│   ├── notifier.sh        # 通知脚本包装器
│   ├── init.sh            # 初始化状态文件
│   ├── start.sh           # 一键启动
│   ├── stop.sh            # 一键停止
│   ├── status.sh          # 查看运行状态
│   ├── regen_pdf.py       # PDF 中文字体生成
│   └── monitor/
│       ├── monitor.py     # Token 监控（扫描 session 文件）
│       └── proxy-addon.py # Token 监控（mitmproxy 代理模式）
├── examples/
│   ├── prd-scan.json      # 示例：文件扫描任务
│   ├── prd-research.json  # 示例：调研任务
│   └── CLAUDE-scan.md     # 示例：文件扫描指令
├── docs/
│   ├── architecture.md    # 架构详解
│   ├── pitfalls.md        # 踩坑记录
│   └── customization.md   # 自定义指南
├── heartbeat.json         # 实时心跳状态
├── checkpoint.json        # 完成记录
├── progress.txt           # 人类可读进度日志
└── .gitignore
```

## 核心概念

### Story（任务）

每个 story 是一个独立的、可验证的任务单元：

```json
{
  "id": "US-001",
  "title": "扫描目录",
  "description": "扫描 /data 目录，生成文件清单",
  "acceptanceCriteria": [
    "输出 inventory.csv",
    "包含 path/size/modified 三列"
  ],
  "priority": 1,
  "passes": false
}
```

- `priority`: 数字越小越先执行
- `passes`: false=待执行，true=已完成

### Checkpoint（检查点）

每完成一个 story，自动写入 checkpoint.json：

```json
{
  "US-001": {
    "status": "done",
    "output": "inventory.csv",
    "timestamp": 1748390408
  }
}
```

Ralph 重启时会读取 checkpoint，跳过已完成的任务。

### Heartbeat（心跳）

实时记录运行状态，watchdog 依赖它判断进程是否存活：

```json
{
  "lastUpdate": 1748390408,
  "currentStory": "US-003",
  "iteration": 5,
  "status": "running",
  "completedStories": ["US-001", "US-002"],
  "failedStories": []
}
```

## 自定义指南

### 添加新任务

1. 在 `prd.json` 的 `userStories` 数组中添加新 story
2. 设置合理的 `priority`（控制执行顺序）
3. Ralph 会自动拾取新任务

### 修改执行逻辑

编辑 `CLAUDE.md`，这是 AI Agent 每轮迭代读取的指令。关键部分：
- 如何读取当前状态
- 如何执行任务
- 如何写入结果
- 错误处理策略

### 调整参数

| 参数 | 文件 | 默认值 | 说明 |
|------|------|--------|------|
| 最大迭代次数 | ralph.sh | 100 | 总共执行多少轮 |
| 轮次间隔 | ralph.sh | 10 秒 | 防 429 限流 |
| 心跳超时 | watchdog.sh | 600 秒 | 超时自动重启 |
| 子 Agent 超时 | CLAUDE.md | 1800 秒 | 子任务最大执行时间 |
| 通知频率 | notifier.js | 30 秒 | 检查完成状态的间隔 |

## Token 监控

运行过程中实时查看 token 消耗：

```bash
# 扫描模式（零配置，读 session 文件）
python scripts/monitor/monitor.py --once           # 看一次
python scripts/monitor/monitor.py                  # 每 30 秒刷新
python scripts/monitor/monitor.py --all --once     # 扫描所有项目

# 代理模式（100% 准确，需要 mitmproxy）
pip install mitmproxy
mitmdump -s scripts/monitor/proxy-addon.py --set upstream_cert=false -p 8080
```

## 踩坑记录

详见 [docs/pitfalls.md](docs/pitfalls.md)

**简要版**：
1. **429 限流**: sleep 不要低于 10 秒
2. **假时间戳**: 必须强制 AI 调用 `date` 命令获取时间
3. **时间戳单位**: heartbeat 可能写毫秒或秒，watchdog 需自动检测
4. **JSON 编码**: Windows 下中文可能损坏，用映射表兜底
5. **子 Agent 超时**: 大目录必须分片处理
6. **PDF 生成**: 中文需要嵌入 CJK 字体
7. **迭代上限**: 默认 50 太小，建议设 100+

## 适用场景

- 全量文件扫描和分析
- 批量文档处理和报告生成
- 长时间数据采集
- 多步骤研究任务
- 任何可以拆分为独立 story 的批量工作

## License

MIT
