#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
duration="${DOOMDB_MLE_SOAK_SECONDS:-1800}"
warmup="${DOOMDB_MLE_SOAK_WARMUP_SECONDS:-300}"
interval="${DOOMDB_MLE_SOAK_SAMPLE_SECONDS:-30}"
memory_margin="${DOOMDB_MLE_SOAK_MEMORY_MARGIN_BYTES:-67108864}"
sql="$root/probes/mle/teavm-engine/soak-multiplayer-mle.sql"
calibration="$root/probes/mle/teavm-engine/run-memory-calibration.sh"
run_identifier="DOOM_MLE_SOAK_$$_$RANDOM"

[[ "$duration" =~ ^[1-9][0-9]*$ ]] || { printf 'invalid soak duration: %s\n' "$duration" >&2; exit 2; }
[[ "$warmup" =~ ^[0-9]+$ ]] || { printf 'invalid soak warmup: %s\n' "$warmup" >&2; exit 2; }
[[ "$interval" =~ ^[1-9][0-9]*$ ]] || { printf 'invalid sample interval: %s\n' "$interval" >&2; exit 2; }
[[ "$memory_margin" =~ ^[1-9][0-9]*$ ]] || { printf 'invalid memory margin: %s\n' "$memory_margin" >&2; exit 2; }

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'MLE soak requires a quiet host; active work:\n%s\n' "$busy_host" >&2
  exit 1
fi
printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
"$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/environment-metadata.sql"

run_log="$(mktemp "${TMPDIR:-/tmp}/doom-mle-soak.XXXXXX")"
memory_log="$(mktemp "${TMPDIR:-/tmp}/doom-mle-soak-memory.XXXXXX")"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doom-mle-soak-alert.XXXXXX")"
run_pid=''
cleanup() {
  prior_status=$?
  if [[ -n "$run_pid" ]] && kill -0 "$run_pid" 2>/dev/null; then
    kill "$run_pid" 2>/dev/null || true
    wait "$run_pid" 2>/dev/null || true
  fi
  if ! "$root/scripts/oracle-alert-window.sh" end "$alert_state" \
    MULTIPLAYER_SOAK; then
    prior_status=1
  fi
  rm -f "$run_log" "$memory_log" "$alert_state"
  trap - EXIT
  exit "$prior_status"
}
trap cleanup EXIT
"$root/scripts/oracle-alert-window.sh" begin "$alert_state" MULTIPLAYER_SOAK

if [[ "${DOOMDB_MLE_SOAK_CALIBRATE_MEMORY:-YES}" == YES ]]; then
  "$calibration"
fi

{
  printf "begin dbms_session.set_identifier('%s');end;\n/\n" "$run_identifier"
  sed -e "s/c_duration_seconds constant number:=1800;/c_duration_seconds constant number:=$duration;/" \
    -e "s/c_warmup_seconds constant number:=300;/c_warmup_seconds constant number:=$warmup;/" "$sql"
} | "$root/scripts/db_sql.sh" - >"$run_log" 2>&1 &
run_pid=$!

while kill -0 "$run_pid" 2>/dev/null; do
  session_row="$(docker compose -f "$root/compose.yaml" exec -T db sqlplus -s / as sysdba <<SQL
set heading off feedback off pages 0 verify off echo off lines 300 trimspool on
alter session set container=FREEPDB1;
select 'PMLE_TEAVM_MULTI_SOAK_OWNER|sid='||s.sid||'|serial='||s.serial#||
  '|spid='||p.spid||
  '|action='||nvl(s.action,'-')||
  '|pga_bytes='||max(case when n.name='session pga memory' then st.value end)||
  '|pga_max_bytes='||max(case when n.name='session pga memory max' then st.value end)||
  '|process_pga_bytes='||max(p.pga_used_mem)||
  '|process_pga_max_bytes='||max(p.pga_max_mem)
from v\$session s join v\$sesstat st on st.sid=s.sid
join v\$statname n on n.statistic#=st.statistic#
join v\$process p on p.addr=s.paddr
where s.module='DOOM_MLE_SOAK' and s.client_identifier='$run_identifier'
group by s.sid,s.serial#,p.spid,s.action;
exit
SQL
)"
  session_row="$(awk '/PMLE_TEAVM_MULTI_SOAK_OWNER/{print;exit}' <<<"$session_row")"
  if [[ -n "$session_row" ]]; then
    printf '%s\n' "$session_row" | tee -a "$memory_log"
    spid="$(sed -n 's/.*|spid=\([^|]*\).*/\1/p' <<<"$session_row")"
    if [[ "$spid" =~ ^[0-9]+$ ]]; then
      action="$(sed -n 's/.*|action=\([^|]*\).*/\1/p' <<<"$session_row")"
      docker compose -f "$root/compose.yaml" exec -T db sh -c '
        awk -v spid="$1" -v action="$2" '\''
          /^(Rss|Pss|Private_Clean|Private_Dirty|Anonymous):/ {value[$1]=$2*1024}
          END {printf "PMLE_TEAVM_MULTI_SOAK_PROCESS|spid=%s|action=%s|rss=%d|pss=%d|private_clean=%d|private_dirty=%d|anonymous=%d\n",
            spid,action,value["Rss:"],value["Pss:"],value["Private_Clean:"],
            value["Private_Dirty:"],value["Anonymous:"]}
        '\'' "/proc/$1/smaps_rollup"
      ' _ "$spid" "$action" | tee -a "$memory_log"
    fi
  fi
  sleep "$interval"
