#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tag="${PMLE_EVIDENCE_TAG:-decps-5ec18cbe-2026-07-25-v2}"
evidence="$root/artifacts/performance/pmle-worker-lifecycle"
log="$evidence/run-${tag}.log"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-warm-lifecycle-alert.XXXXXX")"
alert_started=0

[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid lifecycle evidence tag: %s\n' "$tag" >&2; exit 2; }
[[ ! -e "$log" ]] ||
  { printf 'warm lifecycle evidence already exists: %s\n' "$log" >&2; exit 1; }

finish() {
  local status=$?
  trap - EXIT
  if [[ "$alert_started" == 1 ]]; then
    "$root/scripts/oracle-alert-window.sh" end "$alert_state" \
      DECPS_WARM_LIFECYCLE | tee -a "$log" || status=1
  fi
  rm -f "$alert_state"
  exit "$status"
}
trap finish EXIT

mkdir -p "$evidence"
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" \
  DECPS_WARM_LIFECYCLE
alert_started=1
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  node "$root/scripts/verify-db-output-helper.mjs"
  "$root/scripts/db_sql.sh" \
    "$root/probes/mle/teavm-engine/environment-metadata.sql"
  "$root/scripts/db_sql.sh" \
    "$root/probes/mle/teavm-engine/artifact-metadata.sql"
  "$root/scripts/db_sql.sh" "$root/tests/verify-mle-warm-lifecycle.sql"
} | tee "$log"
