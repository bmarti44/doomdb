#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-dvr-compression"
candidate="$root/artifacts/performance/pmle-presentation-decps/presentation-candidate-118c37717b36.js"
candidate_sha=118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3
codec="$evidence/dvr-codec-candidate-e44884a58a0b.js"
codec_sha=e44884a58a0b1767919b65e141b8a1c3fdec6560b7b90db519fc1008134c4353
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
fixture="$root/tests/fixtures/mle-live-deathmatch-2026-07-23.json"
record_parser="$root/scripts/require-db-record.mjs"

pool_log="$evidence/oci-dvr-pool-park-2026-07-26.log"
stream_log="$evidence/oci-dvr-stream-stage-2026-07-26.log"
engine_log="$evidence/oci-dvr-presentation-load-118c3771-2026-07-26.log"
codec_load_log="$evidence/oci-dvr-codec-load-e44884a5-2026-07-26.log"
bind_log="$evidence/oci-dvr-bind-install-2026-07-26.log"
codec_log="$evidence/oci-dvr-codec-5250-2026-07-26.log"
cleanup_log="$evidence/oci-dvr-production-restore-2026-07-26.log"
summary_log="$evidence/oci-dvr-codec-boundary-verdict-2026-07-26.log"
profiles=(RAW_1 DFR1_1 DFR1_5 DFR1_10 DFR1_35)

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI DVR authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf 'OCI DVR diagnostic requires the DOOM schema\n' >&2; exit 2; }
for input in "$candidate" "$codec" "$tables" "$fixture" \
    "$project/benchmark-oci-dvr-codec.sql" \
    "$project/benchmark-oci-dvr-boundary.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'OCI DVR input is unavailable: %s\n' "$input" >&2; exit 2; }
done
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]]
[[ "$(shasum -a 256 "$codec" | awk '{print $1}')" == "$codec_sha" ]]

outputs=("$pool_log" "$stream_log" "$engine_log" "$codec_load_log" \
  "$bind_log" "$codec_log" "$cleanup_log" "$summary_log")
for profile in "${profiles[@]}"; do
  outputs+=("$evidence/oci-dvr-boundary-${profile,,}-2026-07-26.log")
done
for output in "${outputs[@]}"; do
  [[ ! -e "$output" ]] || {
    printf 'OCI DVR evidence already exists: %s\n' "$output" >&2; exit 1; }
done

node "$record_parser" --self-test
competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[o]ci-command-stream-digest|[r]un-oci-presentation/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'OCI DVR diagnostic refuses a competing OCI cell:\n%s\n' \
    "$competing" >&2; exit 1; }

