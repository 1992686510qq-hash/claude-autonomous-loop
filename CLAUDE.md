# Ralph Auto Runner - Agent 指令

你是一个自主执行任务的 Agent。每轮迭代，你需要：
1. 读取 checkpoint.json，跳过已完成的任务
2. 读取 prd.json，找到优先级最高且未完成的任务
3. 执行该任务
4. 记录结果
5. 退出（让 ralph.sh 启动下一轮）

## 执行流程

```
1. 读取 checkpoint.json → 获取已完成列表
2. 读取 prd.json → 找到 priority 最小且 passes=false 的 story
3. 如果没有待执行的 story → 输出 <promise>COMPLETE</promise>
4. 更新 heartbeat.json（设置 currentStory 和 status: running）
5. 执行该 story
6. 写结果到 output/ 目录
7. 更新 checkpoint.json（标记完成，记录 output 路径和 timestamp）
8. 更新 prd.json（设置 passes: true）
9. 追加进度到 progress.txt
10. 更新 heartbeat.json（设置 status: story_complete）
```

## 时间戳规则

**关键规则：所有时间必须从系统获取，绝对不能自己编造！**

```bash
# 获取 ISO 格式时间
date '+%Y-%m-%dT%H:%M:%S'

# 获取 Unix 时间戳（用于 heartbeat.json）
date '+%s'
```

## 子 Agent 使用规则

当任务需要并行处理时，使用 Agent 工具启动子 Agent：

- 每个子 Agent 有明确的输入和输出路径
- 子 Agent 超时设为 1800 秒（30 分钟）
- 子 Agent 结果必须写入文件（不是只返回文本）
- 处理大目录时按目录分片，每个子 Agent 处理一片

## 输出规范

- 所有输出必须写入文件（不只是返回文本）
- JSON 文件必须包含 meta 字段（version/generated/source）
- 附证据路径（指向源文件的具体位置）

## 心跳机制

每完成一个 story，更新 heartbeat.json：

```bash
# 获取真实时间戳
NOW=$(date '+%s')
# 用 node 更新（避免 jq 依赖）
node -e "
  const fs = require('fs');
  const hb = JSON.parse(fs.readFileSync('heartbeat.json', 'utf8'));
  hb.lastUpdate = $NOW;
  hb.currentStory = 'US-XXX';
  hb.status = 'story_complete';
  hb.completedStories.push('US-XXX');
  fs.writeFileSync('heartbeat.json', JSON.stringify(hb, null, 2));
"
```

## 429 限流处理

- 遇到 429 错误时，等待 30 秒后重试
- 子 Agent 调用之间保持 5 秒间隔
- 如果连续 3 次 429，记录到 failedStories 并跳到下一个 story

## 失败处理

- 子 Agent 超时 → 重试 1 次
- 重试仍失败 → 标记为 failed，继续下一个
- 全部完成后回头处理失败的

## 停止条件

当所有 story 的 `passes` 都为 `true` 时：

1. 输出：`<promise>COMPLETE</promise>`
2. 更新 heartbeat.json 的 status 为 "completed"

## 重要提醒

- 每次只处理一个 story
- 处理前先读 checkpoint，避免重复工作
- 每个 story 的输出必须写入文件
- 保持 heartbeat.json 每 5 分钟更新一次
- 不要跳过任何文件，确保全覆盖
- 遇到 429 限流错误时，等待 30 秒后重试
