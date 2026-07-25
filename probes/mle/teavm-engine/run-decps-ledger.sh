#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
candidate="${PMLE_CANDIDATE_FILE:-$root/artifacts/performance/pmle-decps-rank/authority-candidate-5ec18cbe4cff.js}"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
candidate_sha="${PMLE_EXPECTED_AUTHORITY_SHA256:-5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3}"
candidate_bytes="${PMLE_EXPECTED_AUTHORITY_BYTES:-1081335}"
tag="${PMLE_EVIDENCE_TAG:-decps-reproducible-5ec18cbe-2026-07-25}"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-ledger-alert.XXXXXX")"
pool_parked=0
candidate_loaded=0

[[ "$(wc -c <"$candidate" | tr -d '[:space:]')" == "$candidate_bytes" ]] ||
  { printf 'de-CPS ledger candidate byte-length mismatch\n' >&2; exit 1; }
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] ||
  { printf 'de-CPS ledger candidate SHA mismatch\n' >&2; exit 1; }

restore_environment() {
  local status=$?
  trap - EXIT
  if [[ "$candidate_loaded" == 1 ]]; then
    "$project/load-mle-module.sh" --production >/dev/null || status=1
  fi
  if [[ "$pool_parked" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  "$root/scripts/oracle-alert-window.sh" end "$alert_state" DECPS_LEDGER ||
    status=1
  rm -f "$alert_state"
  exit "$status"
}
trap restore_environment EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" DECPS_LEDGER

active_output="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state='ACTIVE' and expires_at>(localtimestamp at time zone 'UTC');
SQL
)"
active="$(awk -F= '/^ACTIVE_MATCHES=/{print $2}' <<<"$active_output")"
[[ "$active" == 0 ]] ||
  { printf 'de-CPS ledger refuses %s active match(es)\n' "$active" >&2; exit 1; }

pool_parked=1
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
      slot_.job_name,true,'de-CPS exhaustive ledger',
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

"$project/load-mle-module.sh" \
  "--javascript=$candidate" "--table-pack=$tables" >/dev/null
candidate_loaded=1
PMLE_EXPECTED_AUTHORITY_SHA256="$candidate_sha" \
PMLE_EXPECTED_AUTHORITY_BYTES="$candidate_bytes" \
PMLE_CANDIDATE_FILE="$candidate" PMLE_EVIDENCE_TAG="$tag" \
  "$project/run-ledger-differential.sh"
