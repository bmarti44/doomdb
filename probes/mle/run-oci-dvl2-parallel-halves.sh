#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
evidence="$root/artifacts/performance/pmle-free-live-frames"
tag="${PMLE_DVL2_PARALLEL_TAG:-dvl2-parallel-halves-v1-2026-07-27}"
pool_log="$evidence/oci-$tag-pool.log"
authority_log="$evidence/oci-$tag-authority-install.log"
renderer_log="$evidence/oci-$tag-renderer-install.log"
coordinator_log="$evidence/oci-$tag-coordinator-install.log"
left_log="$evidence/oci-$tag-left.log"
right_log="$evidence/oci-$tag-right.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"

[[ "${PMLE_DVL2_PARALLEL_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_DVL2_PARALLEL_EXECUTE=YES to run OCI cell' >&2
  exit 2
}
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI authority is absent: %s\n' "$name" >&2;exit 2; }
done
for log in "$pool_log" "$authority_log" "$renderer_log" "$coordinator_log" \
  "$left_log" "$right_log" "$cleanup_log"; do
  [[ ! -e "$log" ]] || { printf 'evidence exists: %s\n' "$log" >&2;exit 1; }
done

pool_parked=0
diagnostics_loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostics_loaded" == 1 ]]; then
    {
      cat "$probe/cleanup-dvl2-render-coordinator.sql"
      cat "$probe/cleanup-plain-live-renderer.sql"
      "$probe/cleanup-dvl2-authority-diagnostic.sh" --emit-sql
    } | "$root/scripts/adb-doom-sql.sh" - >"$cleanup_log" || safe=0
  else
    : >"$cleanup_log"
  fi
  "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL' || safe=0
set serveroutput on size unlimited heading off feedback off pages 0
declare l_objects number;l_sha varchar2(64);begin
  select count(*) into l_objects from user_objects
   where object_name like 'DOOM_DVL2_%'
      or object_name like 'DOOM_PLAIN_%';
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_sha
    from doom_teavm_sim_source;
  if l_objects<>0 or
     l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
  then raise_application_error(-20796,'parallel postflight mismatch');end if;
  dbms_output.put_line(
    'PMLE_OCI_DVL2_PARALLEL_POSTFLIGHT|PASS|diagnostic_objects=0'||
    '|production_authority=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3');
end;
/
SQL
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL' || safe=0
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  [[ "$safe" == 1 ]] || status=1
  exit "$status"
}
trap finish EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - >"$pool_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pages 0
declare l_active number;l_live number;begin
  select count(*) into l_active from doom_match
   where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  if l_active<>0 then
    raise_application_error(-20796,'parallel cell requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI parallel renderer diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
   where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_OCI_DVL2_PARALLEL_POOL|PASS|active_matches=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fq 'PMLE_OCI_DVL2_PARALLEL_POOL|PASS|' "$pool_log"
diagnostics_loaded=1
"$probe/install-dvl2-authority-diagnostic.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - >"$authority_log"
"$probe/install-plain-live-renderer.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - >"$renderer_log"
PMLE_DVL2_PLAIN_RENDERER=YES \
  "$probe/install-dvl2-render-coordinator.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - >"$coordinator_log"
grep -Fq 'PMLE_TEAVM_STAGING_GATE|PASS|' "$authority_log"
grep -Fq 'PMLE_PLAIN_RENDERER_STAGING|PASS|' "$renderer_log"
grep -Fq 'PMLE_DVL2_COORDINATOR_STAGING|PASS|' "$coordinator_log"

run_half() {
  local half="$1" log="$2"
  {
    printf "begin dbms_session.set_identifier('%s');end;\n/\n" "$half"
    cat "$probe/benchmark-oci-dvl2-parallel-half.sql"
  } | "$root/scripts/adb-doom-sql.sh" - >"$log"
}
run_half LEFT "$left_log" &
left_pid=$!
run_half RIGHT "$right_log" &
right_pid=$!
left_status=0;right_status=0
wait "$left_pid" || left_status=$?
wait "$right_pid" || right_status=$?
[[ "$left_status" == 0 && "$right_status" == 0 ]]
grep -Eq '^PMLE_OCI_DVL2_PARALLEL_HALF\|PASS\|half=LEFT\|.*\|gate=(PASS|FAIL)$' \
  "$left_log"
grep -Eq '^PMLE_OCI_DVL2_PARALLEL_HALF\|PASS\|half=RIGHT\|.*\|gate=(PASS|FAIL)$' \
  "$right_log"
cat "$left_log" "$right_log"
printf 'PASS PMLE-OCI-DVL2-PARALLEL-HALVES left=%s right=%s\n' \
  "$left_log" "$right_log"
