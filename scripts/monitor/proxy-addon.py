"""
mitmproxy addon — 拦截 Claude API 请求，实时记录 token

用法:
  mitmdump -s proxy-addon.py --set upstream_cert=false -p 8080

然后在 Claude Code settings.json 的 env 中添加:
  "HTTP_PROXY": "http://127.0.0.1:8080",
  "HTTPS_PROXY": "http://127.0.0.1:8080"

依赖: pip install mitmproxy
"""

import json
import time
import os
from mitmproxy import http

LOG_FILE = os.path.expanduser("~/.claude/token-usage.jsonl")


class TokenMonitor:
    def __init__(self):
        self.total_input = 0
        self.total_output = 0
        self.total_cache_read = 0
        self.request_count = 0

    def response(self, flow: http.HTTPFlow):
        if "anthropic" not in flow.request.pretty_host:
            return
        if "/messages" not in flow.request.path:
            return

        try:
            resp_text = flow.response.get_text(strict=False)
            if not resp_text:
                return

            usage = None
            model = None

            if "event: message_stop" in resp_text:
                # SSE 流式响应
                for line in resp_text.split("\n"):
                    if line.startswith("data: "):
                        try:
                            data = json.loads(line[6:])
                            if data.get("type") == "message_delta" and "usage" in data:
                                usage = data["usage"]
                            if data.get("type") == "message_start" and "message" in data:
                                model = data["message"].get("model", "unknown")
                                if "usage" in data["message"]:
                                    start_usage = data["message"]["usage"]
                                    if usage:
                                        usage = {**start_usage, **usage}
                                    else:
                                        usage = start_usage
                        except json.JSONDecodeError:
                            continue
            else:
                try:
                    data = json.loads(resp_text)
                    usage = data.get("usage")
                    model = data.get("model", "unknown")
                except json.JSONDecodeError:
                    return

            if not usage:
                return

            input_tokens = usage.get("input_tokens", 0)
            output_tokens = usage.get("output_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            cache_create = usage.get("cache_creation_input_tokens", 0)

            self.total_input += input_tokens
            self.total_output += output_tokens
            self.total_cache_read += cache_read
            self.request_count += 1

            record = {
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "unix_ts": int(time.time()),
                "model": model,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "cache_read_input_tokens": cache_read,
                "cache_creation_input_tokens": cache_create,
                "cumulative_input": self.total_input,
                "cumulative_output": self.total_output,
                "cumulative_cache_read": self.total_cache_read,
                "request_count": self.request_count,
                "path": flow.request.path,
                "status": flow.response.status_code,
            }

            with open(LOG_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")

            total = input_tokens + output_tokens
            print(f"[TOKEN] #{self.request_count} | {model} | "
                  f"in={input_tokens} out={output_tokens} cache={cache_read} | "
                  f"cumulative: {self.total_input+self.total_output:,}")

        except Exception as e:
            print(f"[TOKEN] error: {e}")


addons = [TokenMonitor()]
