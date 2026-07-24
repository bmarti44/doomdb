#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
phase="${1:-}"
tic_limit="${2:-5250}"
candidate="${DOOMDB_DECPS_CANDIDATE:-$project/target/javascript/doom-mle-simulation-engine-headless.js}"
candidate_sha="2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
evidence="$root/artifacts/performance/pmle-decps-rank"
log="$evidence/${phase}-${candidate_sha:0:12}-${tic_limit}.log"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-alert.XXXXXX")"
pool_parked=0
candidate_loaded=0

case "$phase" in
  interpreter|hidden-jit|hidden-jit-hot) ;;
  *) printf 'usage: %s interpreter|hidden-jit|hidden-jit-hot [TIC_LIMIT]\n' \
      "$0" >&2; exit 2 ;;
esac
[[ "$tic_limit" =~ ^[1-9][0-9]{1,5}$ && "$tic_limit" -le 5250 ]] || {
  printf 'tic limit must be between 10 and 5250\n' >&2
  exit 2
}
[[ -s "$candidate" ]] || { printf 'candidate missing: %s\n' "$candidate" >&2; exit 1; }
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] || {
  printf 'de-CPS candidate SHA mismatch\n' >&2
  exit 1
}
[[ ! -e "$log" ]] || { printf 'evidence exists: %s\n' "$log" >&2; exit 1; }
if [[ "$phase" == hidden-jit || "$phase" == hidden-jit-hot ]]; then
  [[ "${PMLE_HIDDEN_JIT_EXECUTE:-NO}" == YES ]] || {
    printf 'set PMLE_HIDDEN_JIT_EXECUTE=YES for unsupported diagnostic parameters\n' >&2
    exit 2
  }
fi

cleanup_tagged_session() {
  local rows incarnation
  rows="$(docker compose -f "$root/compose.yaml" exec -T db \
    sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
alter session set container=FREEPDB1;
select sid||','||serial# from v$session
where module='PMLE_DECPS_RANK';
exit
SQL
)"
  while IFS= read -r incarnation; do
    incarnation="${incarnation//[[:space:]]/}"
    [[ "$incarnation" =~ ^[0-9]+,[0-9]+$ ]] || continue
    docker compose -f "$root/compose.yaml" exec -T db \
      sqlplus -s / as sysdba >/dev/null <<SQL
alter session set container=FREEPDB1;
alter system kill session '$incarnation' immediate;
exit
SQL
  done <<<"$rows"
}

restore_environment() {
  local status=$?
  trap - EXIT
  cleanup_tagged_session || status=1
  if [[ "$candidate_loaded" == 1 ]]; then
    "$project/load-mle-module.sh" --production >/dev/null || status=1
  fi
  if [[ "$pool_parked" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  fi
  "$root/scripts/oracle-alert-window.sh" end "$alert_state" DECPS_RANK ||
    status=1
  rm -f "$alert_state"
  exit "$status"
}
trap restore_environment EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" DECPS_RANK

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'de-CPS rank requires a quiet host:\n%s\n' "$busy_host" >&2
  exit 1
}
active_output="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state='ACTIVE' and expires_at>(localtimestamp at time zone 'UTC');
SQL
)"
active="$(awk -F= '/^ACTIVE_MATCHES=/{print $2}' <<<"$active_output")"
[[ "$active" == 0 ]] || {
  printf 'de-CPS rank refuses %s active match(es)\n' "$active" >&2
  exit 1
}

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
      slot_.job_name,true,'de-CPS rank host quiescence',
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
mkdir -p "$evidence"
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_DECPS_ARTIFACT|sha256=%s|bytes=%s|phase=%s\n' \
    "$candidate_sha" "$(wc -c <"$candidate" | tr -d '[:space:]')" "$phase"
  "$root/scripts/db_sql.sh" "$project/environment-metadata.sql"
  {
    printf '%s\n' \
      'whenever oserror exit failure rollback' \
      'whenever sqlerror exit sql.sqlcode rollback' \
      'set define off echo off verify off feedback off' \
      'alter session set container=FREEPDB1;' \
      "begin dbms_application_info.set_module('PMLE_DECPS_RANK','$phase');end;" \
      '/'
    if [[ "$phase" == hidden-jit ]]; then
      printf '%s\n' \
        'alter session set "_mle_compile_immediately"=true;' \
        'alter session set "_mle_compilation_sync"=true;' \
        'alter session set "_mle_compilation_errors_are_fatal"=true;'
    elif [[ "$phase" == hidden-jit-hot ]]; then
      printf '%s\n' \
        'alter session set "_mle_compilation_sync"=true;' \
        'alter session set "_mle_compilation_errors_are_fatal"=true;'
    fi
    sed -e 's/__STREAM_NAME__/live-dm-2026-07-23/g' \
      -e 's/__DEATHMATCH__/1/g' \
      -e "s/__TIC_LIMIT__/$tic_limit/g" \
      "$project/replay-command-stream-mle.sql"
    printf '%s\n' 'exit success rollback'
  } | timeout --signal=TERM 1800 "$root/scripts/db_sql.sh" -
} | tee "$log"

grep -q "^PMLE_LIVE_REPLAY_TICKER|stream=live-dm-2026-07-23|tics=$tic_limit|" \
  "$log"
printf 'PASS PMLE-DECPS-RANK phase=%s tics=%s evidence=%s\n' \
  "$phase" "$tic_limit" "${log#$root/}"
