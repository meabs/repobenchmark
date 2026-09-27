#!/usr/bin/env python3
"""
Sum real token usage AND real tool usage for a Codex CLI session, straight from
its rollout transcript -- not self-reported.

An agent can't report either of these about itself mid-run. Token counts are
response metadata attached by the API, never part of the model's own context.
Tool-call counts written to a self-authored RUN_METRICS.json are the agent's own
bookkeeping, which can drift from what it actually did. Codex CLI already logs
both to ~/.codex/sessions/<year>/<month>/<day>/rollout-<timestamp>-<session-id>.jsonl:

- `token_usage_record` events carry a `thread_token_usage` block that is the
  running CUMULATIVE total for the whole session -- the last one in the file is
  the session's final total.
- `response_item` events of type `custom_tool_call` are every real action Codex
  took. In the "code mode" tool-use style this CLI uses, there are exactly two
  shapes: the JS wrapper contains `*** Begin Patch` (a file edit via apply_patch)
  or a `tools.exec_command({cmd: ...})` call (an arbitrary shell command). That
  split is exact, unlike a self-reported read/edit/bash/search breakdown, which
  requires the agent to correctly categorize and tally its own actions.

Usage:
  python3 token_usage.py                    list recent Codex sessions, newest
                                             first, with cwd and final token totals
  python3 token_usage.py <session-id>       full breakdown for one session
  python3 token_usage.py /path/to/rollout.jsonl   same, for an exact file
  python3 token_usage.py --cwd <path>       full breakdown for the most recent
                                             session whose cwd matches
  add --json to any of the above (except the bare list) for machine-readable output
"""

import json
import sys
from pathlib import Path

SESSIONS_DIR = Path.home() / ".codex" / "sessions"


def all_rollouts():
    return sorted(SESSIONS_DIR.glob("*/*/*/rollout-*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)


def read_session(path: Path):
    """Return a dict: cwd, thread_token_usage (final, cumulative), turns
    (count of token_usage_record events), and real tool-usage counts derived
    from custom_tool_call events."""
    cwd = None
    last_usage = None
    turns = 0
    tool_calls_total = 0
    file_edits = 0
    shell_execs = 0
    reasoning_steps = 0

    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = d.get("type")
            if t == "session_meta":
                cwd = d.get("payload", {}).get("cwd")
            elif t == "token_usage_record":
                turns += 1
                last_usage = d.get("payload", {}).get("thread_token_usage")
            elif t == "response_item":
                payload = d.get("payload", {})
                pt = payload.get("type")
                if pt == "custom_tool_call":
                    tool_calls_total += 1
                    inp = payload.get("input", "") or ""
                    if "Begin Patch" in inp:
                        file_edits += 1
                    else:
                        shell_execs += 1
                elif pt == "reasoning":
                    reasoning_steps += 1

    return {
        "cwd": cwd,
        "token_usage": last_usage,
        "api_turns": turns,
        "tool_calls_total": tool_calls_total,
        "file_edits": file_edits,
        "shell_execs": shell_execs,
        "reasoning_steps": reasoning_steps,
    }


def find_by_id(arg: str) -> Path:
    p = Path(arg).expanduser()
    if p.is_file():
        return p
    matches = [f for f in all_rollouts() if arg in f.name]
    if not matches:
        sys.exit(f"No session found matching '{arg}' under {SESSIONS_DIR}")
    if len(matches) > 1:
        sys.exit("Multiple sessions match:\n" + "\n".join(str(m) for m in matches))
    return matches[0]


def find_by_cwd(cwd_arg: str) -> Path:
    target = str(Path(cwd_arg).expanduser().resolve())
    for f in all_rollouts():
        info = read_session(f)
        if info["cwd"] and str(Path(info["cwd"]).resolve()) == target:
            return f
    sys.exit(f"No session found with cwd == {target}")


def fmt(n):
    return f"{n:,}" if isinstance(n, int) else str(n)


def print_breakdown(path: Path, as_json: bool = False):
    info = read_session(path)
    usage = info["token_usage"] or {}

    if as_json:
        print(json.dumps({
            "session": str(path),
            "cwd": info["cwd"],
            "api_turns": info["api_turns"],
            "tool_calls_total": info["tool_calls_total"],
            "file_edits": info["file_edits"],
            "shell_execs": info["shell_execs"],
            "reasoning_steps": info["reasoning_steps"],
            "input_tokens": usage.get("input_tokens"),
            "cached_input_tokens": usage.get("cached_input_tokens"),
            "output_tokens": usage.get("output_tokens"),
            "reasoning_output_tokens": usage.get("reasoning_output_tokens"),
            "total_tokens": usage.get("total_tokens"),
        }, indent=2))
        return

    print(f"Session:  {path}")
    print(f"cwd:      {info['cwd']}")
    print(f"API turns with recorded usage: {info['api_turns']}")
    print()
    print("Real tool usage (from custom_tool_call events, not self-reported):")
    print(f"  tool_calls_total          {fmt(info['tool_calls_total']):>10}")
    print(f"  file_edits (apply_patch)  {fmt(info['file_edits']):>10}")
    print(f"  shell_execs               {fmt(info['shell_execs']):>10}")
    print(f"  reasoning_steps           {fmt(info['reasoning_steps']):>10}")
    print()
    if not usage:
        print("No token_usage_record found in this session.")
        return
    print("Real token usage:")
    for k in ("input_tokens", "cached_input_tokens", "cache_write_input_tokens",
              "output_tokens", "reasoning_output_tokens", "total_tokens"):
        if k in usage:
            print(f"  {k:<26} {fmt(usage[k]):>10}")


def list_recent(limit: int = 15):
    files = all_rollouts()
    if not files:
        print(f"No sessions found under {SESSIONS_DIR}")
        return
    print(f"{'session id':<40} {'cwd':<48} {'total_tokens':>12}")
    for f in files[:limit]:
        info = read_session(f)
        usage = info["token_usage"] or {}
        total = usage.get("total_tokens")
        print(f"{f.stem[-36:]:<40} {(info['cwd'] or '?'):<48} {fmt(total) if total is not None else '-':>12}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = "--json" in sys.argv[1:]

    if not args:
        list_recent()
    elif args[0] == "--cwd" and len(args) == 2:
        print_breakdown(find_by_cwd(args[1]), as_json=as_json)
    else:
        print_breakdown(find_by_id(args[0]), as_json=as_json)
