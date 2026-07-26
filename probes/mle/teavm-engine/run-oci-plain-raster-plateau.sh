#!/usr/bin/env bash
set -Eeuo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$project/../../.." && pwd)"
evidence="$root/artifacts/performance/pmle-database-frames"
tag="${PMLE_PLAIN_RASTER_TAG:-plain-mle-raster-default-async-v1-2026-07-26}"
mode="${PMLE_PLAIN_RASTER_MODE:-default}"
pool_log="$evidence/oci-$tag-pool.log"
install_log="$evidence/oci-$tag-install.log"
rank_log="$evidence/oci-$tag-rank.log"
cleanup_log="$evidence/oci-$tag-cleanup.log"

[[ "${PMLE_PLAIN_RASTER_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_PLAIN_RASTER_EXECUTE=YES to run OCI plateau' >&2
  exit 2
}
case "$mode" in
  default) ;;
  forced-sync)
    [[ "${PMLE_HIDDEN_JIT_EXECUTE:-NO}" == YES ]] || {
      printf '%s\n' \
        'forced-sync requires PMLE_HIDDEN_JIT_EXECUTE=YES leak-guard authority' >&2
      exit 2
    }
    ;;
  *) printf 'invalid plain-raster mode: %s\n' "$mode" >&2; exit 2 ;;
esac
[[ "$tag" =~ ^[a-z0-9][a-z0-9-]{2,80}$ ]] || exit 2
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
    SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI raster authority absent: %s\n' "$name" >&2; exit 2; }
done
[[ "$ADB_USERNAME" == DOOM ]]
for input in "$project/plain-raster-kernel.mjs" \
    "$project/install-plain-raster-kernel.sh" \
    "$project/benchmark-oci-plain-raster-plateau.sql" \
    "$project/cleanup-plain-raster-kernel.sql" \
    "$evidence/plain-mle-raster-plateau-predeclaration-2026-07-26.md" \
    "$evidence/plain-mle-raster-compiled-floor-predeclaration-2026-07-26.md"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'OCI plain-raster input unavailable: %s\n' "$input" >&2; exit 2; }
done
for output in "$pool_log" "$install_log" "$rank_log" "$cleanup_log"; do
  [[ ! -e "$output" ]] || {
    printf 'OCI plain-raster evidence exists: %s\n' "$output" >&2; exit 1; }
done
competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[r]un-oci-dvr-compression|[r]un-oci-raw-frame|[r]un-oci-presentation|[r]un-oci-mle-rank/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'OCI plain-raster cell refuses competing OCI work:\n%s\n' \
    "$competing" >&2; exit 1; }

pool_parked=0
diagnostic_loaded=0
finish() {
  local status=$? safe=1
  trap - EXIT HUP INT TERM
  if [[ "$diagnostic_loaded" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" \
        "$project/cleanup-plain-raster-kernel.sql" >"$cleanup_log"; then
      safe=0
    fi
  else
    : >"$cleanup_log"
  fi
  if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_objects number;l_sha varchar2(64);
begin
  select count(*) into l_objects from user_objects
    where object_name like 'DOOM_PLAIN_RASTER%';
  select lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256))) into l_sha
    from doom_teavm_sim_source;
  if l_objects<>0 or
      l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' then
    raise_application_error(-20796,'plain-raster postflight failed');
  end if;
  dbms_output.put_line(
    'PMLE_PLAIN_RASTER_POSTFLIGHT|PASS|diagnostic_objects=0|production_sha256='||
    l_sha);
end;
/
SQL
  then safe=0; fi
  if [[ "$pool_parked" == 1 && "$safe" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >>"$cleanup_log" <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
    then safe=0; fi
  fi
  if [[ "$safe" != 1 ]]; then
    printf '%s\n' \
      'PMLE_PLAIN_RASTER_CAPACITY|HELD_CLOSED|reason=cleanup_unproven' >&2
    status=1
  fi
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
    raise_application_error(-20796,'plain-raster cell requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI plain MLE raster plateau',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_PLAIN_RASTER_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
SQL
pool_parked=1
grep -Fqx \
  'PMLE_PLAIN_RASTER_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0' \
  "$pool_log"

diagnostic_loaded=1
"$project/install-plain-raster-kernel.sh" --emit-sql |
  "$root/scripts/adb-doom-sql.sh" - | tee "$install_log"
grep -Eq '^PMLE_PLAIN_RASTER_STAGING\|PASS\|' "$install_log"

{
  printf '%s\n' \
    "begin dbms_session.set_identifier('OCI_PLAIN_RASTER_PLATEAU');dbms_application_info.set_module('PMLE_HIDDEN_JIT','plain_raster_${mode//-/_}');end;" /
  if [[ "$mode" == forced-sync ]]; then
    printf '%s\n' \
      'alter session set "_mle_compile_immediately"=true;' \
      'alter session set "_mle_compilation_sync"=true;' \
      'alter session set "_mle_compilation_errors_are_fatal"=true;'
  fi
  printf "select 'PMLE_PLAIN_RASTER_SETTINGS|mode=%s|hidden_params=%s|classification=DIAGNOSTIC_NOT_GATE' from dual;\n" \
    "$mode" "$([[ "$mode" == forced-sync ]] && printf YES || printf NO)"
  cat "$project/benchmark-oci-plain-raster-plateau.sql"
} | timeout --signal=TERM 180 "$root/scripts/adb-doom-sql.sh" - | tee "$rank_log"
[[ "$(grep -c '^PMLE_PLAIN_RASTER_PASS|' "$rank_log" || true)" == 6 ]]
grep -Eq \
  '^PMLE_PLAIN_RASTER_VERDICT\|(COMPILED_RASTER_SHAPE_PROMISING|COMPILED_RASTER_SHAPE_AMBIGUOUS|COMPILED_RASTER_SHAPE_INSUFFICIENT)\|' \
  "$rank_log"
if [[ "$mode" == forced-sync ]]; then
  final_worst="$(awk -F'[=|]' '
    /^PMLE_PLAIN_RASTER_PASS[|]/ {
      pass=0;value=0
      for(i=1;i<=NF;i++){
        if($i=="pass")pass=$(i+1)+0
        if($i=="p95_ms")value=$(i+1)+0
      }
      if((pass==5 || pass==6) && value>max)max=value
    }
    END{if(max<=0)exit 1;printf "%.3f",max}
  ' "$rank_log")"
  floor_verdict="$(awk -v value="$final_worst" 'BEGIN{
    if(value<=8)print "COMPILED_FLOOR_PLAUSIBLE";
    else if(value>=20)print "COMPILED_FLOOR_CLOSES_LIVE_RENDERING";
    else print "COMPILED_FLOOR_AMBIGUOUS";
  }')"
  printf 'PMLE_PLAIN_RASTER_FLOOR_VERDICT|%s|final_two_worst_p95_ms=%s|pixels=64000|byte_touches_per_pixel=3|hidden_params=SYNC_FATAL|classification=DIAGNOSTIC_NOT_GATE\n' \
    "$floor_verdict" "$final_worst" | tee -a "$rank_log"
fi
printf 'PASS PMLE-OCI-PLAIN-RASTER-PLATEAU source_sha256=%s rank_log=%s\n' \
  "$(shasum -a 256 "$project/plain-raster-kernel.mjs" | awk '{print $1}')" \
  "${rank_log#"$root"/}"
