"""
Claude Code Token 实时监控

扫描 .claude/projects/ 下的 session 文件，统计 token 使用量。
不需要代理，不需要重启 Claude Code，随时跑随时看。

用法:
  python monitor.py                    # 默认扫描当前项目
  python monitor.py /path/to/project   # 指定项目目录
  python monitor.py --once             # 只跑一次（不循环）
  python monitor.py --json             # 输出 JSON 格式

依赖: Python 3.8+, 无第三方依赖
"""

import json
import os
import sys
import time
import glob
import argparse
from collections import defaultdict

# ─── 配置 ───────────────────────────────────────────────

CLAUDE_PROJECTS_DIR = os.path.expanduser("~/.claude/projects")

# 项目目录名映射: D:\Claude Code\scan-project → D--Claude-Code-scan-project
def project_dir_to_session_name(project_dir):
    """将项目路径转换为 Claude Code session 目录名"""
    abs_path = os.path.abspath(project_dir)
    # 替换: \ → -, : → -, 空格不变
    name = abs_path.replace("\\", "-").replace(":", "-")
    return name

# ─── 核心逻辑 ───────────────────────────────────────────

class TokenScanner:
    def __init__(self):
        self.file_offsets = {}  # filepath → last read offset

    def scan_file(self, filepath):
        """扫描单个 session 文件，返回增量 token"""
        usage = {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "count": 0}

        try:
            size = os.path.getsize(filepath)
            offset = self.file_offsets.get(filepath, 0)
            if size <= offset:
                return usage

            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                f.seek(offset)
                for line in f:
                    if '"usage"' not in line or '"input_tokens"' not in line:
                        continue
                    u = self._extract_usage(line)
                    if u and (u["input"] > 0 or u["output"] > 0):
                        usage["input"] += u["input"]
                        usage["output"] += u["output"]
                        usage["cache_read"] += u["cache_read"]
                        usage["cache_create"] += u["cache_create"]
                        usage["count"] += 1

                self.file_offsets[filepath] = f.tell()

        except Exception:
            pass

        return usage

    def _extract_usage(self, line):
        """从 JSONL 行中提取 usage 对象"""
        try:
            idx = line.find('"usage"')
            if idx == -1:
                return None
            brace_start = line.find("{", idx)
            if brace_start == -1:
                return None
            depth = 0
            for i in range(brace_start, len(line)):
                if line[i] == "{":
                    depth += 1
                elif line[i] == "}":
                    depth -= 1
                    if depth == 0:
                        data = json.loads(line[brace_start:i+1])
                        return {
                            "input": data.get("input_tokens", 0),
                            "output": data.get("output_tokens", 0),
                            "cache_read": data.get("cache_read_input_tokens", 0),
                            "cache_create": data.get("cache_creation_input_tokens", 0),
                        }
        except (json.JSONDecodeError, ValueError):
            pass
        return None

    def scan_project(self, project_dir):
        """扫描指定项目的所有 session 文件"""
        session_name = project_dir_to_session_name(project_dir)
        session_dir = os.path.join(CLAUDE_PROJECTS_DIR, session_name)

        if not os.path.isdir(session_dir):
            return {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "count": 0, "files": 0}

        total = {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "count": 0, "files": 0}

        # 主会话文件
        for f in glob.glob(os.path.join(session_dir, "*.jsonl")):
            u = self.scan_file(f)
            if u["count"] > 0:
                total["input"] += u["input"]
                total["output"] += u["output"]
                total["cache_read"] += u["cache_read"]
                total["cache_create"] += u["cache_create"]
                total["count"] += u["count"]
                total["files"] += 1

        # 子 Agent 会话文件
        for f in glob.glob(os.path.join(session_dir, "*", "subagents", "*.jsonl")):
            u = self.scan_file(f)
            if u["count"] > 0:
                total["input"] += u["input"]
                total["output"] += u["output"]
                total["cache_read"] += u["cache_read"]
                total["cache_create"] += u["cache_create"]
                total["count"] += u["count"]
                total["files"] += 1

        return total

    def scan_all_projects(self):
        """扫描所有项目"""
        total = {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "count": 0, "files": 0}
        if not os.path.isdir(CLAUDE_PROJECTS_DIR):
            return total
        for name in os.listdir(CLAUDE_PROJECTS_DIR):
            session_dir = os.path.join(CLAUDE_PROJECTS_DIR, name)
            if not os.path.isdir(session_dir):
                continue
            for f in glob.glob(os.path.join(session_dir, "*.jsonl")):
                u = self.scan_file(f)
                if u["count"] > 0:
                    total["input"] += u["input"]
                    total["output"] += u["output"]
                    total["cache_read"] += u["cache_read"]
                    total["cache_create"] += u["cache_create"]
                    total["count"] += u["count"]
                    total["files"] += 1
            for f in glob.glob(os.path.join(session_dir, "*", "subagents", "*.jsonl")):
                u = self.scan_file(f)
                if u["count"] > 0:
                    total["input"] += u["input"]
                    total["output"] += u["output"]
                    total["cache_read"] += u["cache_read"]
                    total["cache_create"] += u["cache_create"]
                    total["count"] += u["count"]
                    total["files"] += 1
        return total


