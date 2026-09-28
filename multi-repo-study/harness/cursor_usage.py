#!/usr/bin/env python3
"""Extract real token + tool-call usage from a cursor-agent stream-json log."""
import json
import sys


def read_stream(path: str) -> dict:
    tool_calls = 0
    file_edits = 0
    shell_execs = 0
    seen_call_ids = set()
    result = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("type") == "tool_call" and d.get("subtype") == "completed":
                call_id = d.get("call_id")
                if call_id in seen_call_ids:
                    continue
                seen_call_ids.add(call_id)
                tool_calls += 1
                tc = d.get("tool_call", {})
                key = next(iter(tc.keys()), "")
                if key in ("writeToolCall", "editToolCall", "createFileToolCall", "deleteFileToolCall", "applyPatchToolCall"):
                    file_edits += 1
                else:
                    shell_execs += 1
            elif d.get("type") == "result":
                result = d
    usage = (result or {}).get("usage", {})
    return {
        "tool_calls_total": tool_calls,
        "file_edits": file_edits,
        "shell_execs": shell_execs,
        "input_tokens": usage.get("inputTokens"),
        "cached_input_tokens": usage.get("cacheReadTokens"),
        "output_tokens": usage.get("outputTokens"),
        "total_tokens": (usage.get("inputTokens") or 0) + (usage.get("outputTokens") or 0),
        "duration_ms": (result or {}).get("duration_ms"),
        "is_error": (result or {}).get("is_error"),
        "session_id": (result or {}).get("session_id"),
    }


if __name__ == "__main__":
    print(json.dumps(read_stream(sys.argv[1]), indent=2))
