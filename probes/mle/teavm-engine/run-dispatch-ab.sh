#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
phase="${1:-}"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23}"
ledger_lock="${TMPDIR:-/tmp}/doomdb-pmle-ledger-$(id -u).lock"
case "$phase" in baseline|candidate) ;;
  *) printf 'usage: %s baseline|candidate\n' "$0" >&2;exit 2;;
esac
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }
if [[ -d "$ledger_lock" ]] ||
    pgrep -f '[b]uild-ledger-differential.mjs' >/dev/null; then
  printf 'exhaustive ledger differential is still active; A/B is fenced\n' >&2
  exit 1
fi
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'dispatch A/B requires a quiet host; active work:\n%s\n' "$busy_host" >&2
  exit 1
fi

evidence="$root/artifacts/performance/pmle-dispatch-ab"
mkdir -p "$evidence"
log="$evidence/${phase}-${tag}.log"
[[ ! -e "$log" ]] || { printf 'A/B evidence already exists: %s\n' "$log" >&2;exit 1; }

if [[ "$phase" == candidate ]]; then
  load_log="$evidence/candidate-load-${tag}.log"
  [[ ! -e "$load_log" ]] || { printf 'A/B load evidence already exists: %s\n' "$load_log" >&2;exit 1; }
  "$project/load-mle-module.sh" --no-build | tee "$load_log"
fi
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
  "$root/scripts/db_sql.sh" "$project/artifact-metadata.sql"
  "$root/scripts/db_sql.sh" "$project/benchmark-multiplayer-mle.sql"
} | tee "$log"
grep -q '^PMLE_HOST_QUIESCENCE|PASS|' "$log"
grep -q '^PMLE_ENVIRONMENT|' "$log"
grep -q '^PMLE_ARTIFACT|' "$log"
grep -q '^PMLE_TEAVM_MULTI_TICKER|' "$log"
printf 'PASS PMLE-DISPATCH-AB-PHASE phase=%s evidence=%s\n' "$phase" "${log#$root/}"
