#!/usr/bin/env bash
# Sequentially run all 30 multi-repo benchmark cells (5 repos x 2 arms x 3 tasks).
# Emits one PROGRESS line per cell to stdout (and a progress file) so the
# caller can poll for real-time status without tailing full codex logs.

set -uo pipefail

SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
CELL_SCRIPT="$SCRATCH/run_multirepo_cell.sh"
PROGRESS_FILE="$SCRATCH/multirepo_progress.log"
> "$PROGRESS_FILE"

REPOS=(python-api java-spring react-frontend event-driven legacy-enterprise)
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

TOTAL=30
N=0

for repo in "${REPOS[@]}"; do
  for arm in "${ARMS[@]}"; do
    for task in "${TASKS[@]}"; do
      N=$((N+1))
      REPO_DIR_NAME="${repo}-${arm}"
      TO="$(timeout_for "$task")"
      SUMMARY_FILE="$SCRATCH/multirepo_cell_results/${task}__${REPO_DIR_NAME}.summary.json"
      if [[ -f "$SUMMARY_FILE" ]] && python3 -c "
import json, sys
d = json.load(open('$SUMMARY_FILE'))
sys.exit(0 if (d.get('exit_code') == 0 and not d.get('timed_out')) else 1)
" 2>/dev/null; then
        echo "[$N/$TOTAL] SKIP  $task / $REPO_DIR_NAME (already succeeded) $(date -u +%FT%TZ)" | tee -a "$PROGRESS_FILE"
        continue
      fi
      echo "[$N/$TOTAL] START $task / $REPO_DIR_NAME (timeout ${TO}s) $(date -u +%FT%TZ)" | tee -a "$PROGRESS_FILE"
      bash "$CELL_SCRIPT" "$REPO_DIR_NAME" "$task" "gpt-5.6-luna" "$TO" \
        > "$SCRATCH/multirepo_cell_results/${task}__${REPO_DIR_NAME}.runlog.txt" 2>&1
      CELL_EXIT=$?
      SUMMARY_FILE="$SCRATCH/multirepo_cell_results/${task}__${REPO_DIR_NAME}.summary.json"
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

echo "=== ALL $TOTAL CELLS COMPLETE $(date -u +%FT%TZ) ===" | tee -a "$PROGRESS_FILE"
