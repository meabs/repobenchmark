#!/usr/bin/env bash
# Run one (repo x task) benchmark cell end-to-end: reset -> launch codex exec (with
# a hard timeout, since macOS has no `timeout` binary) -> independently verify ->
# pull real token usage -> write one consolidated summary. Designed to be invoked
# once per cell (sequentially — see run_all_cells.sh) so the caller does one tool
# call per cell instead of ~8.
#
# Usage: run_cell.sh <repo> <task> [model] [timeout_seconds] [round_label]
#   repo:  repo-baseline | repo-agent-optimised | repo-agent-skill
#   task:  complex | understanding | simple_change
#   round_label: optional, e.g. "r3" — appended to output filenames so repeat
#     rounds don't clobber each other. Omit for the old (round-less) naming.
#
# Pins model_reasoning_effort=medium explicitly (matches the config.toml default
# that --ignore-user-config otherwise drops) so reasoning effort is a controlled
# variable, not whatever the model's own default happens to be.
#
# Writes to $RESULTS_DIR (below): <cell>.log, <cell>.lastmsg.txt,
# <cell>.RUN_METRICS.json, <cell>.tokens.txt, <cell>.summary.json, and for
# understanding tasks <cell>.ANSWER.md.

set -uo pipefail

REPO="${1:?repo required}"
TASK="${2:?task required}"
MODEL="${3:-gpt-5.6-luna}"
TIMEOUT="${4:-1200}"
ROUND_LABEL="${5:-}"

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
PROMPTS_DIR="$SCRATCH/prompts"
RESULTS_DIR="$SCRATCH/cell_results"
mkdir -p "$RESULTS_DIR"

if [[ -n "$ROUND_LABEL" ]]; then
  CELL="${TASK}__${REPO}__${ROUND_LABEL}"
else
  CELL="${TASK}__${REPO}"
fi
PROMPT_CELL="${TASK}__${REPO}"
PROMPT_FILE="$PROMPTS_DIR/${PROMPT_CELL}.txt"
LOG="$RESULTS_DIR/${CELL}.log"
LASTMSG="$RESULTS_DIR/${CELL}.lastmsg.txt"
SUMMARY="$RESULTS_DIR/${CELL}.summary.json"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: no prompt file at $PROMPT_FILE" >&2
  exit 1
fi

db_name_for() {
  case "$1" in
    repo-baseline) echo "app_baseline" ;;
    repo-agent-optimised) echo "app_optimised" ;;
    repo-agent-skill) echo "app_skill" ;;
    repo-agent-recommended) echo "app_recommended" ;;
    *) echo "" ;;
  esac
}
DB_NAME="$(db_name_for "$REPO")"
REPO_DIR="$BENCH_DIR/$REPO"

echo "=== CELL $CELL (timeout ${TIMEOUT}s) ==="

# 1. Reset this repo and its live DB to a clean baseline before the run.
git -C "$REPO_DIR" reset --hard HEAD >/dev/null 2>&1
git -C "$REPO_DIR" clean -fdx >/dev/null 2>&1
dropdb -h localhost --if-exists "$DB_NAME" 2>/dev/null
createdb -h localhost "$DB_NAME"

# 2. Launch codex exec with a hard timeout (background + watchdog kill, since
#    this macOS has no `timeout`/`gtimeout`).
START_EPOCH=$(date +%s)
codex exec --cd "$REPO_DIR" -m "$MODEL" -s danger-full-access --ignore-user-config \
  -c model_reasoning_effort="medium" \
  --output-last-message "$LASTMSG" \
  - < "$PROMPT_FILE" > "$LOG" 2>&1 &
CODEX_PID=$!

( sleep "$TIMEOUT"; kill -9 "$CODEX_PID" 2>/dev/null ) &
WATCHER_PID=$!

wait "$CODEX_PID" 2>/dev/null
EXIT_CODE=$?
kill "$WATCHER_PID" 2>/dev/null
wait "$WATCHER_PID" 2>/dev/null

END_EPOCH=$(date +%s)
WALL=$((END_EPOCH - START_EPOCH))
TIMED_OUT=false
if [[ "$WALL" -ge "$TIMEOUT" ]]; then TIMED_OUT=true; fi

# 3. Copy RUN_METRICS.json out if present.
METRICS_PRESENT=false
if [[ -f "$REPO_DIR/RUN_METRICS.json" ]]; then
  cp "$REPO_DIR/RUN_METRICS.json" "$RESULTS_DIR/${CELL}.RUN_METRICS.json"
  METRICS_PRESENT=true
