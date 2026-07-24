#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
stream="${1:-live-dm-2026-07-23}"
tic_limit="${2:-500}"
tag="${PMLE_EVIDENCE_TAG:-free-26ai-2026-07-24}"
evidence="$root/artifacts/performance/pmle-hidden-jit"
log="$evidence/${tag}-production-ticker-sync-hot-${tic_limit}.log"
pool_restore_needed=0

[[ "${PMLE_HIDDEN_JIT_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' \
    'set PMLE_HIDDEN_JIT_EXECUTE=YES for the unsupported-parameter diagnostic' >&2
  exit 2
}
[[ "$stream" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || {
  printf 'invalid stream name: %s\n' "$stream" >&2
  exit 2
}
[[ "$tic_limit" =~ ^[1-9][0-9]{1,5}$ && "$tic_limit" -le 5250 ]] || {
  printf 'tic limit must be between 10 and 5250\n' >&2
  exit 2
}
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'invalid evidence tag: %s\n' "$tag" >&2
  exit 2
}
[[ ! -e "$log" ]] || {
  printf 'evidence exists: %s\n' "$log" >&2
  exit 1
}

cleanup_tagged_session() {
  local rows incarnation
  rows="$(docker compose -f "$root/compose.yaml" exec -T db \
    sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pagesize 0
alter session set container=FREEPDB1;
select sid||','||serial# from v$session
where module='PMLE_HIDDEN_JIT' and action='ticker_sync_hot';
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

restore_pool() {
  local status=$?
  trap - EXIT
  cleanup_tagged_session || status=1
  if [[ "$pool_restore_needed" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' ||
begin doom_match_worker.start_warm_pool;end;
/
SQL
      status=1
  fi
  exit "$status"
}
trap restore_pool EXIT

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'JIT ticker diagnostic requires a quiet host:\n%s\n' "$busy_host" >&2
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
  printf 'JIT ticker diagnostic refuses %s active match(es)\n' "$active" >&2
  exit 1
}

pool_restore_needed=1
"$root/scripts/db_sql.sh" - <<'SQL' >/dev/null
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
      slot_.job_name,true,'hidden-JIT production-ticker diagnostic',
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

mkdir -p "$evidence"
{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf '%s\n' \
    'PMLE_HIDDEN_JIT_TICKER|DIAGNOSTIC_NOT_GATE|settings=sync+fatal|compile_immediately=false'
  {
    printf '%s\n' \
      "begin dbms_application_info.set_module('PMLE_HIDDEN_JIT','ticker_sync_hot');end;" \
      '/' \
      'alter session set "_mle_compilation_sync"=true;' \
      'alter session set "_mle_compilation_errors_are_fatal"=true;'
    sed -e "s/__STREAM_NAME__/$stream/g" \
      -e 's/__DEATHMATCH__/1/g' \
      -e "s/__TIC_LIMIT__/$tic_limit/g" \
      "$project/replay-command-stream-mle.sql"
  } | "$root/scripts/db_sql.sh" -
} | tee "$log"

grep -q "^PMLE_LIVE_REPLAY_TICKER|stream=$stream|tics=$tic_limit|" "$log"
printf 'PASS PMLE-HIDDEN-JIT-TICKER tics=%s evidence=%s\n' "$tic_limit" "$log"