pool_parked=0
diagnostic_loaded=0
stream_staged=0
restore_production() {
  local status=$? environment_safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostic_loaded" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >"$cleanup_log" <<'SQL'
begin
  for ddl_ in (
    select 'drop procedure doom_dvr_bind_release' text from dual union all
    select 'drop function '||object_name from user_objects
      where object_name like 'DOOM_DVR_BIND_%' and object_type='FUNCTION'
    union all select 'drop mle module doom_mle_dvr_bind' from dual
    union all select 'drop mle env doom_mle_dvr_bind_env' from dual
    union all select 'drop mle module doom_mle_dvr_codec' from dual
    union all select 'drop table doom_dvr_frame_sink purge' from dual
    union all select 'drop table doom_mle_dvr_bind_source purge' from dual
    union all select 'drop table doom_mle_dvr_codec_source purge' from dual
  ) loop
    begin execute immediate ddl_.text;
    exception when others then
      if sqlcode not in(-4043,-4080,-4103,-4104,-4105,-942) then raise;end if;
    end;
  end loop;
end;
/
SQL
    then
      environment_safe=0
    fi
    if ! "$project/load-mle-module.sh" --production --emit-sql |
        "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log"; then
      environment_safe=0
    fi
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
alter package doom_mle_match_runtime compile body;
set serveroutput on size unlimited heading off feedback off pagesize 0
declare
  l_source blob;l_sha varchar2(64);l_status varchar2(7);
begin
  select source_blob into l_source from doom_teavm_sim_source;
  l_sha:=lower(rawtohex(dbms_crypto.hash(
    l_source,dbms_crypto.hash_sh256)));
  select status into l_status from user_objects
    where object_name='DOOM_MLE_MATCH_RUNTIME' and object_type='PACKAGE BODY';
  if l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
      or l_status<>'VALID' then
    raise_application_error(-20796,'DVR rollback verification failed');
  end if;
  dbms_output.put_line(
    'PMLE_OCI_DVR_ROLLBACK|PASS|module_sha256='||l_sha||
    '|runtime_status='||l_status);
end;
/
SQL
    then
      environment_safe=0
    fi
  fi
  if [[ "$stream_staged" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin execute immediate 'drop table doom_mle_perf_vector purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
SQL
    then
      environment_safe=0
    fi
  fi
  if [[ "$pool_parked" == 1 && "$environment_safe" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then
      environment_safe=0
    fi
  fi
  if [[ "$environment_safe" != 1 ]]; then
    status=1
    printf 'PMLE_OCI_DVR_CAPACITY|HELD_CLOSED|reason=diagnostic_or_restore_failed\n' >&2
  fi
  exit "$status"
}
trap restore_production EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$pool_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
    where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
    where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'OCI DVR diagnostic requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI DVR compression diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_OCI_DVR_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
node "$record_parser" "$pool_log" 'PMLE_OCI_DVR_POOL|' \
  'PMLE_OCI_DVR_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0'

stream_staged=1
node "$project/emit-command-stream-sql.mjs" "$fixture" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$stream_log"
node "$record_parser" "$stream_log" 'PMLE_OCI_COMMAND_STREAM|' \
  'PMLE_OCI_COMMAND_STREAM|PASS|stream=live-dm-2026-07-23|tics=5250|bytes=173250|sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085'

diagnostic_loaded=1
"$project/load-mle-module.sh" --emit-sql "--javascript=$candidate" \
  "--table-pack=$tables" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$engine_log"
"$project/load-dvr-codec-module.sh" --emit-sql "--artifact=$codec" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$codec_load_log"
"$project/install-dvr-bind-wrapper.sh" --emit-sql \
  "--engine-sha256=$candidate_sha" "--codec-sha256=$codec_sha" |
  "$root/scripts/adb-doom-sql.sh" - | tee "$bind_log"

{
  printf '%s\n' \
    "begin dbms_session.set_identifier('OCI_DVR_CODEC_5250');end;" '/'
  cat "$project/benchmark-oci-dvr-codec.sql"
} | "$root/scripts/adb-doom-sql.sh" - | tee "$codec_log"
grep -Eq '^PMLE_OCI_DVR_CODEC\|PASS\|.*\|compress_gate=PASS$' "$codec_log"

for profile in "${profiles[@]}"; do
  output="$evidence/oci-dvr-boundary-${profile,,}-2026-07-26.log"
  {
    printf '%s\n' \
      "begin dbms_session.set_identifier('OCI_DVR_BOUNDARY_${profile}');end;" '/'
    cat "$project/benchmark-oci-dvr-boundary.sql"
  } | "$root/scripts/adb-doom-sql.sh" - | tee "$output"
  grep -Eq '^PMLE_OCI_DVR_BOUNDARY\|PASS\|.*\|boundary_gate=PASS$' "$output"
done

{
  grep '^PMLE_OCI_DVR_CODEC|' "$codec_log"
  for profile in "${profiles[@]}"; do
    grep '^PMLE_OCI_DVR_BOUNDARY|' \
      "$evidence/oci-dvr-boundary-${profile,,}-2026-07-26.log"
  done
  printf 'PMLE_OCI_DVR_FIRST_PACKET|PASS|codec_cell=PASS|boundary_cells=5'
  printf '|presentation_sha256=%s|codec_sha256=%s\n' \
    "$candidate_sha" "$codec_sha"
} | tee "$summary_log"
