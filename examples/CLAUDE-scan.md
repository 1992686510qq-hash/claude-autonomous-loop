# 文件扫描 Agent 指令

你是一个自主执行文件扫描任务的 Agent。

## 扫描范围

- 主目录: [填写你的目录路径]
- 排除: node_modules, .git, __pycache__, *.tmp

## 执行流程

1. 读取 checkpoint.json，跳过已完成的 story
2. 读取 prd.json，找到优先级最高且 passes=false 的 story
3. 更新 heartbeat.json
4. 执行该 story
5. 更新 checkpoint.json 和 prd.json
6. 追加进度到 progress.txt
7. 更新 heartbeat.json

## US-001 扫描目标目录

使用 Bash 工具执行 find 命令：
```bash
find /target/dir -type f \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -printf "%p,%s,%f,%T@\n" > inventory.csv
```

如果文件数超过 10 万，使用子 Agent 分片处理。

## US-002 文件分类统计

读取 inventory.csv，用 Node.js 或 Python 脚本按扩展名分类：
- 文档: .md .txt .docx .pdf .rtf .odt
- 代码: .py .js .ts .java .c .cpp .go .rs
- 图片: .jpg .png .gif .svg .webp
- 媒体: .mp3 .mp4 .wav .avi
- 配置: .json .yaml .toml .ini .env
- 其他: 以上都不匹配的

## US-003 提取文档内容

遍历文档类文件，提取文本摘要：
- .md/.txt: 直接读取前 2000 字
- .json: 读取并格式化
- .pdf: 如有 pdftotext 则提取，否则跳过
- .docx: 如有相关工具则提取，否则记录路径

## US-004 生成分析报告

综合前面的结果，生成 Markdown 报告：
- 文件分布饼图（用 ASCII 表格）
- Top 10 最大文件
- Top 10 最多文件的目录
- 关键发现和建议

## 时间戳规则

所有时间必须从系统获取：
```bash
date '+%Y-%m-%dT%H:%M:%S'
date '+%s'
```

## 停止条件

所有 story 的 passes 都为 true 时，输出 `<promise>COMPLETE</promise>`。
