#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
mode="${1:-}"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23}"
case "$mode" in canonical|coop|membership) ;;
  *) printf 'usage: %s canonical|coop|membership\n' "$0" >&2;exit 2;;
esac
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'MLE differential requires a quiet host; active work:\n%s\n' "$busy_host" >&2
  exit 1
fi

evidence="$root/artifacts/performance/pmle-differentials"
mkdir -p "$evidence"
log="$evidence/${mode}-${tag}.log"
[[ ! -e "$log" ]] || { printf 'differential evidence already exists: %s\n' "$log" >&2;exit 1; }

run_sql() {
  case "$mode" in
    canonical)
      {
        sed '/^whenever /d' "$project/environment-metadata.sql"
        sed '/^whenever /d' "$project/artifact-metadata.sql"
        sed '/^whenever /d' "$project/multiplayer-mle.sql"
      } | "$root/scripts/db_sql.sh" -
      ;;
    coop)
      node "$project/build-coop-differential.mjs" --deep-every=1 |
        "$root/scripts/db_sql.sh" -
      ;;
    membership)
      {
        sed '/^whenever /d' "$project/environment-metadata.sql"
        sed '/^whenever /d' "$project/artifact-metadata.sql"
        sed '/^whenever /d' "$project/membership-recovery-differential.sql"
      } | "$root/scripts/db_sql.sh" -
      ;;
  esac
}

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  run_sql
} | tee "$log"
grep -q '^PMLE_HOST_QUIESCENCE|PASS|' "$log"
grep -q '^PMLE_ENVIRONMENT|' "$log"
grep -q '^PMLE_ARTIFACT|' "$log"
case "$mode" in
  canonical) marker='^PMLE_TEAVM_MULTIPLAYER|PASS|' ;;
  coop) marker='^PMLE_TEAVM_COOP_DIFFERENTIAL|PASS|' ;;
  membership) marker='^PMLE_TEAVM_MEMBERSHIP_RECOVERY_DIFFERENTIAL|PASS|' ;;
esac
grep -q "$marker" "$log"
printf 'PASS PMLE-DIFFERENTIAL mode=%s evidence=%s\n' "$mode" "${log#$root/}"
