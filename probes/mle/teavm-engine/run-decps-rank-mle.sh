#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
phase="${1:-}"
tic_limit="${2:-5250}"
candidate="${DOOMDB_DECPS_CANDIDATE:-$project/target/javascript/doom-mle-simulation-engine-headless.js}"
candidate_sha="${DOOMDB_DECPS_EXPECTED_SHA:-5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3}"
rank_tag="${PMLE_RANK_TAG:-}"
plateau_passes="${PMLE_ASYNC_PLATEAU_PASSES:-4}"
[[ -z "$rank_tag" || "$rank_tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid de-CPS rank tag: %s\n' "$rank_tag" >&2; exit 2; }
rank_suffix="${rank_tag:+-$rank_tag}"
tables="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
evidence="$root/artifacts/performance/pmle-decps-rank"
log="$evidence/${phase}-${candidate_sha:0:12}-${tic_limit}${rank_suffix}.log"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-alert.XXXXXX")"
pool_parked=0
candidate_loaded=0
compiler_census_pid=

case "$phase" in
  interpreter|dual-clock|default-async|default-async-pair|default-async-plateau|hidden-jit|hidden-jit-hot|hidden-jit-heap|simple-jit) ;;
  *) printf 'usage: %s interpreter|dual-clock|default-async|default-async-pair|default-async-plateau|hidden-jit|hidden-jit-hot|hidden-jit-heap|simple-jit [TIC_LIMIT]\n' \
      "$0" >&2; exit 2 ;;
esac
[[ "$tic_limit" =~ ^[1-9][0-9]{1,5}$ && "$tic_limit" -le 5250 ]] || {
  printf 'tic limit must be between 10 and 5250\n' >&2
  exit 2
}
if [[ "$phase" == default-async-plateau ]]; then
  [[ "$tic_limit" == 5250 ]] ||
    { printf 'async plateau requires the exact 5250-tic stream\n' >&2; exit 2; }
  [[ "$plateau_passes" =~ ^[4-6]$ ]] ||
    { printf 'async plateau pass count must be between 4 and 6\n' >&2; exit 2; }
fi
[[ -s "$candidate" ]] || { printf 'candidate missing: %s\n' "$candidate" >&2; exit 1; }
[[ "$(shasum -a 256 "$candidate" | awk '{print $1}')" == "$candidate_sha" ]] || {
  printf 'de-CPS candidate SHA mismatch\n' >&2
  exit 1
}
[[ ! -e "$log" ]] || { printf 'evidence exists: %s\n' "$log" >&2; exit 1; }
if pgrep -f '[r]un-decps-ledger' >/dev/null; then
  printf 'exhaustive ledger is active; de-CPS rank deferred\n' >&2
  exit 1
fi
if [[ "$phase" == hidden-jit || "$phase" == hidden-jit-hot ||
      "$phase" == hidden-jit-heap || "$phase" == simple-jit ]]; then
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
  local safe_to_start_pool=1
  trap - EXIT
  if [[ -n "$compiler_census_pid" ]]; then
    kill "$compiler_census_pid" >/dev/null 2>&1 || true
    wait "$compiler_census_pid" >/dev/null 2>&1 || true
  fi
  if ! cleanup_tagged_session; then
    status=1
    safe_to_start_pool=0
  fi
  if [[ "$candidate_loaded" == 1 ]]; then
    if ! "$project/load-mle-module.sh" --production >/dev/null; then
      status=1
      safe_to_start_pool=0
    fi
  fi
  if ! "$root/scripts/oracle-alert-window.sh" end \
      "$alert_state" DECPS_RANK; then
    status=1
    safe_to_start_pool=0
  fi
  if [[ "$pool_parked" == 1 && "$safe_to_start_pool" == 1 ]]; then
    "$root/scripts/db_sql.sh" - >/dev/null <<'SQL' || status=1
begin doom_match_worker.start_warm_pool;end;
/
SQL
  elif [[ "$pool_parked" == 1 ]]; then
    printf '%s\n' \
      'PMLE_DECPS_RANK_CAPACITY|HELD_CLOSED|reason=cleanup_restore_or_alert_unproven' >&2
  fi
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
where match_state in('LOBBY','ACTIVE')
  and expires_at>(localtimestamp at time zone 'UTC');
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
if [[ "$phase" == default-async-pair || "$phase" == default-async-plateau ]]; then
  compiler_census="$evidence/${phase}-${candidate_sha:0:12}-${tic_limit}${rank_suffix}-compiler-threads.log"
  [[ ! -e "$compiler_census" ]] || {
    printf 'async-JIT compiler census exists: %s\n' "$compiler_census" >&2
    exit 1
  }
  (
    while true; do
      thread_rows="$(
        docker compose -f "$root/compose.yaml" exec -T db sh -c \
          'for f in /proc/[0-9]*/task/[0-9]*/comm; do
             name=$(cat "$f" 2>/dev/null) || continue
             echo "$name" | grep -Eiq "mle|graal|truffle|compiler" || continue
             stat=${f%/comm}/stat
             values=$(cat "$stat" 2>/dev/null) || continue
             set -- $values
             echo "$name|$((${14}+${15}))"
           done' || true
      )"
      count="$(grep -c . <<<"$thread_rows" || true)"
      names="$(cut -d'|' -f1 <<<"$thread_rows" | tr '\n' ',' | sed 's/,$//')"
      compiler_ticks="$(awk -F'|' '{sum+=$2} END{print sum+0}' <<<"$thread_rows")"
      cpu_line="$(
        docker compose -f "$root/compose.yaml" exec -T db \
          sh -c 'head -1 /proc/stat'
      )"
      read -r _ user nice system idle iowait irq softirq steal _ \
        <<<"$cpu_line"
      busy_ticks=$((user + nice + system + irq + softirq + steal))
      total_ticks=$((busy_ticks + idle + iowait))
      printf 'PMLE_DECPS_ASYNC_JIT_COMPILER_CENSUS|utc=%s|matching_threads=%s|compiler_cpu_ticks=%s|names=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$count" "$compiler_ticks" "$names"
      printf 'PMLE_DECPS_ASYNC_JIT_HOST_CPU|utc=%s|busy_ticks=%s|total_ticks=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$busy_ticks" "$total_ticks"
      sleep 30
    done
  ) >"$compiler_census" 2>&1 &
  compiler_census_pid=$!
