#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
sql="$root/probes/mle/teavm-engine/calibrate-memory-mle.sql"
# Use a larger diagnostic allocation than the 64 MiB soak margin. Oracle may
# satisfy part of a 64 MiB request from already-reserved JS heap pages, which
# makes the process sampler look blind even when it is working correctly.
allocation_bytes=134217728
minimum_visible_bytes=$((48 * 1024 * 1024))
run_log="$(mktemp "${TMPDIR:-/tmp}/doom-mle-memory-cal.XXXXXX")"
run_pid=''

cleanup() {
  if [[ -n "$run_pid" ]] && kill -0 "$run_pid" 2>/dev/null; then
    kill "$run_pid" 2>/dev/null || true
    wait "$run_pid" 2>/dev/null || true
  fi
  rm -f "$run_log"
}
trap cleanup EXIT

"$root/scripts/db_sql.sh" "$sql" >"$run_log" 2>&1 &
run_pid=$!

session_sample() {
  docker compose -f "$root/compose.yaml" exec -T db sqlplus -s / as sysdba <<'SQL'
set heading off feedback off pages 0 verify off echo off lines 500 trimspool on
alter session set container=FREEPDB1;
select 'PMLE_MLE_MEMORY_CAL_SESSION|sid='||s.sid||'|serial='||s.serial#||
  '|spid='||p.spid||'|action='||s.action||
  '|pga='||coalesce(max(case when n.name='session pga memory' then st.value end),0)||
  '|pga_max='||coalesce(max(case when n.name='session pga memory max' then st.value end),0)||
  '|uga='||coalesce(max(case when n.name='session uga memory' then st.value end),0)||
  '|uga_max='||coalesce(max(case when n.name='session uga memory max' then st.value end),0)||
  '|process_pga='||max(p.pga_used_mem)||'|process_pga_max='||max(p.pga_max_mem)
from v$session s join v$process p on p.addr=s.paddr
join v$sesstat st on st.sid=s.sid
join v$statname n on n.statistic#=st.statistic#
where s.module='DOOM_MLE_MEMORY_CAL'
group by s.sid,s.serial#,p.spid,s.action;
exit
SQL
}

process_sample() {
  local spid="$1" phase="$2"
  [[ "$spid" =~ ^[0-9]+$ ]] || { printf 'invalid Oracle spid: %s\n' "$spid" >&2; return 1; }
  docker compose -f "$root/compose.yaml" exec -T db sh -c '
    awk -v phase="$2" -v spid="$1" '\''
      /^(Rss|Pss|Private_Clean|Private_Dirty|Anonymous):/ {
        value[$1]=$2*1024
      }
      END {
        printf "PMLE_MLE_MEMORY_CAL_PROCESS|phase=%s|spid=%s|rss=%d|pss=%d|private_clean=%d|private_dirty=%d|anonymous=%d\n",
          phase,spid,value["Rss:"],value["Pss:"],value["Private_Clean:"],
          value["Private_Dirty:"],value["Anonymous:"]
      }
    '\'' "/proc/$1/smaps_rollup"
  ' _ "$spid" "$phase"
}

declare -A seen pss private
deadline=$((SECONDS + 180))
while kill -0 "$run_pid" 2>/dev/null && ((SECONDS < deadline)); do
  row="$(session_sample | tr -d '\r' | awk '/PMLE_MLE_MEMORY_CAL_SESSION/{print;exit}')"
  if [[ -n "$row" ]]; then
    action="$(sed -n 's/.*|action=\([^|]*\).*/\1/p' <<<"$row")"
    spid="$(sed -n 's/.*|spid=\([^|]*\).*/\1/p' <<<"$row")"
    case "$action" in
      BASELINE_READY|ALLOCATED_READY|RELEASED_READY)
        phase="${action%_READY}"
        if [[ -z "${seen[$phase]:-}" ]]; then
          printf '%s\n' "$row"
          process_row="$(process_sample "$spid" "$phase")"
          printf '%s\n' "$process_row"
          pss[$phase]="$(sed -n 's/.*|pss=\([^|]*\).*/\1/p' <<<"$process_row")"
          clean="$(sed -n 's/.*|private_clean=\([^|]*\).*/\1/p' <<<"$process_row")"
          dirty="$(sed -n 's/.*|private_dirty=\([^|]*\).*/\1/p' <<<"$process_row")"
          private[$phase]=$((clean + dirty))
          seen[$phase]=1
        fi
        ;;
    esac
  fi
  sleep 1
done

status=0
wait "$run_pid" || status=$?
cat "$run_log"
((status == 0)) || exit "$status"
for phase in BASELINE ALLOCATED RELEASED; do
  [[ -n "${seen[$phase]:-}" ]] || { printf 'missing memory calibration phase: %s\n' "$phase" >&2; exit 1; }
done

pss_delta=$((pss[ALLOCATED] - pss[BASELINE]))
private_delta=$((private[ALLOCATED] - private[BASELINE]))
if ((pss_delta < minimum_visible_bytes && private_delta < minimum_visible_bytes)); then
  printf 'memory sampler did not observe retained allocation: pss_delta=%d private_delta=%d\n' \
    "$pss_delta" "$private_delta" >&2
  exit 1
fi
printf 'PMLE_MLE_MEMORY_CAL|PASS|allocation_bytes=%d|minimum_visible_bytes=%d|pss_delta=%d|private_delta=%d|pga_is_complete=0\n' \
  "$allocation_bytes" "$minimum_visible_bytes" "$pss_delta" "$private_delta"
