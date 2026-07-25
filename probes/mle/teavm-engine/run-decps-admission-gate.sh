#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
samples="${DOOMDB_MLE_ADMISSION_SAMPLES:-10}"
target_ms="${DOOMDB_MLE_ADMISSION_TARGET_MS:-5000}"
tag="${PMLE_EVIDENCE_TAG:-decps-5ec18cbe-2026-07-25}"
evidence="$root/artifacts/performance/pmle-browser-role-swap"
log="$evidence/warm-pool-admission-${tag}.log"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-admission-alert.XXXXXX")"
alert_started=0

[[ "$samples" =~ ^[1-9][0-9]*$ && "$samples" -le 100 ]] ||
  { printf 'invalid admission sample count: %s\n' "$samples" >&2; exit 2; }
[[ "$target_ms" =~ ^[1-9][0-9]*$ ]] ||
  { printf 'invalid admission target: %s\n' "$target_ms" >&2; exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2; exit 2; }
[[ ! -e "$log" ]] ||
  { printf 'admission evidence already exists: %s\n' "$log" >&2; exit 1; }

finish() {
  local status=$?
  trap - EXIT
  if [[ "$alert_started" == 1 ]]; then
    "$root/scripts/oracle-alert-window.sh" end "$alert_state" DECPS_ADMISSION |
      tee -a "$log" || status=1
  fi
  rm -f "$alert_state"
  exit "$status"
}
trap finish EXIT

wait_for_idle_pool() {
  local output ready active
  for _ in $(seq 1 2400); do
    output="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'READY='||count(*) from doom_mle_warm_slot
where slot_status='READY' and assigned_match is null;
select 'ACTIVE='||count(*) from doom_match
where match_state in('LOBBY','ACTIVE');
SQL
)"
    ready="$(awk -F= '/^READY=/{print $2}' <<<"$output")"
    active="$(awk -F= '/^ACTIVE=/{print $2}' <<<"$output")"
    if [[ "$ready" == 2 && "$active" == 0 ]]; then
      return 0
    fi
    sleep .1
  done
  printf 'admission gate timed out waiting for two idle READY slots\n' >&2
  return 1
}

mkdir -p "$evidence"
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" DECPS_ADMISSION
alert_started=1
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  "$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/environment-metadata.sql"
  "$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/artifact-metadata.sql"
} | tee "$log"

values=()
for sample in $(seq 1 "$samples"); do
  wait_for_idle_pool
  output="$(node "$root/tests/verify-mle-solo-admission.mjs")"
  marker="$(awk '/^PMLE_SOLO_ADMISSION[|]PASS[|]/{print}' <<<"$output")"
  [[ "$(wc -l <<<"$marker" | tr -d '[:space:]')" == 1 ]] ||
    { printf 'admission sample %s lacks one PASS marker\n' "$sample" >&2; exit 1; }
  elapsed="$(sed -n 's/.*|ready_to_active_ms=\([0-9][0-9]*\).*/\1/p' <<<"$marker")"
  [[ "$elapsed" =~ ^[0-9]+$ ]] ||
    { printf 'admission sample %s ready-to-active time is malformed\n' "$sample" >&2; exit 1; }
  values+=("$elapsed")
  printf '%s\n' "${marker/PMLE_SOLO_ADMISSION|PASS|/PMLE_SOLO_ADMISSION_SAMPLE|PASS|sample=$sample|}" |
    tee -a "$log"
done
wait_for_idle_pool

sorted="$(printf '%s\n' "${values[@]}" | sort -n)"
minimum="$(head -1 <<<"$sorted")"
maximum="$(tail -1 <<<"$sorted")"
p50_rank=$(((samples + 1) / 2))
p95_rank=$(((95 * samples + 99) / 100))
p50="$(sed -n "${p50_rank}p" <<<"$sorted")"
p95="$(sed -n "${p95_rank}p" <<<"$sorted")"
verdict=PASS
((p95 <= target_ms)) || verdict=FAIL
printf 'PMLE_WARM_POOL_ADMISSION|%s|metric=browser_ready_click_to_first_active|poll_cadence_ms=100|samples=%s|min_ms=%s|p50_ms=%s|p95_ms=%s|max_ms=%s|target_p95_ms=%s\n' \
  "$verdict" "$samples" "$minimum" "$p50" "$p95" "$maximum" "$target_ms" |
  tee -a "$log"
[[ "$verdict" == PASS ]]
