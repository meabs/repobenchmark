#!/usr/bin/env bash
# Re-runs all 12 Maven-repo cells (java-spring + legacy-enterprise, both arms,
# all 3 tasks) now that JAVA_HOME is correctly exported into codex's own
# sandbox. The original 12 results are archived as *.preJavaFix_failed / kept
# as-is for comparison; fresh results land under the normal names.
set -uo pipefail

SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
RD="$SCRATCH/multirepo_cell_results"
CELL_SCRIPT="$SCRATCH/run_multirepo_cell.sh"
PROGRESS_FILE="$SCRATCH/rerun12_progress.log"
> "$PROGRESS_FILE"

REPOS=(java-spring legacy-enterprise)
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
      CELL="${task}__${REPO_DIR_NAME}"
      TO="$(timeout_for "$task")"

      # Already re-verified cleanly post-JAVA_HOME-fix; skip re-running it.
      if [[ "$CELL" == "simple_change__java-spring-recommended" ]]; then
        echo "[$N/$TOTAL] SKIP  $task / $REPO_DIR_NAME (already re-verified post-fix) $(date -u +%FT%TZ)" | tee -a "$PROGRESS_FILE"
        continue
      fi

      # Archive the pre-JAVA_HOME-fix result before overwriting.
      for f in "$RD/$CELL".*; do
        [[ -f "$f" ]] || continue
        case "$f" in *.preJavaFix_failed.*|*.attempt1_failed.*) continue ;; esac
        base=$(basename "$f")
        ext="${base#"$CELL".}"
        cp "$f" "$RD/${CELL}.preJavaFix.${ext}"
      done

      echo "[$N/$TOTAL] START $task / $REPO_DIR_NAME (timeout ${TO}s) $(date -u +%FT%TZ)" | tee -a "$PROGRESS_FILE"
      bash "$CELL_SCRIPT" "$REPO_DIR_NAME" "$task" "gpt-5.6-luna" "$TO" \
        > "$RD/${CELL}.rerun12.runlog.txt" 2>&1
      CELL_EXIT=$?
      SUMMARY_FILE="$RD/${CELL}.summary.json"
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

echo "=== RERUN12 COMPLETE $(date -u +%FT%TZ) ===" | tee -a "$PROGRESS_FILE"
