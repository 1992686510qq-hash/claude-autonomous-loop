# 功能调研报告

> 基于 30+ 同类项目的研究，4 个子 Agent 并行调研

---

## 一、Token 预算硬限制

**来源**: vercel-labs/ralph-loop-agent, builderz-labs/mission-control

**核心发现**:
- mission-control 做的是**纯观测**（SQLite 记录 token 消耗），不做预算限制
- ralph-loop-agent 做的是**真正的限制**：组合式停止条件（迭代次数 OR token 数 OR 成本）

**ralph-loop-agent 的实现**:
```typescript
// 三个停止条件，OR 逻辑
const stop = composeStopConditions(
  iterationCountIs(50),        // 最多 50 轮
  tokenCountIs(1_000_000),     // 最多 100 万 token
  costIs(10.00),               // 最多 $10
);
// 每轮迭代后检查
if (stop(usage)) break;
```

- 成本计算区分 cache-read / cache-write / uncached，不同价格
- 超预算时优雅退出，不抛异常

**推荐实现（bash）**:
```bash
# 在 .loop-budget.json 中定义预算
{"max_iterations": 100, "max_tokens": 50000000, "max_cost_usd": 50}

# 每轮迭代后，用 monitor.py 读取累计 token，检查是否超限
# 超限 → 写入 progress.txt "BUDGET_EXCEEDED" → ralph.sh 检测到后退出
```

**改动量**: ralph.sh 加 ~20 行，monitor.py 加 --check-budget 参数

---

## 二、完成后自动摘要

**来源**: thedotmack/claude-mem, vercel-labs/ralph-loop-agent

**核心发现**:
- claude-mem 用**第二个 Claude 会话**做压缩，输出结构化 XML（request/investigated/learned/completed/next_steps）
- ralph-loop-agent 在上下文超过 70% 时自动压缩旧迭代，prompt 只要 200 token 输出

**压缩 prompt**（来自 ralph-loop-agent）:
```
Summarize this agent iteration in 2-3 concise sentences.
Focus on: what was accomplished, key decisions made, and any blockers encountered.
```

**注入方式**:
- claude-mem: 写入 `AGENTS.md`，Claude Code 启动时自动读取
- ralph-loop-agent: 追加到 system message

**推荐实现（bash）**:
```bash
# 每个 story 完成后，调用一次轻量 Claude 做摘要
claude --print "用 3 句话总结以下任务的执行结果和关键决策：
$(tail -50 progress.txt)
输出到 .loop-context.md"

# 下一轮迭代开始时，在 CLAUDE.md 开头注入上下文
echo "## 上下文摘要" >> /tmp/claude-input.md
cat .loop-context.md >> /tmp/claude-input.md
cat CLAUDE.md >> /tmp/claude-input.md
claude --print < /tmp/claude-input.md
```

**改动量**: ralph.sh 加 ~15 行（摘要调用 + 注入逻辑）

---

## 三、DAG 依赖执行

**来源**: win4r/team-tasks, umputun/ralphex

**核心发现**:
- team-tasks 用**轮询式 ready-check**而非完整拓扑排序
- 依赖声明：每个 task 加 `dependsOn: ["task-a", "task-b"]`
- 完成一个 task 后，扫描所有 pending task，检查 dependsOn 是否全 done
- ralphex 用 git worktree 隔离并行任务

**数据格式扩展**:
```json
{
  "id": "US-003",
  "title": "生成报告",
  "dependsOn": ["US-001", "US-002"],
  "priority": 3,
  "passes": false
}
```

**算法**:
```
while 有未完成的 story:
    ready = [s for s in stories if s.passes==false AND all(d.passes==true for d in s.dependsOn)]
    if ready:
        并行启动 len(ready) 个 claude 进程
        等待任一完成 → 标记 done → 重新计算 ready
    else:
        等待 10 秒
```

**推荐实现**:
- prd.json 加可选 `dependsOn` 字段（默认空 = 顺序执行，向后兼容）
- ralph.sh 改为 while 循环 + 后台进程 + PID 追踪
- 用 jq 做 ready-check

**改动量**: ralph.sh 重写 ~80 行（从 for 循环改为 while + 并行调度）

---

## 四、验证步骤

**来源**: win4r/team-tasks (debate), umputun/ralphex (review pipeline), avivl/claude-007-agents

**核心发现**:
- **team-tasks debate**: 三阶段 — 独立产出 → 交叉审查 → 综合合并。开销大（3x）
- **ralphex review pipeline**: 四阶段 — 执行 → 5 个并行审查 Agent → codex 工具审查 → 2 个终审 Agent。开销更大（5+1+2 = 8x）
- **推荐简化**: 单个轻量审查 Agent，检查三件事：
  1. 预期文件是否存在
  2. 输出内容是否匹配 acceptanceCriteria
  3. 是否有明显错误标记

**审查 prompt 模板**:
```
你是质量审查员。检查以下任务是否真正完成：
任务: {title}
完成条件: {acceptanceCriteria}
输出文件: {output_files}

逐条检查完成条件，对每条给出 PASS/FAIL。
如果全部 PASS，输出 VERDICT: PASS
如果有任何 FAIL，输出 VERDICT: FAIL + 具体问题。
```

**失败处理**:
- FAIL → 把审查反馈追加到 CLAUDE.md，重试 1 次
- 重试仍 FAIL → 标记 failed，继续下一个
- 审查 Agent 本身报错 → fail-open（当作 PASS，不阻塞流程）

**成本控制**: 用轻量模型（如 Haiku）做审查，成本约为正式执行的 10%

**改动量**: CLAUDE.md 加审查步骤描述，ralph.sh 加审查调用 ~30 行

---

## 实施建议

| 优先级 | 功能 | 改动量 | 收益 |
|--------|------|--------|------|
| **P0** | Token 预算 | ~20 行 | 防止 token 花超 |
| **P0** | 自动摘要 | ~15 行 | 防止上下文膨胀 |
| **P1** | 验证步骤 | ~30 行 | 提高输出质量 |
| **P2** | DAG 依赖 | ~80 行 | 无依赖任务并行，加速 2-3x |

建议先做 P0（Token 预算 + 自动摘要），改动小、收益大。P1 验证步骤次之。P2 DAG 改动最大，但对 70+ story 的任务加速效果显著。
