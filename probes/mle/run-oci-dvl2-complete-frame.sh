#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
evidence="$root/artifacts/performance/pmle-free-live-frames"
tag="${PMLE_DVL2_COMPLETE_TAG:-dvl2-complete-frame-v1-2026-07-27}"
fused="${PMLE_DVL2_FUSED:-NO}"
plain="${PMLE_DVL2_PLAIN_RENDERER:-NO}"
world="${PMLE_DVL2_WORLD_RENDERER:-NO}"
unified="${PMLE_DVL2_UNIFIED_RENDERER:-NO}"
command_floor="${PMLE_DVL2_COMMAND_FLOOR:-NO}"
batch_publish="${PMLE_DVL2_BATCH_PUBLISH:-NO}"
batch_refine="${PMLE_DVL2_BATCH_REFINE:-NO}"
batch_production="${PMLE_DVL2_BATCH_PRODUCTION:-NO}"
authority_log="$evidence/oci-$tag-authority-install.log"
renderer_log="$evidence/oci-$tag-renderer-install.log"
pool_log="$evidence/oci-$tag-pool.log"
rank_log="$evidence/oci-$tag-rank.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"
coordinator_log="$evidence/oci-$tag-coordinator-install.log"

[[ "${PMLE_DVL2_COMPLETE_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_DVL2_COMPLETE_EXECUTE=YES to run OCI cell' >&2
  exit 2
}
[[ "$fused" == YES || "$fused" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_FUSED must be YES or NO' >&2
  exit 2
}
[[ "$plain" == YES || "$plain" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_PLAIN_RENDERER must be YES or NO' >&2;exit 2; }
[[ "$plain" == NO || "$fused" == YES ]] || {
  printf '%s\n' 'plain DVL2 renderer requires fused mode' >&2;exit 2; }
[[ "$world" == YES || "$world" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_WORLD_RENDERER must be YES or NO' >&2;exit 2; }
[[ "$unified" == YES || "$unified" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_UNIFIED_RENDERER must be YES or NO' >&2;exit 2; }
[[ "$unified" != YES || "$world" == YES ]] || {
  printf '%s\n' 'unified renderer requires world mode' >&2;exit 2; }
[[ "$world" != YES || "$plain" != YES ]] || {
  printf '%s\n' 'world and plain renderer modes are mutually exclusive' >&2;exit 2; }
[[ "$world" != YES || "$fused" == YES ]] || {
  printf '%s\n' 'slim world renderer requires fused mode' >&2;exit 2; }
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf '%s\n' 'complete-frame cell requires the DOOM schema' >&2
  exit 2
}
[[ "$command_floor" == YES || "$command_floor" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_COMMAND_FLOOR must be YES or NO' >&2;exit 2; }
[[ "$batch_publish" == YES || "$batch_publish" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_BATCH_PUBLISH must be YES or NO' >&2;exit 2; }
[[ "$batch_refine" == YES || "$batch_refine" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_BATCH_REFINE must be YES or NO' >&2;exit 2; }
[[ "$batch_production" == YES || "$batch_production" == NO ]] || {
  printf '%s\n' 'PMLE_DVL2_BATCH_PRODUCTION must be YES or NO' >&2;exit 2; }
[[ "$command_floor" == NO || "$plain" == YES ]] || {
  printf '%s\n' 'command floor requires plain renderer' >&2;exit 2; }
[[ "$batch_publish" == NO || "$unified" == YES ]] || {
  printf '%s\n' 'batch publication requires unified renderer mode' >&2;exit 2; }
[[ "$batch_refine" == NO || "$batch_publish" == YES ]] || {
  printf '%s\n' 'batch refinement requires batch publication mode' >&2;exit 2; }
[[ "$batch_production" == NO || "$batch_publish" == YES ]] || {
  printf '%s\n' 'production batch rank requires batch publication mode' >&2;exit 2; }
[[ "$batch_refine" == NO || "$batch_production" == NO ]] || {
  printf '%s\n' 'batch refinement and production rank are mutually exclusive' >&2
  exit 2
}
for output in "$authority_log" "$renderer_log" "$pool_log" "$rank_log" \
  "$cleanup_log" "$coordinator_log"; do
  [[ ! -e "$output" ]] || {
    printf 'complete-frame evidence exists: %s\n' "$output" >&2
    exit 1
  }
done
competing="$(ps ax -o command= | awk '
  /[r]un-wan-matrix|[r]un-oci-dvr|[r]un-oci-.*rank|[r]un-oci-free-live/ {
    print
  }
')"
[[ -z "$competing" ]] || {
  printf 'complete-frame cell refuses competing OCI work:\n%s\n' \
    "$competing" >&2
  exit 1
}

pool_parked=0
diagnostics_loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostics_loaded" == 1 ]]; then
    {
      cat "$probe/cleanup-dvl2-render-coordinator.sql"
      if [[ "$plain" == YES ]]; then
        cat "$probe/cleanup-plain-live-renderer.sql"
      else
        cat "$probe/cleanup-free-live-renderer-teavm.sql"
      fi
      "$probe/cleanup-dvl2-authority-diagnostic.sh" --emit-sql
    } | "$root/scripts/adb-doom-sql.sh" - >"$cleanup_log" || safe=0
  else
    : >"$cleanup_log"
  fi
  if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pages 0
declare l_objects number;l_sha varchar2(64);
begin
  select count(*) into l_objects from user_objects
   where object_name like 'DOOM_DVL2_%'
      or object_name like 'DOOM_FREE_GEN%'
      or object_name='DOOM_FREE_GENERATED_RENDERER'
      or object_name like 'DOOM_FREE_COMPOSITOR%'
      or object_name='DOOM_FREE_LIVE_COMPOSITOR'
      or object_name like 'DOOM_PLAIN_%';
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_sha
    from doom_teavm_sim_source;
  if l_objects<>0 or
     l_sha<>'c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1'
  then raise_application_error(-20796,'DVL2 postflight mismatch');end if;
  dbms_output.put_line(
    'PMLE_OCI_DVL2_POSTFLIGHT|PASS|diagnostic_objects=0'||
    '|production_authority=c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1');
end;
/
SQL
  then safe=0;fi
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
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
   where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
   where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'DVL2 cell requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI DVL2 complete-frame diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
   where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_OCI_DVL2_POOL|PASS|active_matches=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fq 'PMLE_OCI_DVL2_POOL|PASS|' "$pool_log"

diagnostics_loaded=1
"$probe/install-dvl2-authority-diagnostic.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - | tee "$authority_log"
grep -Fq 'PMLE_TEAVM_STAGING_GATE|PASS|' "$authority_log"
if [[ "$plain" == YES ]]; then
  "$probe/install-plain-live-renderer.sh" --emit-sql |
    "$root/scripts/adb-doom-sql.sh" - | tee "$renderer_log"
  grep -Fq 'PMLE_PLAIN_RENDERER_STAGING|PASS|' "$renderer_log"
else
  PMLE_FREE_LIVE_WORLD_ARTIFACT="$world" \
    PMLE_FREE_LIVE_UNIFIED_ARTIFACT="$unified" \
    "$probe/install-free-live-renderer-teavm.sh" --emit-sql |
    "$root/scripts/adb-doom-sql.sh" - | tee "$renderer_log"
  grep -Fq 'PMLE_FREE_LIVE_TEAVM_STAGING|PASS|' "$renderer_log"
fi

if [[ "$fused" == YES ]]; then
  PMLE_DVL2_PLAIN_RENDERER="$plain" PMLE_DVL2_WORLD_RENDERER="$world" \
    PMLE_DVL2_UNIFIED_RENDERER="$unified" \
    "$probe/install-dvl2-render-coordinator.sh" --emit-sql |
    "$root/scripts/adb-doom-sql.sh" - | tee "$coordinator_log"
  grep -Fq 'PMLE_DVL2_COORDINATOR_STAGING|PASS|' "$coordinator_log"
  if [[ "$world" == YES ]]; then
    if [[ "$batch_publish" == YES ]]; then
      batch_benchmark="$probe/benchmark-oci-dvl2-batched-publish.sql"
      if [[ "$batch_refine" == YES ]]; then
        batch_benchmark="$probe/benchmark-oci-dvl2-batched-publish-refine.sql"
      elif [[ "$batch_production" == YES ]]; then
        batch_benchmark="$probe/benchmark-oci-dvl2-batched-publish-production.sql"
      fi
      "$root/scripts/adb-doom-sql.sh" \
        "$batch_benchmark" | tee "$rank_log"
      expected_batch_cells=4
      if [[ "$batch_production" == YES ]]; then expected_batch_cells=1;fi
      test "$(grep -Ec \
        '^PMLE_OCI_DVL2_BATCH_PUBLISH\\|PASS\\|.*\\|rate_shape=(PASS|FAIL)$' \
        "$rank_log")" -eq "$expected_batch_cells"
      grep -Fq 'PMLE_OCI_DVL2_BATCH_POSTFLIGHT|PASS|' "$rank_log"
    else
      "$root/scripts/adb-doom-sql.sh" \
        "$probe/benchmark-oci-dvl2-slim-world.sql" | tee "$rank_log"
      grep -Eq '^PMLE_OCI_DVL2_SLIM_WORLD\\|PASS\\|.*\\|gate=(PASS|FAIL)$' \
        "$rank_log"
    fi
  elif [[ "$plain" == YES ]]; then
    if [[ "$command_floor" == YES ]]; then
      "$root/scripts/adb-doom-sql.sh" \
        "$probe/benchmark-oci-dvl2-command-floor.sql" | tee "$rank_log"
      grep -Eq \
        '^PMLE_OCI_DVL2_COMMAND_FLOOR\|PASS\|.*\|verdict=(BUILD_COMMAND_RASTER|REJECT_COMMAND_RASTER|MARGINAL)$' \
        "$rank_log"
    else
      "$root/scripts/adb-doom-sql.sh" \
        "$probe/benchmark-oci-dvl2-fused-geometry.sql" | tee "$rank_log"
      grep -Fq 'PMLE_OCI_DVL2_PLAIN_QUANTIZED_BSP|PASS|' "$rank_log"
      grep -Eq \
        '^PMLE_OCI_DVL2_PLAIN_QUANTIZED_BSP\|PASS\|.*\|gate=(PASS|FAIL)$' \
        "$rank_log"
    fi
  else
    "$root/scripts/adb-doom-sql.sh" \
      "$probe/benchmark-oci-dvl2-fused-frame.sql" | tee "$rank_log"
    grep -Fq 'PMLE_OCI_DVL2_FUSED_FRAME|PASS|' "$rank_log"
    grep -Eq '^PMLE_OCI_DVL2_FUSED_FRAME\|PASS\|.*\|gate=(PASS|FAIL)$' \
      "$rank_log"
  fi
else
  : >"$coordinator_log"
  "$root/scripts/adb-doom-sql.sh" \
    "$probe/benchmark-oci-dvl2-complete-frame.sql" | tee "$rank_log"
  grep -Fq 'PMLE_OCI_DVL2_COMPLETE_FRAME|PASS|' "$rank_log"
  grep -Eq '^PMLE_OCI_DVL2_COMPLETE_FRAME\|PASS\|.*\|gate=(PASS|FAIL)\|' \
    "$rank_log"
fi

printf 'PASS PMLE-OCI-DVL2-COMPLETE-FRAME rank_log=%s\n' "$rank_log"
