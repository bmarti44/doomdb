#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
evidence="$root/artifacts/performance/pmle-hidden-jit"
tag="${PMLE_EVIDENCE_TAG:-2026-07-24}"
pool_restore_needed=0
bench_installed=0
alert_state="$(mktemp "${TMPDIR:-/tmp}/doom-mle-hidden-jit-alert.XXXXXX")"

[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'invalid evidence tag: %s\n' "$tag" >&2
  exit 2
}
[[ "${PMLE_HIDDEN_JIT_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' \
    'set PMLE_HIDDEN_JIT_EXECUTE=YES for the unsupported-parameter diagnostic' >&2
  exit 2
}

restore_environment() {
  local status=$?
  trap - EXIT
  if [[ "$bench_installed" == 1 ]]; then
    "$root/scripts/db_sql.sh" "$root/probes/mle/cleanup.sql" >/dev/null ||
      status=1
  fi
  if [[ "$pool_restore_needed" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' ||
begin doom_match_worker.start_warm_pool;end;
/
SQL
      status=1
  fi
  if ! "$root/scripts/oracle-alert-window.sh" end "$alert_state" HIDDEN_JIT; then
    status=1
  fi
  rm -f "$alert_state"
  exit "$status"
}
trap restore_environment EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" HIDDEN_JIT

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'hidden-JIT diagnostic requires a quiet host:\n%s\n' "$busy_host" >&2
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
  printf 'hidden-JIT diagnostic refuses %s active match(es)\n' "$active" >&2
  exit 1
}

pool_restore_needed=1
"$root/scripts/db_sql.sh" - <<'SQL'
set serveroutput on
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
      slot_.job_name,true,'hidden-JIT diagnostic host quiescence',
      slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
      slot_.worker_spid,slot_.worker_job_run);
  end loop;
  select count(*) into l_live from doom_mle_warm_slot
    where slot_status in('WARMING','READY','CLAIMED','RUNNING');
  if l_live<>0 then
    raise_application_error(-20796,'retained warm pool did not park');
  end if;
  dbms_output.put_line('PMLE_HIDDEN_JIT_POOL|PARKED|live_slots='||l_live);
end;
/
SQL

"$root/scripts/db_sql.sh" "$root/probes/mle/install.sql" >/dev/null
bench_installed=1
mkdir -p "$evidence"

cleanup_tagged_sessions() {
  local rows
  rows="$(docker compose -f "$root/compose.yaml" exec -T db \
    sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
alter session set container=FREEPDB1;
select sid||','||serial# from v$session
where module='PMLE_HIDDEN_JIT';
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

  rows="$(docker compose -f "$root/compose.yaml" exec -T db \
    sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
alter session set container=FREEPDB1;
select count(*) from v$session where module='PMLE_HIDDEN_JIT';
exit
SQL
)"
  [[ "$(tr -dc '0-9' <<<"$rows")" == 0 ]] || {
    printf 'tagged hidden-JIT session survived cleanup: %s\n' "$rows" >&2
    return 1
  }
}

run_cell() {
  local label=$1
  local settings=$2
  local log="$evidence/${tag}-${label}.log"
  [[ ! -e "$log" ]] || {
    printf 'evidence exists: %s\n' "$log" >&2
    return 1
  }
  cleanup_tagged_sessions
  {
    printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
    printf 'PMLE_HIDDEN_JIT_SETTINGS|cell=%s|settings=%s\n' \
      "$label" "${settings:-DEFAULT}"
    {
      printf '%s\n' \
        'whenever oserror exit failure rollback' \
        'whenever sqlerror exit sql.sqlcode rollback' \
        'set define off echo off verify off feedback off' \
        'alter session set container=FREEPDB1;' \
        "begin dbms_application_info.set_module('PMLE_HIDDEN_JIT','$label');end;" \
        '/'
      if [[ -n "$settings" ]]; then
        printf '%s\n' "$settings"
      fi
      cat "$root/probes/mle/hidden-jit-benchmark.sql"
      printf '%s\n' 'exit success rollback'
    } | docker compose -f "$root/compose.yaml" exec -T db \
      timeout --signal=TERM 300 sqlplus -s / as sysdba
  } | tee "$log"
  grep -q "^PMLE_HIDDEN_JIT|PASS|cell=$label|terminal_samples=40|" "$log"
  cleanup_tagged_sessions
}

run_cell default_async ''
run_cell immediate \
  'alter session set "_mle_compile_immediately"=true;'
run_cell immediate_sync \
  $'alter session set "_mle_compile_immediately"=true;\nalter session set "_mle_compilation_sync"=true;\nalter session set "_mle_compilation_errors_are_fatal"=true;'

printf 'PASS PMLE-HIDDEN-JIT-MATRIX classification=DIAGNOSTIC_NOT_GATE evidence=%s\n' \
  "$evidence"
