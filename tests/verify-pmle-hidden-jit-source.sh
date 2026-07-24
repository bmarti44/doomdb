#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
matrix="$root/probes/mle/run-hidden-jit-matrix.sh"
ticker="$root/probes/mle/teavm-engine/run-jit-command-stream-mle.sh"
bench="$root/probes/mle/hidden-jit-benchmark.sql"
compiled="$root/artifacts/performance/pmle-hidden-jit/"\
"free-26ai-2026-07-24-immediate_sync.log"
report="$root/artifacts/performance/pmle-hidden-jit/REPORT.md"

bash -n "$matrix" "$ticker"
grep -q 'PMLE_HIDDEN_JIT_EXECUTE' "$matrix"
grep -q 'PMLE_HIDDEN_JIT_EXECUTE' "$ticker"
grep -q "module='PMLE_HIDDEN_JIT'" "$matrix"
grep -q "module='PMLE_HIDDEN_JIT'" "$ticker"
grep -q "sid||','||serial#" "$matrix"
grep -q "sid||','||serial#" "$ticker"
grep -q 'doom_match_worker.start_warm_pool' "$matrix"
grep -q 'doom_match_worker.start_warm_pool' "$ticker"
grep -q 'classification=DIAGNOSTIC_NOT_GATE' "$bench"
grep -q '^PMLE_HIDDEN_JIT|PASS|cell=immediate_sync|terminal_samples=40|' \
  "$compiled"
awk -F'[=|]' '
  /PMLE_HIDDEN_JIT_SAMPLE.*cell=immediate_sync/ {
    for (i=1;i<=NF;i++) {
      if ($i=="ns_per_iteration" && $(i+1)+0<=15) pass=1
    }
  }
  END { exit !pass }
' "$compiled"
grep -q 'more than 100x faster' "$report"
grep -q 'compilation hang' "$report"

if rg -n '_mle_(compile_immediately|compilation_sync|compilation_errors_are_fatal)' \
  "$root/sql" "$root/deploy" "$root/scripts/verify-cloud-database.sh" \
  >/dev/null; then
  printf '%s\n' 'unsupported MLE compilation parameter leaked into production' >&2
  exit 1
fi

printf '%s\n' \
  'PASS PMLE-HIDDEN-JIT-SOURCE diagnostic-only, cleanup-fenced, compiled-kernel threshold'