fi

# 4. Task-aware independent verification.
VERIFY_JSON="{}"
if [[ "$TASK" == "complex" || "$TASK" == "simple_change" ]]; then
  VDB="bench_verify_${REPO//-/_}_${TASK}"
  dropdb -h localhost --if-exists "$VDB" 2>/dev/null
  createdb -h localhost "$VDB"
  pushd "$REPO_DIR/backend" >/dev/null
  uv sync >/dev/null 2>&1
  export FASTAPI_ENV=development
  export SECRET_KEY=changethis-benchmark-secret-key-1234567890
  export PROJECT_NAME="Benchmark Verify"
  export FIRST_SUPERUSER=admin@example.com
  export FIRST_SUPERUSER_PASSWORD=changethis123
  export DATABASE_URL="postgresql://garry@localhost:5432/$VDB"
  MIGRATE_LOG=$(uv run alembic upgrade head 2>&1)
  MIGRATE_EXIT=$?
  TEST_LOG=$(uv run pytest tests/ -q 2>&1)
  TEST_EXIT=$?
  echo "$MIGRATE_LOG" > "$RESULTS_DIR/${CELL}.migrate.log"
  echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.pytest.log"
  TEST_SUMMARY_LINE=$(echo "$TEST_LOG" | grep -E "passed|failed|error" | tail -1)
  unset FASTAPI_ENV SECRET_KEY PROJECT_NAME FIRST_SUPERUSER FIRST_SUPERUSER_PASSWORD DATABASE_URL
  popd >/dev/null
  dropdb -h localhost --if-exists "$VDB" 2>/dev/null
  VERIFY_JSON=$(python3 -c "
import json, sys
migrate_exit, test_exit, test_summary = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    'migrate_exit_code': int(migrate_exit),
    'test_exit_code': int(test_exit),
    'test_summary_line': test_summary.strip(),
}))
" "$MIGRATE_EXIT" "$TEST_EXIT" "$TEST_SUMMARY_LINE")
elif [[ "$TASK" == "understanding" ]]; then
  ANSWER_PRESENT=false
  if [[ -f "$REPO_DIR/ANSWER.md" ]]; then
    cp "$REPO_DIR/ANSWER.md" "$RESULTS_DIR/${CELL}.ANSWER.md"
    ANSWER_PRESENT=true
  fi
  UNEXPECTED=$(git -C "$REPO_DIR" status --short | grep -v -E "ANSWER\.md|RUN_METRICS\.json|\.gitignore" | wc -l | tr -d ' ')
  VERIFY_JSON=$(python3 -c "
import json, sys
answer_present, unexpected = sys.argv[1], sys.argv[2]
print(json.dumps({'answer_present': answer_present == 'true', 'unexpected_file_changes': int(unexpected)}))
" "$ANSWER_PRESENT" "$UNEXPECTED")
fi

# 5. Real token usage AND real tool usage (both from the transcript, not
#    self-reported) via token_usage.py's --json mode.
USAGE_JSON=$(python3 "$BENCH_DIR/token_usage.py" --cwd "$REPO_DIR" --json 2>&1)
echo "$USAGE_JSON" > "$RESULTS_DIR/${CELL}.tokens.json"

# 6. Consolidated summary.
python3 -c "
import json, sys
cell, repo, task, exit_code, timed_out, wall, metrics_present, verify_json, usage_json = sys.argv[1:10]
d = {
    'cell': cell,
    'repo': repo,
    'task': task,
    'exit_code': int(exit_code),
    'timed_out': timed_out == 'true',
    'wall_seconds': int(wall),
    'run_metrics_present': metrics_present == 'true',
    'verification': json.loads(verify_json),
    'real_usage': json.loads(usage_json),
}
print(json.dumps(d, indent=2))
" "$CELL" "$REPO" "$TASK" "$EXIT_CODE" "$TIMED_OUT" "$WALL" "$METRICS_PRESENT" "$VERIFY_JSON" "$USAGE_JSON" | tee "$SUMMARY"

TOTAL_TOKENS=$(python3 -c "import json; print(json.loads('''$USAGE_JSON''').get('total_tokens', 0))" 2>/dev/null || echo "?")
echo "=== CELL $CELL done: exit=$EXIT_CODE timed_out=$TIMED_OUT wall=${WALL}s tokens=${TOTAL_TOKENS} ==="
