#!/usr/bin/env bash
# Cursor cross-tool pilot: react-frontend, both arms, all 3 tasks (6 cells).
set -uo pipefail

SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
CELL_SCRIPT="$SCRATCH/run_multirepo_cursor_cell.sh"
PROGRESS_FILE="$SCRATCH/cursor_pilot_progress.log"
> "$PROGRESS_FILE"

REPOS=(react-frontend java-spring)
ARMS=(baseline recommended)
TASKS=(understanding simple_change complex)

timeout_for() {
  case "$1" in
    understanding) echo 1200 ;;
    simple_change) echo 1200 ;;
    complex) echo 1800 ;;
    *) echo 1200 ;;
  esac
}

TOTAL=12
N=0

for repo in "${REPOS[@]}"; do
for arm in "${ARMS[@]}"; do
  for task in "${TASKS[@]}"; do
    N=$((N+1))
    REPO_DIR_NAME="${repo}-${arm}"
    TO="$(timeout_for "$task")"
    echo "[$N/$TOTAL] START $task / $REPO_DIR_NAME (timeout ${TO}s) $(date -u +%FT%TZ)" | tee -a "$PROGRESS_FILE"
    bash "$CELL_SCRIPT" "$REPO_DIR_NAME" "$task" "auto" "$TO" \
      > "$SCRATCH/multirepo_cursor_results/${task}__${REPO_DIR_NAME}__cursor.runlog.txt" 2>&1
    CELL_EXIT=$?
    SUMMARY_FILE="$SCRATCH/multirepo_cursor_results/${task}__${REPO_DIR_NAME}__cursor.summary.json"
    STATUS_LINE=$(python3 -c "
import json
try:
    d = json.load(open('$SUMMARY_FILE'))
    print(f\"exit={d.get('exit_code')} timed_out={d.get('timed_out')} wall={d.get('wall_seconds')}s verify={json.dumps(d.get('verification', {}))[:200]}\")
except Exception as e:
    print(f'SUMMARY_READ_ERROR: {e}')
" 2>&1)
    echo "[$N/$TOTAL] DONE  $task / $REPO_DIR_NAME (harness_exit=$CELL_EXIT) $STATUS_LINE $(date -u +%FT%TZ)" | tee -a "$PROGRESS_FILE"
  done
done
done

echo "=== CURSOR PILOT COMPLETE $(date -u +%FT%TZ) ===" | tee -a "$PROGRESS_FILE"
