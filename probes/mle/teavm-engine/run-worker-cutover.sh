#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23}"
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'MLE worker cutover requires a quiet host; active work:\n%s\n' "$busy_host" >&2
  exit 1
fi

evidence="$root/artifacts/performance/pmle-worker-cutover"
mkdir -p "$evidence"
log="$evidence/run-${tag}.log"
[[ ! -e "$log" ]] || { printf 'worker evidence already exists: %s\n' "$log" >&2;exit 1; }

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  {
    sed '/^whenever /d' "$root/probes/mle/teavm-engine/environment-metadata.sql"
    sed '/^whenever /d' "$root/probes/mle/teavm-engine/artifact-metadata.sql"
    sed '/^whenever /d' "$root/tests/verify-mle-match-worker-cutover.sql"
  } | "$root/scripts/db_sql.sh" -
} | tee "$log"

grep -q '^PMLE_HOST_QUIESCENCE|PASS|' "$log"
grep -q '^PMLE_ENVIRONMENT|' "$log"
grep -q '^PMLE_ARTIFACT|' "$log"
grep -q '^PMLE_WORKER_CUTOVER|PASS|' "$log"
printf 'PASS PMLE-WORKER-CUTOVER evidence=%s\n' "${log#$root/}"