fi
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
    if [[ "$phase" == hidden-jit || "$phase" == simple-jit ]]; then
      printf '%s\n' \
        'alter session set "_mle_compile_immediately"=true;' \
        'alter session set "_mle_compilation_sync"=true;' \
        'alter session set "_mle_compilation_errors_are_fatal"=true;'
    elif [[ "$phase" == hidden-jit-hot ]]; then
      printf '%s\n' \
        'alter session set "_mle_compilation_sync"=true;' \
        'alter session set "_mle_compilation_errors_are_fatal"=true;'
    elif [[ "$phase" == hidden-jit-heap ]]; then
      printf '%s\n' \
        'alter session set "_mle_max_heap_size"=1500;'
    fi
    replay="$(
      sed -e 's/__STREAM_NAME__/live-dm-2026-07-23/g' \
        -e 's/__DEATHMATCH__/1/g' \
        -e "s/__TIC_LIMIT__/$tic_limit/g" \
        "$project/replay-command-stream-mle.sql"
    )"
    if [[ "$phase" == default-async-plateau ]]; then
      printf '%s\n' \
        "select 'PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=1|event=BEGIN|utc='||to_char(systimestamp at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.FF3\"Z\"') from dual;" \
        "$replay" \
        "select 'PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=1|event=END|utc='||to_char(systimestamp at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.FF3\"Z\"') from dual;"
    else
      printf '%s\n' "$replay"
    fi
    if [[ "$phase" == default-async-pair ]]; then
      printf '%s\n' "$replay"
    elif [[ "$phase" == default-async-plateau ]]; then
      for pass in $(seq 2 "$plateau_passes"); do
        printf '%s\n' \
          "select 'PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=$pass|event=BEGIN|utc='||to_char(systimestamp at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.FF3\"Z\"') from dual;" \
          "$replay" \
          "select 'PMLE_DECPS_ASYNC_PLATEAU_PASS|pass=$pass|event=END|utc='||to_char(systimestamp at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.FF3\"Z\"') from dual;"
      done
    fi
    printf '%s\n' 'exit success rollback'
  } | timeout --signal=TERM \
      "$([[ "$phase" == default-async-plateau ]] && printf 7200 ||
        ([[ "$phase" == default-async-pair || "$phase" == simple-jit ]] &&
          printf 3600 || printf 1800))" \
      "$root/scripts/db_sql.sh" -
} | tee "$log"
if [[ -n "$compiler_census_pid" ]]; then
  kill "$compiler_census_pid" >/dev/null 2>&1 || true
  wait "$compiler_census_pid" >/dev/null 2>&1 || true
  compiler_census_pid=
  grep -q '^PMLE_DECPS_ASYNC_JIT_COMPILER_CENSUS|' "$compiler_census"
fi

expected_tickers=1
[[ "$phase" == default-async-pair ]] && expected_tickers=2
[[ "$phase" == default-async-plateau ]] && expected_tickers="$plateau_passes"
[[ "$(grep -c "^PMLE_LIVE_REPLAY_TICKER|stream=live-dm-2026-07-23|tics=$tic_limit|" \
  "$log")" == "$expected_tickers" ]]
if [[ "$phase" == default-async-pair ]]; then
  comparison="$evidence/${phase}-${candidate_sha:0:12}-${tic_limit}${rank_suffix}-comparison.log"
  [[ ! -e "$comparison" ]] || {
    printf 'async-JIT comparison evidence exists: %s\n' "$comparison" >&2
    exit 1
  }
  node "$project/compare-decps-async-jit.mjs" "$log" | tee "$comparison"
elif [[ "$phase" == default-async-plateau ]]; then
  comparison="$evidence/${phase}-${candidate_sha:0:12}-${tic_limit}${rank_suffix}-comparison.log"
  [[ ! -e "$comparison" ]] || {
    printf 'async plateau comparison evidence exists: %s\n' "$comparison" >&2
    exit 1
  }
  node "$project/compare-decps-async-plateau.mjs" \
    "$log" "$plateau_passes" | tee "$comparison"
fi
printf 'PASS PMLE-DECPS-RANK phase=%s tics=%s evidence=%s\n' \
  "$phase" "$tic_limit" "${log#"$root"/}"
