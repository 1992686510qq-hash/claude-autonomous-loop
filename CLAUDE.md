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
7. 验证输出质量（见下方"验证步骤"）
8. 更新 checkpoint.json（标记完成，记录 output 路径和 timestamp）
9. 更新 prd.json（设置 passes: true）
10. 追加进度到 progress.txt
11. 更新 heartbeat.json（设置 status: story_complete）
```

## 验证步骤

每个 story 执行完成后，必须验证输出质量：

1. **检查输出文件是否存在** — 读取 checkpoint 中记录的 output 路径，确认文件存在且非空
2. **检查 acceptanceCriteria** — 逐条对照 acceptanceCriteria，确认每条都满足
3. **检查明显错误** — 输出中是否包含 error/exception/traceback 等错误标记

如果验证失败：
- 将失败原因追加到 progress.txt
- 重试该 story（最多 1 次）
- 重试仍失败 → 标记为 failed，继续下一个

验证通过后才更新 checkpoint.json 和 prd.json。

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

## 时间轴记录（必须执行）

**关键规则：所有时间必须从系统获取，绝对不能自己编造！**

获取真实时间的方法：
```bash
# 获取 ISO 格式时间
date '+%Y-%m-%dT%H:%M:%S'
# 获取 Unix 时间戳（用于 heartbeat.json）
date '+%s'
```

每次记录事件时，必须先用 Bash 执行 `date` 命令获取真实时间，然后用获取到的时间写入 timeline.json。

### 开始处理时追加：
先执行 `CURRENT_TIME=$(date '+%Y-%m-%dT%H:%M:%S')` 获取真实时间，然后追加：
```json
{"time": "$CURRENT_TIME", "type": "STORY_START", "detail": "story标题", "story": "US-XXX", "agent": null, "status": "running"}
```

### 启动子 Agent 时追加：
```json
{"time": "ISO时间", "type": "AGENT_SPAWN", "detail": "子Agent任务描述", "story": "US-XXX", "agent": "agent-label", "status": "running"}
```

### 子 Agent 完成时追加：
```json
{"time": "ISO时间", "type": "AGENT_DONE", "detail": "结果摘要", "story": "US-XXX", "agent": "agent-label", "status": "done"}
```

### story 完成时追加：
```json
{"time": "ISO时间", "type": "STORY_END", "detail": "输出文件路径", "story": "US-XXX", "agent": null, "status": "done"}
```

### story 失败时追加：
```json
{"time": "ISO时间", "type": "STORY_FAIL", "detail": "失败原因", "story": "US-XXX", "agent": null, "status": "failed"}
```

### 全部完成时：
1. 更新 timeline.json 的 meta.ended
2. 读取 timeline.json 的所有 events
3. 生成 `output/run-timeline.md`，格式如下：

```markdown
# 运行时间轴报告

## 概览
- 开始时间: ...
- 结束时间: ...
- 总耗时: ...
- 完成 story: X/Y
- 失败重试: N 次

## 时间轴

### HH:MM - 事件描述
- HH:MM:SS | 类型 | 详情

### 运行统计
| 指标 | 值 |
|---|---|
| 总迭代次数 | N |
| 总子Agent调用 | N |
| 平均每story耗时 | N 分钟 |
```

## 停止条件

当所有 story 的 `passes` 都为 `true` 时：

1. 生成最终时间轴报告 `output/run-timeline.md`
2. 更新 heartbeat.json 的 status 为 "completed"
3. 输出：`<promise>COMPLETE</promise>`

## 重要提醒

- 每次只处理一个 story
- 处理前先读 checkpoint，避免重复工作
- 每个 story 的输出必须写入文件
- 保持 heartbeat.json 每 5 分钟更新一次
- **每个 story 必须记录时间轴事件（开始/子Agent/结束）**
- **最终必须生成 output/run-timeline.md**
- 遇到 429 限流错误时，等待 30 秒后重试
- 子 Agent 调用之间保持 5 秒间隔
