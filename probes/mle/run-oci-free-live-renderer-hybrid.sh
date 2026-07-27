#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
evidence="$root/artifacts/performance/pmle-free-live-frames"
tag="${PMLE_FREE_LIVE_HYBRID_TAG:-hybrid-command-tape-v1-2026-07-26}"
build_log="$evidence/oci-$tag-build.log"
pool_log="$evidence/oci-$tag-pool.log"
install_log="$evidence/oci-$tag-install.log"
rank_log="$evidence/oci-$tag-rank.log"
verdict_log="$evidence/oci-$tag-verdict.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"

[[ "${PMLE_FREE_LIVE_EXECUTE:-NO}" == YES ]] || {
  printf 'PMLE_FREE_LIVE_EXECUTE=YES is required\n' >&2;exit 2; }
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'missing hybrid renderer setting: %s\n' "$name" >&2;exit 2; }
done
[[ "$ADB_USERNAME" == DOOM ]] || exit 2
for output in "$build_log" "$pool_log" "$install_log" "$rank_log" \
  "$verdict_log" "$cleanup_log"; do
  [[ ! -e "$output" ]] || {
    printf 'hybrid renderer evidence exists: %s\n' "$output" >&2;exit 1; }
done
competing="$(ps ax -o command= | awk '
  /[r]un-wan-matrix|[r]un-oci-dvr|[r]un-oci-free-live-renderer[.]sh|[r]un-oci-free-live-renderer-teavm[.]sh/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'hybrid renderer refuses competing OCI work:\n%s\n' \
    "$competing" >&2;exit 1; }

"$probe/build-free-live-renderer-teavm.sh" | tee "$build_log"
grep -Fq 'PMLE_FREE_LIVE_TEAVM_BUILD|PASS|' "$build_log"
node --check "$probe/free-live-renderer-hybrid.mjs"

pool_parked=0
loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$loaded" == 1 ]]; then
    "$root/scripts/adb-doom-sql.sh" \
      "$probe/cleanup-free-live-renderer-hybrid.sql" >"$cleanup_log" || safe=0
  else
    : >"$cleanup_log"
  fi
  if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_objects number;l_sha varchar2(64);
begin
  select count(*) into l_objects from user_objects
   where object_name like 'DOOM_FREE_HYBRID%'
      or object_name like 'DOOM_FREE_GEN%'
      or object_name in(
        'DOOM_FREE_HYBRID_RENDERER','DOOM_FREE_GENERATED_RENDERER');
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_sha
    from doom_teavm_sim_source;
  if l_objects<>0 or
     l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
  then raise_application_error(-20796,'hybrid renderer postflight');end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_HYBRID_POSTFLIGHT|PASS|diagnostic_objects=0');
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
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_active number;l_assigned number;l_live number;
begin
  select count(*) into l_active from doom_match
   where match_state in('LOBBY','STARTING','ACTIVE','RECOVERING');
  select count(*) into l_assigned from doom_mle_warm_slot
   where assigned_match is not null;
  if l_active<>0 or l_assigned<>0 then
    raise_application_error(-20796,'hybrid renderer requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI hybrid renderer diagnostic',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
   where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_HYBRID_POOL|PASS|active_matches=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fq 'PMLE_FREE_LIVE_HYBRID_POOL|PASS|' "$pool_log"

loaded=1
"$probe/install-free-live-renderer-hybrid.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - | tee "$install_log"
grep -Fq 'PMLE_FREE_LIVE_HYBRID_STAGING|PASS|' "$install_log"
"$root/scripts/adb-doom-sql.sh" \
  "$probe/benchmark-oci-free-live-renderer-hybrid.sql" | tee "$rank_log"
[[ "$(grep -c '^PMLE_FREE_LIVE_HYBRID_EQUIVALENCE|PASS|' "$rank_log")" == 5 ]]
[[ "$(grep -c '^PMLE_FREE_LIVE_HYBRID_PASS|PASS|' "$rank_log")" == 12 ]]
final_p95="$(awk -F'[=|]' '
  $1=="PMLE_FREE_LIVE_HYBRID_PASS" && $2=="PASS" {
    pass=0;p95=0
    for(i=1;i<=NF;i++){if($i=="pass")pass=$(i+1);if($i=="p95_ms")p95=$(i+1)}
    if((pass==11||pass==12)&&p95>max)max=p95
  }END{if(max<=0)exit 1;printf "%.3f",max}' "$rank_log")"
verdict="$(awk -v p95="$final_p95" 'BEGIN{
  if(p95<=11.330)print "PROMOTE_HYBRID_WALL_PIPELINE";
  else if(p95>=20)print "REJECT_HYBRID_WALL_PIPELINE";
  else print "MEASURE_HYBRID_FULL_ROUTE";
}')"
printf 'PMLE_FREE_LIVE_HYBRID_VERDICT|%s|final_two_worst_p95_ms=%s|kernel=GENERATED_COMMAND_TAPE_NATIVE_TYPEDARRAY_RASTER|classification=DIAGNOSTIC_NOT_GATE\n' \
  "$verdict" "$final_p95" | tee "$verdict_log"
