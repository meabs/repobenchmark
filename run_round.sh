#!/usr/bin/env bash
# Run one full round: all 9 (task x repo) cells, in a controllable order, back
# to back. Fails fast — stops the round immediately if any cell errors, times
# out, or fails verification, rather than burning time/tokens on a broken
# sequence.
#
# Usage: run_round.sh <round_label> [order_understanding] [order_simple] [order_complex]
#   round_label: e.g. "r3" — passed through to run_cell.sh so this round's
#                files don't clobber other rounds'.
#   order_*: comma-separated repo order for that task group, e.g.
#            "repo-agent-optimised,repo-agent-skill,repo-baseline"
#            Defaults to baseline,optimised,skill (same order as rounds 1-2)
#            if omitted — pass explicit orders to control for the
#            execution-order/cache-warming confound noted in the report.
#
# Writes $RESULTS_DIR/round_<label>.meta.json recording the exact order used
# and start/end time, plus the usual per-cell files from run_cell.sh
# (suffixed __<round_label>).

set -uo pipefail

ROUND_LABEL="${1:?round_label required, e.g. r3}"
ORDER_UNDERSTANDING="${2:-repo-baseline,repo-agent-optimised,repo-agent-skill}"
ORDER_SIMPLE="${3:-repo-baseline,repo-agent-optimised,repo-agent-skill}"
ORDER_COMPLEX="${4:-repo-baseline,repo-agent-optimised,repo-agent-skill}"
MODEL="${5:-gpt-5.6-luna}"

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="/private/tmp/claude-501/-Users-garry-code-benchmark/c93218a9-16b4-4885-bc97-8f8edcb49904/scratchpad"
RESULTS_DIR="$SCRATCH/cell_results"
mkdir -p "$RESULTS_DIR"

TIMEOUT_UNDERSTANDING=1200
TIMEOUT_SIMPLE=1200
TIMEOUT_COMPLEX=1800

START_EPOCH=$(date +%s)
echo "=== ROUND $ROUND_LABEL starting ==="
echo "    understanding order: $ORDER_UNDERSTANDING"
echo "    simple_change order: $ORDER_SIMPLE"
echo "    complex order:       $ORDER_COMPLEX"

run_group() {
  local task="$1" order="$2" timeout="$3"
  IFS=',' read -ra repos <<< "$order"
  for repo in "${repos[@]}"; do
    "$BENCH_DIR/run_cell.sh" "$repo" "$task" "$MODEL" "$timeout" "$ROUND_LABEL"
    local cell="${task}__${repo}__${ROUND_LABEL}"
    local summary="$RESULTS_DIR/${cell}.summary.json"
    if [[ ! -f "$summary" ]]; then
      echo "!!! ROUND $ROUND_LABEL ABORTED: no summary written for $cell" >&2
      exit 1
    fi
    # A timeout kill is only a real failure if verification also failed (or
    # never ran) — the watchdog can kill a session a few seconds after its
    # actual work (migration/tests/answer) already completed and was
    # verified, while it was still doing final wrap-up. Judge by
    # verification outcome, not the timeout flag alone.
    local result
    result=$(python3 -c "
import json
d = json.load(open('$summary'))
v = d.get('verification', {})
# A crashed/zero-work session (e.g. an auth failure mid-run) can still show
# migrate/pytest exit 0, because the PRE-EXISTING test suite passes trivially
# against an untouched repo. Real completion always writes RUN_METRICS.json
# per the prompt protocol, so require that too, not just 'tests pass'.
verified_ok = bool(d.get('run_metrics_present'))
if verified_ok:
    if 'migrate_exit_code' in v:
        verified_ok = v.get('migrate_exit_code') == 0 and v.get('test_exit_code') == 0
    elif 'answer_present' in v:
        verified_ok = bool(v.get('answer_present'))
    else:
        verified_ok = False

if d.get('exit_code') != 0 and not verified_ok:
    print('FAIL'); raise SystemExit(1)
if not verified_ok:
    print('FAIL'); raise SystemExit(1)
if d.get('timed_out'):
    print('WARN')
else:
    print('OK')
" ) || true
    if [[ "$result" == "FAIL" ]]; then
      echo "!!! ROUND $ROUND_LABEL ABORTED at $cell: verification failed" >&2
      echo "    Inspect $summary and the matching .log before retrying." >&2
      exit 1
    elif [[ "$result" == "WARN" ]]; then
      echo "    $cell: OK (verified), but timed_out=true — watchdog killed it just after its own work finished. Timing/duration for this cell is unreliable; correctness is not."
    else
      echo "    $cell: OK"
    fi
  done
}

run_group "understanding" "$ORDER_UNDERSTANDING" "$TIMEOUT_UNDERSTANDING"
run_group "simple_change" "$ORDER_SIMPLE" "$TIMEOUT_SIMPLE"
run_group "complex" "$ORDER_COMPLEX" "$TIMEOUT_COMPLEX"

END_EPOCH=$(date +%s)
python3 -c "
import json, sys
d = {
    'round': sys.argv[1],
    'order_understanding': sys.argv[2].split(','),
    'order_simple_change': sys.argv[3].split(','),
    'order_complex': sys.argv[4].split(','),
    'model': sys.argv[5],
    'wall_seconds': int(sys.argv[6]),
}
print(json.dumps(d, indent=2))
" "$ROUND_LABEL" "$ORDER_UNDERSTANDING" "$ORDER_SIMPLE" "$ORDER_COMPLEX" "$MODEL" "$((END_EPOCH-START_EPOCH))" \
  | tee "$RESULTS_DIR/round_${ROUND_LABEL}.meta.json"

echo "=== ROUND $ROUND_LABEL complete: all 9 cells OK, $((END_EPOCH-START_EPOCH))s ==="
