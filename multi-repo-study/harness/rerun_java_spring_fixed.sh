#!/usr/bin/env bash
# Waits for the main 30-cell run to finish, archives the original (doc-gap)
# failed results for simple_change/complex on java-spring-recommended under an
# "attempt1_failed" name, then re-runs those two cells against the fixed doc
# layer (verify-work skill added) so both the failure and the fix are on record.
set -uo pipefail

SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
PROGRESS_FILE="$SCRATCH/multirepo_progress.log"
RD="$SCRATCH/multirepo_cell_results"
CELL_SCRIPT="$SCRATCH/run_multirepo_cell.sh"

echo "Waiting for main 30-cell run to complete..."
while ! grep -q "ALL 30 CELLS COMPLETE" "$PROGRESS_FILE" 2>/dev/null; do
  sleep 60
done
echo "Main run complete. Archiving original failed results and re-running fixed cells."

for task in simple_change complex; do
  CELL="${task}__java-spring-recommended"
  for f in "$RD/$CELL".*; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    ext="${base#"$CELL".}"
    cp "$f" "$RD/${CELL}.attempt1_failed.${ext}"
  done
  echo "Archived original failed result for $CELL as attempt1_failed."
done

echo "=== RERUN START $(date -u +%FT%TZ) ==="
for task in simple_change complex; do
  TO=1200
  [[ "$task" == "complex" ]] && TO=1800
  echo "RERUN START $task / java-spring-recommended (timeout ${TO}s) $(date -u +%FT%TZ)"
  bash "$CELL_SCRIPT" "java-spring-recommended" "$task" "gpt-5.6-luna" "$TO" \
    > "$RD/${task}__java-spring-recommended.rerun.runlog.txt" 2>&1
  RERUN_EXIT=$?
  SUMMARY_FILE="$RD/${task}__java-spring-recommended.summary.json"
  STATUS_LINE=$(python3 -c "
import json
try:
    d = json.load(open('$SUMMARY_FILE'))
    print(f\"exit={d.get('exit_code')} timed_out={d.get('timed_out')} wall={d.get('wall_seconds')}s verify={json.dumps(d.get('verification', {}))[:200]}\")
except Exception as e:
    print(f'SUMMARY_READ_ERROR: {e}')
" 2>&1)
  echo "RERUN DONE  $task / java-spring-recommended (harness_exit=$RERUN_EXIT) $STATUS_LINE $(date -u +%FT%TZ)"
done
echo "=== RERUN COMPLETE $(date -u +%FT%TZ) ==="
