# 自定义指南

## 如何定义任务

### 最小化 story

```json
{
  "id": "US-001",
  "title": "简单任务",
  "description": "做一件事",
  "acceptanceCriteria": ["输出文件"],
  "priority": 1,
  "passes": false
}
```

### 完整 story

```json
{
  "id": "US-010",
  "title": "提取文档内容",
  "description": "扫描 /data/docs 目录，提取所有 .md 和 .txt 文件的内容，生成汇总报告",
  "acceptanceCriteria": [
    "输出 extract/docs-summary.md",
    "包含每个文件的路径、大小、前 200 字摘要",
    "总文件数应与 inventory.csv 中的文档数一致",
    "大文件（>10KB）只提取前 500 字"
  ],
  "priority": 10,
  "passes": false,
  "notes": "依赖 US-001 的 inventory.csv"
}
```

### 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| id | 是 | 唯一标识，建议 US-XXX 格式 |
| title | 是 | 简短标题 |
| description | 是 | 详细描述，告诉 Agent 要做什么 |
| acceptanceCriteria | 是 | 完成条件，Agent 会据此判断是否完成 |
| priority | 是 | 执行顺序，数字越小越先执行 |
| passes | 是 | 初始为 false，完成后自动设为 true |
| notes | 否 | 补充说明 |

## 如何编写 CLAUDE.md

CLAUDE.md 是 Agent 每轮迭代读取的指令。关键部分：

### 1. 扫描范围

告诉 Agent 数据在哪里：
```markdown
## 扫描范围
- /data/input — 源数据目录
- /data/output — 输出目录
排除: node_modules, .git
```

### 2. 执行逻辑

针对每个 story 类型，给出具体的操作步骤：
```markdown
## US-001 扫描目录
使用 find 命令递归扫描，输出 CSV 格式：
\```bash
find /data -type f -printf "%p,%s,%T@\n" > output.csv
\```
```

### 3. 错误处理

告诉 Agent 遇到问题怎么办：
```markdown
## 错误处理
- 文件太大 → 只读前 2000 行
- 权限不足 → 记录路径，跳过
- 429 限流 → 等 30 秒重试
```

### 4. 子 Agent 策略

何时使用子 Agent：
```markdown
## 子 Agent 使用
当需要处理的目录超过 1000 个文件时：
1. 按子目录分片
2. 每个子 Agent 处理一个子目录
3. 最后汇总结果
```

## 如何调整参数

### 迭代次数

在 ralph.sh 中修改 `MAX_ITERATIONS`。计算公式：
```
所需轮数 = story 数量 + 预估重试次数
```
建议设为 story 数量的 1.5-2 倍。

### 轮次间隔

在 ralph.sh 中修改 `sleep` 值：
- 保守：sleep 15（几乎不会 429）
- 默认：sleep 10（推荐）
- 激进：sleep 5（可能触发 429）

### 看门狗超时

在 watchdog.sh 中修改 `TIMEOUT`：
- 快速任务（每个 <1 分钟）：300 秒
- 中等任务（每个 1-10 分钟）：600 秒（默认）
- 慢任务（每个 >10 分钟）：1800 秒

### 子 Agent 超时

在 CLAUDE.md 中修改子 Agent 的超时设置：
- 小任务：600 秒
- 中等任务：1800 秒（默认）
- 大任务：3600 秒

## 如何添加飞书通知

1. 安装 lark-cli: `npm install -g @anthropic-ai/lark-cli`
2. 登录: `lark-cli auth login`
3. 创建飞书群，获取 chat_id
4. 启动时传入: `bash scripts/start.sh --notify oc_xxx`

## 如何自定义输出格式

在 CLAUDE.md 中指定输出格式：

```markdown
## 输出格式
所有报告必须包含：
1. meta 字段（version/generated/source）
2. 证据路径（指向源文件）
3. 中文输出
```