done

status=0
wait "$run_pid" || status=$?
cat "$run_log"
if ((status == 0)); then
  memory_summary="$(awk -F'|' -v margin="$memory_margin" '
    function field(name, i,p) {
      for (i=1;i<=NF;i++) {split($i,p,"=");if(p[1]==name)return p[2]+0}
      return 0
    }
    /PMLE_TEAVM_MULTI_SOAK_PROCESS/ && /[|]action=TICKER[|]/ {
      rss=field("rss");pss=field("pss");private=field("private_clean")+field("private_dirty")
      if (!count++) {base_rss=rss;base_pss=pss;base_private=private;previous=pss}
      if (rss>max_rss)max_rss=rss;if(pss>max_pss)max_pss=pss
      if(private>max_private)max_private=private
      if(pss-previous>=8388608)steps++;previous=pss
      end_rss=rss;end_pss=pss;end_private=private
    }
    END {
      if(!count)exit 2
      pass=max_rss<=base_rss+margin && max_pss<=base_pss+margin && max_private<=base_private+margin
      printf "PMLE_TEAVM_MULTI_SOAK_MEMORY_GATE|%s|samples=%d|warmup_excluded=1|margin=%d|rss_base=%d|rss_max=%d|rss_end=%d|pss_base=%d|pss_max=%d|pss_end=%d|private_base=%d|private_max=%d|private_end=%d|plateau_steps_8m=%d",
        pass?"PASS":"FAIL",count,margin,base_rss,max_rss,end_rss,base_pss,max_pss,end_pss,
        base_private,max_private,end_private,steps
      exit (pass?0:1)
    }' "$memory_log")" || {
      memory_status=$?;printf '%s\n' "${memory_summary:-PMLE_TEAVM_MULTI_SOAK_MEMORY_GATE|FAIL|reason=no_scored_samples}" >&2
      exit "$memory_status"
    }
  printf '%s\n' "$memory_summary"
  owner="$(awk -F'[|=]' '/PMLE_TEAVM_MULTI_SOAK_OWNER/{line=$0} END{print line}' "$memory_log" 2>/dev/null || true)"
  # Correlate every recorded >100 ms call with ASH. ASH is sampled, so zero
  # rows is valid evidence that the short call fell between samples.
  while IFS= read -r slow; do
    tic="$(sed -n 's/.*|tic=\([^|]*\).*/\1/p' <<<"$slow")"
    started="$(sed -n 's/.*|started_utc=\([^|]*\).*/\1/p' <<<"$slow")"
    ended="$(sed -n 's/.*|ended_utc=\([^|]*\).*/\1/p' <<<"$slow")"
    sid="$(sed -n 's/.*|sid=\([^|]*\).*/\1/p' <<<"$owner")"
    serial="$(sed -n 's/.*|serial=\([^|]*\).*/\1/p' <<<"$owner")"
    [[ "$tic" =~ ^[0-9]+$ && "$sid" =~ ^[0-9]+$ && "$serial" =~ ^[0-9]+$ ]] || continue
    [[ "$started" =~ ^[0-9TZ:.-]+$ && "$ended" =~ ^[0-9TZ:.-]+$ ]] || continue
    started="${started%Z}";ended="${ended%Z}"
    if ! docker compose -f "$root/compose.yaml" exec -T db sqlplus -s / as sysdba <<SQL
set heading off feedback off pages 0 verify off echo off lines 500 trimspool on
alter session set container=FREEPDB1;
select 'PMLE_TEAVM_MULTI_SOAK_ASH|tic=$tic|samples='||count(*)||
  '|on_cpu='||coalesce(sum(case when session_state='ON CPU' then 1 else 0 end),0)||
  '|waiting='||coalesce(sum(case when session_state='WAITING' then 1 else 0 end),0)||
  '|resmgr='||coalesce(sum(case when event like 'resmgr:%' then 1 else 0 end),0)
from v\$active_session_history
where session_id=$sid and session_serial#=$serial
  and sys_extract_utc(sample_time) between
    to_timestamp('$started','YYYY-MM-DD"T"HH24:MI:SS.FF6')-interval '1' second and
    to_timestamp('$ended','YYYY-MM-DD"T"HH24:MI:SS.FF6')+interval '1' second;
select 'PMLE_TEAVM_MULTI_SOAK_ASH_EVENT|tic=$tic|state='||session_state||
  '|category='||case when event like 'resmgr:%' then 'RESOURCE_MANAGER'
    when session_state='ON CPU' then 'ON_CPU' else nvl(wait_class,'OTHER') end||
  '|event='||nvl(event,'ON CPU')||'|samples='||count(*)
from v\$active_session_history
where session_id=$sid and session_serial#=$serial
  and sys_extract_utc(sample_time) between
    to_timestamp('$started','YYYY-MM-DD"T"HH24:MI:SS.FF6')-interval '1' second and
    to_timestamp('$ended','YYYY-MM-DD"T"HH24:MI:SS.FF6')+interval '1' second
group by session_state,event,wait_class;
exit
SQL
    then
      printf 'PMLE_TEAVM_MULTI_SOAK_ASH|tic=%s|status=UNAVAILABLE\n' "$tic"
    fi
  done < <(awk '/PMLE_TEAVM_MULTI_SOAK_SLOW/' "$run_log")
fi
exit "$status"
