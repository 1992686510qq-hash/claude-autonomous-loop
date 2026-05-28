# 架构详解

## 三层架构

### 第一层：ralph.sh（任务调度器）

ralph.sh 是一个 bash 循环，每轮调用一次 `claude --dangerously-skip-permissions --print < CLAUDE.md`。

**为什么每轮启动新进程？**
- 避免上下文膨胀：每个 Claude 进程有独立的上下文窗口
- 进程隔离：一个进程崩溃不影响下一个
- 状态持久化：所有状态存在文件里，进程可以随时重启

**关键参数：**
- `--dangerously-skip-permissions`: 跳过权限确认，全自主运行
- `--print`: 非交互模式，输出到 stdout
- `sleep 10`: 每轮间隔，防 429 限流

### 第二层：claude.exe（执行者）

每个 Claude 进程启动后：
1. 读取 CLAUDE.md 获取指令
2. 读取 checkpoint.json 了解哪些已完成
3. 读取 prd.json 找到下一个待执行的 story
4. 执行 story（可能启动子 Agent）
5. 写结果到文件
6. 更新状态文件
7. 进程退出

### 第三层：子 Agent（并行）

对于大任务，Claude 进程内部可以启动多个子 Agent 并行处理：
- 每个子 Agent 有独立的上下文
- 子 Agent 共享父进程的工具权限
- 结果必须写入文件（不是只返回文本）

## 状态管理

### prd.json（任务定义）

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

- `priority`: 数字越小越先执行
- `passes`: false=待执行，true=已完成

### checkpoint.json（完成记录）

```json
{
  "US-001": {
    "status": "done",
    "output": "path/to/output",
    "timestamp": 1748390408
  }
}
```

### heartbeat.json（实时状态）

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

## 容错机制

### 1. 断点恢复

Ralph 每轮启动新进程，读取 checkpoint.json 跳过已完成的 story。即使进程崩溃，已完成的 work 不会丢失。

### 2. 看门狗自动重启

watchdog.sh 每 60 秒检查 heartbeat.json，如果超过 600 秒没有更新，说明进程卡死或崩溃，自动重启。

### 3. 429 限流保护

- ralph.sh 每轮 sleep 10 秒
- CLAUDE.md 中指导 Agent 遇到 429 等待 30 秒
- ralph.sh 检测输出中的 429 关键字，额外等待

### 4. 子 Agent 超时

子 Agent 设置 1800 秒超时。超时后重试 1 次，仍失败则标记为 failed 继续下一个。
