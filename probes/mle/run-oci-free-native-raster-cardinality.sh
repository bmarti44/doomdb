#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$root/probes/mle"
evidence="$root/artifacts/performance/pmle-free-live-frames"
pool_log="$evidence/oci-native-cardinality-pool-2026-07-26.log"
rank_log="$evidence/oci-native-cardinality-rank-2026-07-26.log"
verdict_log="$evidence/oci-native-cardinality-verdict-2026-07-26.log"
restore_log="$evidence/oci-native-cardinality-restore-2026-07-26.log"

[[ "${PMLE_FREE_NATIVE_EXECUTE:-NO}" == YES ]] || {
  printf 'set PMLE_FREE_NATIVE_EXECUTE=YES to run the Always Free cell\n' >&2
  exit 2
}
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required Always Free SQL authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf 'Always Free native cell requires DOOM schema\n' >&2;exit 2; }
for input in "$probe/benchmark-oci-free-native-raster-cardinality.sql" \
  "$probe/evaluate-free-native-cardinality.mjs" \
  "$evidence/PREDECLARATION.md"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'Always Free native input missing: %s\n' "$input" >&2;exit 2; }
done
for output in "$pool_log" "$rank_log" "$verdict_log" "$restore_log"; do
  [[ ! -e "$output" ]] || {
    printf 'Always Free native evidence already exists: %s\n' "$output" >&2
    exit 1
  }
done
node "$probe/evaluate-free-native-cardinality.mjs" --self-test
competing="$(ps ax -o command= | awk '
  /[v]erify-cloud-browser|[r]un-wan-matrix|[r]un-oci-dvr|[r]un-oci-raw-frame|[r]un-oci-presentation/ {print}
')"
[[ -z "$competing" ]] || {
  printf 'Always Free native cell refuses competing OCI work:\n%s\n' \
    "$competing" >&2;exit 1; }

pool_parked=0
finish() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ "$pool_parked" == 1 ]]; then
    if ! "$root/scripts/adb-doom-sql.sh" - >"$restore_log" <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
begin doom_match_worker.start_warm_pool;end;
/
declare l_source blob;l_sha varchar2(64);
begin
  select source_blob into l_source from doom_teavm_sim_source;
  l_sha:=lower(rawtohex(dbms_crypto.hash(
    l_source,dbms_crypto.hash_sh256)));
  dbms_output.put_line(
    'PMLE_FREE_NATIVE_RESTORE|PASS|production_sha256='||l_sha);
end;
/
SQL
    then status=1;fi
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
    raise_application_error(-20796,'native cardinality requires idle capacity');
  end if;
  for slot_ in (
    select job_name,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING')
  ) loop
    doom_worker_lifecycle.stop_job(
      slot_.job_name,true,'OCI Always Free native raster cardinality',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then raise_application_error(-20796,'pool did not park');end if;
  dbms_output.put_line(
    'PMLE_FREE_NATIVE_POOL|PASS|active_matches=0|assigned_slots=0|live_slots=0');
end;
/
select 'PMLE_FREE_NATIVE_ENV|cpu_count='||
  (select value from v$parameter where name='cpu_count')||
  '|service='||sys_context('USERENV','SERVICE_NAME')
from dual;
SQL
pool_parked=1

"$root/scripts/adb-doom-sql.sh" \
  "$probe/benchmark-oci-free-native-raster-cardinality.sql" >"$rank_log"
node "$probe/evaluate-free-native-cardinality.mjs" \
  "$rank_log" | tee "$verdict_log"
