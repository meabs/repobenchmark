#!/usr/bin/env bash
# Run one (repo-dir x task) multi-repo benchmark cell end-to-end: reset ->
# launch codex exec (hard timeout via background+watchdog) -> independently
# verify with that repo's real toolchain -> pull real token/tool usage via
# token_usage.py (unchanged, matches by cwd) -> write one consolidated summary.
#
# Usage: run_multirepo_cell.sh <repo_dir_name> <task> [model] [timeout_seconds]
#   repo_dir_name: e.g. python-api-baseline | python-api-recommended |
#                  java-spring-baseline | java-spring-recommended |
#                  react-frontend-baseline | react-frontend-recommended |
#                  event-driven-baseline | event-driven-recommended |
#                  legacy-enterprise-baseline | legacy-enterprise-recommended
#   task: understanding | simple_change | complex

set -uo pipefail

REPO="${1:?repo_dir_name required}"
TASK="${2:?task required}"
MODEL="${3:-gpt-5.6-luna}"
TIMEOUT="${4:-1200}"

MULTI_DIR="/Users/garry/code/multi-repo-benchmark"
SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
PROMPTS_DIR="$SCRATCH/prompts"
RESULTS_DIR="$SCRATCH/multirepo_cell_results"
mkdir -p "$RESULTS_DIR"

CELL="${TASK}__${REPO}"
PROMPT_FILE="$PROMPTS_DIR/${CELL}.txt"
LOG="$RESULTS_DIR/${CELL}.log"
LASTMSG="$RESULTS_DIR/${CELL}.lastmsg.txt"
SUMMARY="$RESULTS_DIR/${CELL}.summary.json"
REPO_DIR="$MULTI_DIR/$REPO"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "ERROR: no prompt file at $PROMPT_FILE" >&2
  exit 1
fi
if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: no repo dir at $REPO_DIR" >&2
  exit 1
fi

echo "=== CELL $CELL (timeout ${TIMEOUT}s) ==="

# 1. Reset this repo to a clean baseline before the run.
git -C "$REPO_DIR" reset --hard HEAD >/dev/null 2>&1
git -C "$REPO_DIR" clean -fdx >/dev/null 2>&1

# 2. Launch codex exec with a hard timeout (background + watchdog kill).
#    Export JAVA_HOME/DOTNET_ROOT into codex's own sandbox env -- Homebrew's
#    openjdk@21 is keg-only (not on default PATH, no npx-style fallback), so
#    without this the agent itself can never run mvnw/java, only our separate
#    post-hoc verification step can. This was a real harness bug found via a
#    failed rerun; fixed here so the agent can self-verify like it can for the
#    other 3 stacks (python3/npx/dotnet were all agent-discoverable already).
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$JAVA_HOME/bin:$DOTNET_ROOT:$PATH"

START_EPOCH=$(date +%s)
codex exec --cd "$REPO_DIR" -m "$MODEL" -s danger-full-access --ignore-user-config \
  -c model_reasoning_effort="high" \
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

# 4. Task-aware, repo-stack-aware independent verification.
VERIFY_JSON="{}"

verify_python_api() {
  local vdb="bench_verify_${REPO//-/_}_${TASK}"
  dropdb -h localhost --if-exists "$vdb" 2>/dev/null
  createdb -h localhost "$vdb"
  ( cd "$REPO_DIR" && \
    python3 -m venv venv --upgrade-deps >/dev/null 2>&1 && \
    venv/bin/pip install -e .[test] >/dev/null 2>&1 )
  TEST_LOG=$( cd "$REPO_DIR" && DATABASE_NAME="$vdb" venv/bin/py.test -q tests/ 2>&1 )
  TEST_EXIT=$?
  echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.test.log"
  TEST_SUMMARY_LINE=$(echo "$TEST_LOG" | grep -E "passed|failed|error" | tail -1)
  dropdb -h localhost --if-exists "$vdb" 2>/dev/null
  python3 -c "
import json, sys
print(json.dumps({'test_exit_code': int(sys.argv[1]), 'test_summary_line': sys.argv[2].strip()}))
" "$TEST_EXIT" "$TEST_SUMMARY_LINE"
}

