#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tag="${PMLE_EVIDENCE_TAG:-5ec18cbe-2026-07-25}"
evidence="$root/artifacts/performance/pmle-live-tic"
log="$evidence/long-flag-cast-${tag}.log"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-long-flag-alert.XXXXXX")"
pool_parked=0
alert_started=0

[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid long-flag evidence tag: %s\n' "$tag" >&2; exit 2; }
[[ ! -e "$log" ]] ||
  { printf 'long-flag evidence already exists: %s\n' "$log" >&2; exit 1; }
if pgrep -f '[r]un-decps-ledger' >/dev/null; then
  printf 'exhaustive ledger is active; long-flag benchmark deferred\n' >&2
  exit 1
fi

finish() {
  local status=$?
  trap - EXIT
  if [[ "$alert_started" == 1 ]]; then
    "$root/scripts/oracle-alert-window.sh" end "$alert_state" \
      PMLE_LONG_FLAG_CAST | tee -a "$log" || status=1
  fi
  if [[ "$pool_parked" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' ||
begin doom_match_worker.start_warm_pool;end;
/
SQL
      status=1
  fi
  rm -f "$alert_state"
  exit "$status"
}
trap finish EXIT

mkdir -p "$evidence"
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" PMLE_LONG_FLAG_CAST
alert_started=1

"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
declare
  l_live number;
begin
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run
    from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
      and assigned_match is null
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'long-flag cast benchmark quiescence',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'retained warm pool did not park');
  end if;
end;
/
SQL
pool_parked=1

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  node "$root/scripts/verify-db-output-helper.mjs"
  "$root/scripts/db_sql.sh" \
    "$root/probes/mle/teavm-engine/environment-metadata.sql"
  "$root/scripts/db_sql.sh" \
    "$root/probes/mle/teavm-engine/artifact-metadata.sql"
  "$root/scripts/db_sql.sh" \
    "$root/probes/mle/teavm-engine/benchmark-long-flag-cast.sql"
} | tee "$log"