def read_heartbeat(project_dir):
    """读取 heartbeat.json"""
    hb_path = os.path.join(project_dir, "heartbeat.json")
    try:
        with open(hb_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {}


def read_checkpoint_count(project_dir):
    """读取 checkpoint.json 完成数"""
    cp_path = os.path.join(project_dir, "checkpoint.json")
    try:
        with open(cp_path, "r", encoding="utf-8") as f:
            return len(json.load(f))
    except:
        return 0


def format_tokens(n):
    """格式化 token 数"""
    if n >= 1e8:
        return f"{n/1e8:.2f}亿"
    elif n >= 1e4:
        return f"{n/1e4:.1f}万"
    else:
        return f"{n:,}"


def print_report(cumulative, batch, heartbeat_info, json_mode=False):
    """打印报告"""
    if json_mode:
        report = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "batch": batch,
            "cumulative": cumulative,
            "heartbeat": heartbeat_info,
        }
        print(json.dumps(report, ensure_ascii=False))
        return

    ts = time.strftime("%H:%M:%S")
    total = cumulative["input"] + cumulative["output"]
    status = heartbeat_info.get("status", "-")
    story = heartbeat_info.get("currentStory", "-")
    done = heartbeat_info.get("done", 0)

    print(f"[{ts}] {status} | {story} | done:{done} | "
          f"batch: +{format_tokens(batch['input']+batch['output'])} | "
          f"total: {format_tokens(total)} | "
          f"cache: {format_tokens(cumulative['cache_read'])} | "
          f"requests: {cumulative['count']}", flush=True)


# ─── 主程序 ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Claude Code Token Monitor")
    parser.add_argument("project_dir", nargs="?", default=os.getcwd(),
                        help="项目目录 (默认: 当前目录)")
    parser.add_argument("--once", action="store_true",
                        help="只扫描一次，不循环")
    parser.add_argument("--all", action="store_true",
                        help="扫描所有项目，不只是指定项目")
    parser.add_argument("--interval", type=int, default=30,
                        help="扫描间隔秒数 (默认: 30)")
    parser.add_argument("--json", action="store_true",
                        help="输出 JSON 格式")
    args = parser.parse_args()

    project_dir = os.path.abspath(args.project_dir)
    scanner = TokenScanner()

    if not args.json:
        print("=" * 60, flush=True)
        print("  Claude Code Token Monitor", flush=True)
        print(f"  Project: {project_dir}", flush=True)
        print(f"  Mode: {'once' if args.once else f'every {args.interval}s'}", flush=True)
        print(f"  Scope: {'all projects' if args.all else 'this project'}", flush=True)
        print("=" * 60, flush=True)
        print(flush=True)

    cumulative = {"input": 0, "output": 0, "cache_read": 0, "cache_create": 0, "count": 0, "files": 0}

    try:
        while True:
            # 扫描
            if args.all:
                batch = scanner.scan_all_projects()
            else:
                batch = scanner.scan_project(project_dir)

            # 累加
            for k in ["input", "output", "cache_read", "cache_create", "count", "files"]:
                cumulative[k] += batch[k]

            # 心跳信息
            hb = read_heartbeat(project_dir)
            heartbeat_info = {
                "status": hb.get("status", "-"),
                "currentStory": hb.get("currentStory", "-"),
                "done": read_checkpoint_count(project_dir),
            }

            # 输出
            print_report(cumulative, batch, heartbeat_info, args.json)

            if args.once:
                break

            time.sleep(args.interval)

    except KeyboardInterrupt:
        if not args.json:
            total = cumulative["input"] + cumulative["output"]
            print(f"\n{'=' * 60}", flush=True)
            print(f"  Final: input={cumulative['input']:,} output={cumulative['output']:,}", flush=True)
            print(f"  Total: {format_tokens(total)} (+ cache {format_tokens(cumulative['cache_read'])})", flush=True)
            print(f"  Requests: {cumulative['count']}", flush=True)
            print(f"{'=' * 60}", flush=True)


if __name__ == "__main__":
    main()