verify_maven() {
  TEST_LOG=$( cd "$REPO_DIR" && JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" ./mvnw -q -B test 2>&1 )
  TEST_EXIT=$?
  echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.test.log"
  local n_pass=0 n_fail=0 n_err=0
  if [[ -d "$REPO_DIR/target/surefire-reports" ]]; then
    read -r n_pass n_fail n_err <<EOF
$(python3 -c "
import glob, re
tot_run=tot_fail=tot_err=0
for f in glob.glob('$REPO_DIR/target/surefire-reports/*.txt'):
    txt = open(f).read()
    m = re.search(r'Tests run: (\d+), Failures: (\d+), Errors: (\d+)', txt)
    if m:
        tot_run += int(m.group(1)); tot_fail += int(m.group(2)); tot_err += int(m.group(3))
print(tot_run - tot_fail - tot_err, tot_fail, tot_err)
")
EOF
  fi
  python3 -c "
import json, sys
print(json.dumps({'test_exit_code': int(sys.argv[1]), 'tests_passed': int(sys.argv[2]), 'tests_failed': int(sys.argv[3]), 'tests_errored': int(sys.argv[4])}))
" "$TEST_EXIT" "$n_pass" "$n_fail" "$n_err"
}

verify_react_vite() {
  local app_dir="$REPO_DIR/apps/react-vite"
  ( cd "$app_dir" && npx --yes yarn install >/dev/null 2>&1 && cp -f .env.example .env )
  TEST_LOG=$( cd "$app_dir" && npx --yes vitest run 2>&1 )
  TEST_EXIT=$?
  echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.test.log"
  TEST_SUMMARY_LINE=$(echo "$TEST_LOG" | grep -E "Test Files" | tail -1)
  python3 -c "
import json, sys
print(json.dumps({'test_exit_code': int(sys.argv[1]), 'test_summary_line': sys.argv[2].strip()}))
" "$TEST_EXIT" "$TEST_SUMMARY_LINE"
}

verify_dotnet_ordering() {
  export PATH="$HOME/.dotnet:$PATH"
  export DOTNET_ROOT="$HOME/.dotnet"
  TEST_LOG=$( cd "$REPO_DIR" && dotnet test tests/Ordering.UnitTests/Ordering.UnitTests.csproj 2>&1 )
  TEST_EXIT=$?
  echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.test.log"
  TEST_SUMMARY_LINE=$(echo "$TEST_LOG" | grep -E "total:|Passed!|Failed!" | tail -3 | tr '\n' ' ')
  python3 -c "
import json, sys
print(json.dumps({'test_exit_code': int(sys.argv[1]), 'test_summary_line': sys.argv[2].strip()}))
" "$TEST_EXIT" "$TEST_SUMMARY_LINE"
}

if [[ "$TASK" == "complex" || "$TASK" == "simple_change" ]]; then
  case "$REPO" in
    python-api-*) VERIFY_JSON="$(verify_python_api)" ;;
    java-spring-*|legacy-enterprise-*) VERIFY_JSON="$(verify_maven)" ;;
    react-frontend-*) VERIFY_JSON="$(verify_react_vite)" ;;
    event-driven-*) VERIFY_JSON="$(verify_dotnet_ordering)" ;;
    *) VERIFY_JSON='{"error": "no verifier for this repo"}' ;;
  esac
elif [[ "$TASK" == "understanding" ]]; then
  ANSWER_PRESENT=false
  if [[ -f "$REPO_DIR/ANSWER.md" ]]; then
    cp "$REPO_DIR/ANSWER.md" "$RESULTS_DIR/${CELL}.ANSWER.md"
    ANSWER_PRESENT=true
  fi
  UNEXPECTED=$(git -C "$REPO_DIR" status --short | grep -v -E "ANSWER\.md|RUN_METRICS\.json|\.gitignore|^\?\? (venv|node_modules|target|bin|obj)/" | wc -l | tr -d ' ')
  VERIFY_JSON=$(python3 -c "
import json, sys
print(json.dumps({'answer_present': sys.argv[1] == 'true', 'unexpected_file_changes': int(sys.argv[2])}))
" "$ANSWER_PRESENT" "$UNEXPECTED")
fi

# 5. Real token usage AND real tool usage (unchanged script, matches by cwd).
USAGE_JSON=$(python3 "/Users/garry/code/benchmark/token_usage.py" --cwd "$REPO_DIR" --json 2>&1)
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
    'verification': json.loads(verify_json) if verify_json.strip().startswith('{') else {'raw': verify_json},
    'real_usage': json.loads(usage_json) if usage_json.strip().startswith('{') else {'raw': usage_json},
}
print(json.dumps(d, indent=2))
" "$CELL" "$REPO" "$TASK" "$EXIT_CODE" "$TIMED_OUT" "$WALL" "$METRICS_PRESENT" "$VERIFY_JSON" "$USAGE_JSON" | tee "$SUMMARY"

TOTAL_TOKENS=$(python3 -c "
import json
try:
    print(json.loads('''$USAGE_JSON''').get('total_tokens', 0))
except Exception:
    print('?')
" 2>/dev/null || echo "?")
echo "=== CELL $CELL done: exit=$EXIT_CODE timed_out=$TIMED_OUT wall=${WALL}s tokens=${TOTAL_TOKENS} ==="
