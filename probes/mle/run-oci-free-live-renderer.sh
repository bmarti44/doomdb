#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
evidence="$root/artifacts/performance/pmle-free-live-frames"
tag="${PMLE_FREE_LIVE_TAG:-blockmap-flat-160x100-v1-2026-07-26}"
pool_log="$evidence/oci-$tag-pool.log"
install_log="$evidence/oci-$tag-install.log"
rank_log="$evidence/oci-$tag-rank.log"
verdict_log="$evidence/oci-$tag-verdict.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"

[[ "${PMLE_FREE_LIVE_EXECUTE:-NO}" == YES ]] || {
  printf 'set PMLE_FREE_LIVE_EXECUTE=YES to run the Always Free cell\n' >&2
  exit 2
}
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required Always Free SQL authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || exit 2
for input in "$probe/free-live-renderer.mjs" \
  "$probe/target/free-live-renderer/free-live-render.pack" \
  "$probe/install-free-live-renderer.sh" \
  "$probe/benchmark-oci-free-live-renderer.sql" \
  "$probe/cleanup-free-live-renderer.sql" \
  "$evidence/PREDECLARATION.md"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'Always Free live-render input missing: %s\n' "$input" >&2;exit 2; }
done
for output in "$pool_log" "$install_log" "$rank_log" "$verdict_log" \
  "$cleanup_log"; do
  [[ ! -e "$output" ]] || {
    printf 'Always Free live-render evidence exists: %s\n' "$output" >&2
    exit 1
  }
done
competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[r]un-oci-dvr|[r]un-oci-raw-frame|[r]un-oci-presentation/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'Always Free live-render cell refuses competing OCI work:\n%s\n' \
    "$competing" >&2;exit 1; }

pool_parked=0
diagnostic_loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostic_loaded" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" \
      "$probe/cleanup-free-live-renderer.sql" >"$cleanup_log"; then safe=0;fi
  else
    : >"$cleanup_log"
  fi
  if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_objects number;l_sha varchar2(64);
begin
  select count(*) into l_objects from user_objects
   where object_name like 'DOOM_FREE_LIVE%';
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_sha
    from doom_teavm_sim_source;
  if l_objects<>0 or
     l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
  then raise_application_error(-20796,'free live postflight failed');end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_POSTFLIGHT|PASS|diagnostic_objects=0|production_sha256='||
    l_sha);
end;
/
SQL
  then safe=0;fi
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then safe=0;fi
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
    raise_application_error(-20796,'free live cell requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI Always Free specialized live renderer',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
   where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fq 'PMLE_FREE_LIVE_POOL|PASS' "$pool_log"

diagnostic_loaded=1
"$probe/install-free-live-renderer.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - | tee "$install_log"
grep -Fq 'PMLE_FREE_LIVE_PACK_LOAD|PASS' "$install_log"
"$root/scripts/adb-doom-sql.sh" \
  "$probe/benchmark-oci-free-live-renderer.sql" | tee "$rank_log"
[[ "$(grep -c '^PMLE_FREE_LIVE_PASS|PASS|' "$rank_log")" == 6 ]]
final_p95="$(awk -F'[=|]' '
  /^PMLE_FREE_LIVE_PASS[|]PASS[|]/ {
    pass=0;p95=0
    for(i=1;i<=NF;i++){if($i=="pass")pass=$(i+1);if($i=="p95_ms")p95=$(i+1)}
    if((pass==5||pass==6)&&p95>max)max=p95
  }END{if(max<=0)exit 1;printf "%.3f",max}' "$rank_log")"
verdict="$(awk -v p95="$final_p95" 'BEGIN{
  if(p95<=8)print "PROMOTE_BLOCKMAP_LAYOUT";
  else if(p95>=15)print "REJECT_BLOCKMAP_LAYOUT";
  else print "PROFILE_ONE_OPTIMIZATION";
}')"
printf 'PMLE_FREE_LIVE_VERDICT|%s|final_two_worst_p95_ms=%s|width=160|height=100|input=ACCEPTED_5250_POSES|classification=DIAGNOSTIC_NOT_GATE\n' \
  "$verdict" "$final_p95" | tee "$verdict_log"
