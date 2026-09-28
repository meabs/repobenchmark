#!/usr/bin/env bash
# Cursor cross-tool pilot for the multi-repo study, mirroring
# run_multirepo_cell.sh's structure but invoking cursor-agent instead of codex.
# Usage: run_multirepo_cursor_cell.sh <repo_dir_name> <task> [model] [timeout_s]

set -uo pipefail

REPO="${1:?repo_dir_name required}"
TASK="${2:?task required}"
MODEL="${3:-auto}"
TIMEOUT="${4:-1200}"

MULTI_DIR="/Users/garry/code/multi-repo-benchmark"
SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
PROMPTS_DIR="$SCRATCH/prompts"
RESULTS_DIR="$SCRATCH/multirepo_cursor_results"
mkdir -p "$RESULTS_DIR"

CELL="${TASK}__${REPO}__cursor"
PROMPT_FILE="$PROMPTS_DIR/${TASK}__${REPO}.txt"
LOG="$RESULTS_DIR/${CELL}.streamjson.log"
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

git -C "$REPO_DIR" reset --hard HEAD >/dev/null 2>&1
git -C "$REPO_DIR" clean -fdx >/dev/null 2>&1

START_EPOCH=$(date +%s)
( cd "$REPO_DIR" && cursor-agent -p --model "$MODEL" --force --output-format stream-json < "$PROMPT_FILE" > "$LOG" 2>&1 ) &
CURSOR_PID=$!
( sleep "$TIMEOUT"; kill -9 "$CURSOR_PID" 2>/dev/null ) &
WATCHER_PID=$!
wait "$CURSOR_PID" 2>/dev/null
EXIT_CODE=$?
kill "$WATCHER_PID" 2>/dev/null
wait "$WATCHER_PID" 2>/dev/null
END_EPOCH=$(date +%s)
WALL=$((END_EPOCH - START_EPOCH))
TIMED_OUT=false
if [[ "$WALL" -ge "$TIMEOUT" ]]; then TIMED_OUT=true; fi

VERIFY_JSON="{}"
if [[ "$TASK" == "complex" || "$TASK" == "simple_change" ]]; then
  case "$REPO" in
    react-frontend-*)
      app_dir="$REPO_DIR/apps/react-vite"
      ( cd "$app_dir" && npx --yes yarn install >/dev/null 2>&1 && cp -f .env.example .env )
      TEST_LOG=$( cd "$app_dir" && npx --yes vitest run 2>&1 )
      TEST_EXIT=$?
      echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.test.log"
      TEST_SUMMARY_LINE=$(echo "$TEST_LOG" | grep -E "Test Files" | tail -1)
      VERIFY_JSON=$(python3 -c "
import json, sys
print(json.dumps({'test_exit_code': int(sys.argv[1]), 'test_summary_line': sys.argv[2].strip()}))
" "$TEST_EXIT" "$TEST_SUMMARY_LINE")
      ;;
    java-spring-*)
      export JAVA_HOME=/opt/homebrew/opt/openjdk@21
      export PATH="$JAVA_HOME/bin:$PATH"
      TEST_LOG=$( cd "$REPO_DIR" && ./mvnw -q -B test 2>&1 )
      TEST_EXIT=$?
      echo "$TEST_LOG" > "$RESULTS_DIR/${CELL}.test.log"
      n_pass=0; n_fail=0; n_err=0
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
      VERIFY_JSON=$(python3 -c "
import json, sys
print(json.dumps({'test_exit_code': int(sys.argv[1]), 'tests_passed': int(sys.argv[2]), 'tests_failed': int(sys.argv[3]), 'tests_errored': int(sys.argv[4])}))
" "$TEST_EXIT" "$n_pass" "$n_fail" "$n_err")
      ;;
    *) VERIFY_JSON='{"error": "no verifier configured for this repo in cursor harness"}' ;;
  esac
elif [[ "$TASK" == "understanding" ]]; then
  ANSWER_PRESENT=false
  if [[ -f "$REPO_DIR/ANSWER.md" ]]; then
    cp "$REPO_DIR/ANSWER.md" "$RESULTS_DIR/${CELL}.ANSWER.md"
    ANSWER_PRESENT=true
  fi
  UNEXPECTED=$(git -C "$REPO_DIR" status --short | grep -v -E "ANSWER\.md|\.gitignore|^\?\? (node_modules|target)/" | wc -l | tr -d ' ')
  VERIFY_JSON=$(python3 -c "
import json, sys
print(json.dumps({'answer_present': sys.argv[1] == 'true', 'unexpected_file_changes': int(sys.argv[2])}))
" "$ANSWER_PRESENT" "$UNEXPECTED")
fi

USAGE_JSON=$(python3 "$SCRATCH/cursor_usage.py" "$LOG" 2>/dev/null || echo '{}')
echo "$USAGE_JSON" > "$RESULTS_DIR/${CELL}.usage.json"

python3 -c "
import json
d = {
  'cell': '$CELL', 'repo': '$REPO', 'task': '$TASK', 'model': '$MODEL',
  'exit_code': $EXIT_CODE, 'timed_out': $([ "$TIMED_OUT" = true ] && echo True || echo False),
  'wall_seconds': $WALL,
  'verification': json.loads('''$VERIFY_JSON'''),
  'real_usage': json.loads('''$USAGE_JSON'''),
}
print(json.dumps(d, indent=2))
" | tee "$SUMMARY"

echo "=== CELL $CELL done: exit=$EXIT_CODE timed_out=$TIMED_OUT wall=${WALL}s ==="
