#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
candidate="${PMLE_CANDIDATE_FILE:-$root/artifacts/performance/pmle-live-frame-authority/authority-candidate-c613bb5106d6.js}"
candidate_sha="${PMLE_EXPECTED_AUTHORITY_SHA256:-c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1}"
tag="${PMLE_EVIDENCE_TAG:-live-frame-c613-final-2026-07-28}"
membership_sql="$(mktemp "${TMPDIR:-/tmp}/doomdb-live-frame-membership.XXXXXX.sql")"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-live-frame-gates-alert.XXXXXX")"
pool_parked=0

[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2; exit 2; }
[[ "$candidate_sha" =~ ^[0-9a-f]{64}$ ]] ||
  { printf 'invalid authority candidate SHA\n' >&2; exit 2; }
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] ||
  { printf 'live-frame authority candidate SHA mismatch\n' >&2; exit 1; }

sed -E "s/(c_mle_sha constant varchar2\\(64\\):=')[0-9a-f]{64}(';)/\\1${candidate_sha}\\2/" \
  "$project/membership-recovery-differential.sql" >"$membership_sql"
[[ "$(grep -Ec "c_mle_sha constant varchar2\\(64\\):='${candidate_sha}';" \
  "$membership_sql")" == 1 ]] ||
  { printf 'membership candidate binding failed\n' >&2; exit 1; }

restore_environment() {
  local status=$?
  trap - EXIT
  if [[ "$pool_parked" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  "$root/scripts/oracle-alert-window.sh" end "$alert_state" \
    LIVE_FRAME_AUTHORITY_DIFFERENTIALS || status=1
  rm -f "$membership_sql" "$alert_state"
  exit "$status"
}
trap restore_environment EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" \
  LIVE_FRAME_AUTHORITY_DIFFERENTIALS

preflight="$("$root/scripts/db_sql.sh" - <<SQL
set serveroutput on size unlimited
set linesize 32767 trimspool on
declare
  l_source blob;l_source_sha varchar2(64);l_live_sha varchar2(64);
  l_active number;
begin
  select source_blob into l_source from doom_teavm_sim_source;
  l_source_sha:=lower(rawtohex(dbms_crypto.hash(
    l_source,dbms_crypto.hash_sh256)));
  select authority_sha256 into l_live_sha
    from doom_mle_live_frame_source where artifact_id=1;
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  if l_source_sha<>'$candidate_sha' or l_live_sha<>l_source_sha
      or l_active<>0 then
    raise_application_error(-20796,'live-frame differential preflight');
  end if;
  dbms_output.put_line(
    'PMLE_LIVE_FRAME_DIFFERENTIAL_PREFLIGHT|PASS|authority_sha256='||
    l_source_sha||'|active_matches='||l_active);
end;
/
SQL
)"
grep -q "^PMLE_LIVE_FRAME_DIFFERENTIAL_PREFLIGHT|PASS|authority_sha256=$candidate_sha|active_matches=0$" \
  <<<"$preflight"

pool_parked=1
"$root/scripts/db_sql.sh" - >/dev/null <<'SQL'
declare
  l_live number;
begin
  for slot_ in (
    select * from doom_mle_warm_slot
    where slot_status in('WARMING','READY') and assigned_match is null
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'live-frame authority differential battery',
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

PMLE_EVIDENCE_TAG="$tag" "$project/run-differential.sh" coop
DOOMDB_MLE_MEMBERSHIP_SQL="$membership_sql" PMLE_EVIDENCE_TAG="$tag" \
  "$project/run-differential.sh" membership

printf 'PMLE_LIVE_FRAME_AUTHORITY_DIFFERENTIALS|PASS|authority_sha256=%s|modes=coop,membership|artifact_mutation=0\n' \
  "$candidate_sha"
