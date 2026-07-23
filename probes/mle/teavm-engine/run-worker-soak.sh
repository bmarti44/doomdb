#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
duration="${DOOMDB_MLE_WORKER_SOAK_SECONDS:-1800}"
warmup="${DOOMDB_MLE_WORKER_SOAK_WARMUP_SECONDS:-300}"
interval="${DOOMDB_MLE_WORKER_SOAK_SAMPLE_SECONDS:-30}"
margin="${DOOMDB_MLE_SOAK_MEMORY_MARGIN_BYTES:-67108864}"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23-cutover}"
[[ "$duration" =~ ^[1-9][0-9]*$ && "$duration" -le 1800 ]] ||
  { printf 'invalid worker soak duration: %s\n' "$duration" >&2;exit 2; }
[[ "$warmup" =~ ^[0-9]+$ && "$warmup" -le 600 ]] ||
  { printf 'invalid worker soak warmup: %s\n' "$warmup" >&2;exit 2; }
[[ "$interval" =~ ^[1-9][0-9]*$ ]] ||
  { printf 'invalid worker soak sample interval: %s\n' "$interval" >&2;exit 2; }
[[ "$margin" =~ ^[1-9][0-9]*$ ]] ||
  { printf 'invalid worker soak memory margin: %s\n' "$margin" >&2;exit 2; }
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }

busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
if [[ -n "$busy_host" ]]; then
  printf 'MLE worker soak requires a quiet host; active work:\n%s\n' "$busy_host" >&2
  exit 1
fi

evidence="$root/artifacts/performance/pmle-worker-soak"
mkdir -p "$evidence"
log="$evidence/run-${tag}.log"
[[ ! -e "$log" ]] ||
  { printf 'worker soak evidence already exists: %s\n' "$log" >&2;exit 1; }
match_file="$(mktemp "${TMPDIR:-/tmp}/doom-mle-worker-soak-match.XXXXXX")"
browser_log="$(mktemp "${TMPDIR:-/tmp}/doom-mle-worker-soak-browser.XXXXXX")"
memory_log="$(mktemp "${TMPDIR:-/tmp}/doom-mle-worker-soak-memory.XXXXXX")"
browser_pid=''
match=''
browser_preserved=0
run_terminal=0
process_missing=0
browser_failed=0

preserve_browser_evidence() {
  ((browser_preserved == 0)) || return 0
  [[ -e "$browser_log" && -e "$log" ]] || return 0
  printf 'PMLE_WORKER_SOAK_BROWSER_EVIDENCE|BEGIN\n' >>"$log"
  cat "$browser_log" >>"$log"
  printf 'PMLE_WORKER_SOAK_BROWSER_EVIDENCE|END\n' >>"$log"
  browser_preserved=1
}

cleanup_match() {
  [[ "$match" =~ ^[0-9a-f]{32}$ ]] || return 0
  if [[ "${DOOMDB_MLE_WORKER_SOAK_KEEP_MATCH:-NO}" == YES ]]; then
    printf 'PMLE_WORKER_SOAK_MATCH|RETAINED_FOR_DIAGNOSTIC|match=%s\n' "$match" >&2
    return 0
  fi
  "$root/scripts/db_sql.sh" - >/dev/null <<SQL || true
declare
  l_generation number;l_job varchar2(64);l_standby varchar2(64);
  l_count number:=0;l_warm number:=0;
begin
  begin
    select generation,job_name into l_generation,l_job
      from doom_match_worker_control where match_id='$match';
    begin doom_match_worker.stop_match('$match',l_generation);exception when others then null;end;
    select count(*) into l_warm from doom_mle_warm_slot where job_name=l_job;
    if l_warm=0 then
      begin doom_worker_lifecycle.stop_job(
        l_job,true,'soak cleanup dedicated authority');
      exception when others then null;end;
      begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    end if;
  exception when no_data_found then null;end;
  begin
    select job_name into l_standby from doom_match_standby_control
      where match_id='$match';
    update doom_match_standby_control set stop_requested=1 where match_id='$match';
    commit;
    select count(*) into l_warm from doom_mle_warm_slot where job_name=l_standby;
    if l_warm=0 then
      begin doom_worker_lifecycle.stop_job(
        l_standby,true,'soak cleanup dedicated standby');
      exception when others then null;end;
      begin dbms_scheduler.drop_job(l_standby,true);exception when others then null;end;
    end if;
  exception when no_data_found then null;end;
  -- Warm-pool jobs own retained MLE contexts and must be allowed to return
  -- through run_warm_slot's RUNNING -> READY fence. Deleting the match or
  -- force-stopping its shared job first leaves a stale RUNNING capacity row.
  for i in 1..200 loop
    select count(*) into l_count from doom_mle_warm_slot
      where assigned_match='$match';
    exit when l_count=0;
    dbms_session.sleep(.1);
  end loop;
  if l_count<>0 then
    for slot_ in (
      select slot_id,job_name,incarnation_token,worker_sid,worker_serial,
        worker_spid,worker_job_run from doom_mle_warm_slot
      where assigned_match='$match'
    ) loop
      begin doom_worker_lifecycle.stop_job(
        slot_.job_name,true,'soak cleanup bounded retained-slot force',
        slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
        slot_.worker_spid,slot_.worker_job_run);
      exception when others then null;end;
    end loop;
  end if;
  delete from doom_match where match_id='$match';commit;
end;
/
SQL
}
cleanup() {
  if [[ -n "$browser_pid" ]] && kill -0 "$browser_pid" 2>/dev/null; then
    kill "$browser_pid" 2>/dev/null || true
    wait "$browser_pid" 2>/dev/null || true
  fi
  preserve_browser_evidence
  cleanup_match
  rm -f "$match_file" "$browser_log" "$memory_log"
}
on_exit() {
  local status=$?
  if ((run_terminal == 0)) && [[ -e "$log" ]]; then
    preserve_browser_evidence
    printf 'PMLE_WORKER_SOAK|VOIDED|reason=harness_exit|exit_status=%s|evidence=%s\n' \
      "$status" "${log#$root/}" >>"$log"
  fi
  cleanup
  return "$status"
}
trap on_exit EXIT

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  "$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/environment-metadata.sql"
  "$root/scripts/db_sql.sh" "$root/probes/mle/teavm-engine/artifact-metadata.sql"
  if [[ "${DOOMDB_MLE_WORKER_SOAK_CALIBRATE_MEMORY:-YES}" == YES ]]; then
    "$root/probes/mle/teavm-engine/run-memory-calibration.sh"
  else
    printf 'PMLE_MLE_MEMORY_CAL|SKIPPED|rehearsal_only=1\n'
  fi
} | tee "$log"

DOOMDB_MATCH_ID_FILE="$match_file" \
DOOMDB_MULTIPLAYER_SOAK_SECONDS="$duration" \
DOOMDB_MULTIPLAYER_SOAK_WARMUP_SECONDS="$warmup" \
DOOMDB_MULTIPLAYER_STARTUP_TIMEOUT_MS=300000 \
  node "$root/tests/verify-p13.5-multiplayer-soak.mjs" >"$browser_log" 2>&1 &
browser_pid=$!

for _ in $(seq 1 1200); do
  match="$(tr -d '\r\n' <"$match_file" 2>/dev/null || true)"
  [[ "$match" =~ ^[0-9a-f]{32}$ ]] && break
  kill -0 "$browser_pid" 2>/dev/null || break
  sleep .25
done
if [[ ! "$match" =~ ^[0-9a-f]{32}$ ]]; then
  cat "$browser_log" | tee -a "$log"
  printf 'worker soak did not obtain a match id\n' >&2
  exit 1
fi
printf 'PMLE_WORKER_SOAK_MATCH|BOUND|match=%s\n' "$match" | tee -a "$log"

ready_epoch=''
while kill -0 "$browser_pid" 2>/dev/null; do
  owner_rows="$(docker compose -f "$root/compose.yaml" exec -T db sqlplus -s / as sysdba <<SQL
set heading off feedback off pages 0 verify off echo off lines 500 trimspool on
alter session set container=FREEPDB1;
select 'PMLE_WORKER_SOAK_OWNER|role='||q.role||'|control_status='||q.control_status||
  '|control_sid='||nvl(to_char(q.sid),'-')||'|sid='||nvl(to_char(s.sid),'-')||
  '|serial='||nvl(to_char(s.serial#),'-')||'|spid='||nvl(p.spid,'-')||
  '|scheduler_running='||case when r.job_name is null then '0' else '1' end||
  '|action='||nvl(s.action,'-')||'|pga_bytes='||nvl(p.pga_used_mem,0)||
  '|pga_max_bytes='||nvl(p.pga_max_mem,0)
from (
  select 'AUTHORITY' role,worker_sid sid,worker_status control_status,job_name
    from doom.doom_match_worker_control where match_id='$match'
  union all
  select 'STANDBY' role,worker_sid sid,standby_status control_status,job_name
    from doom.doom_match_standby_control where match_id='$match'
) q left join v\$session s on s.sid=q.sid
  left join v\$process p on p.addr=s.paddr
  left join dba_scheduler_running_jobs r
    on r.owner='DOOM' and r.job_name=q.job_name
order by q.role;
exit
SQL
)"
  owner_count="$(awk '/PMLE_WORKER_SOAK_OWNER/ && /[|]control_status=READY[|]/ && /[|]spid=[0-9]+[|]/{count++} END{print count+0}' <<<"$owner_rows")"
  if [[ "$owner_count" -eq 2 && -z "$ready_epoch" ]]; then
    ready_epoch="$(date +%s)"
    printf 'PMLE_WORKER_SOAK_WARMUP|BEGIN|seconds=%s|epoch=%s\n' \
      "$warmup" "$ready_epoch" | tee -a "$log"
    printf '%s\n' "$owner_rows" | awk '/PMLE_WORKER_SOAK_OWNER/' |
      sed 's/PMLE_WORKER_SOAK_OWNER/PMLE_WORKER_SOAK_READY_OWNER/' |
      tee -a "$log"
  fi
  now="$(date +%s)"
  if [[ -n "$ready_epoch" && "$now" -ge $((ready_epoch + warmup)) ]]; then
    while IFS= read -r owner; do
      [[ "$owner" == PMLE_WORKER_SOAK_OWNER* ]] || continue
      role="$(sed -n 's/.*|role=\([^|]*\).*/\1/p' <<<"$owner")"
      spid="$(sed -n 's/.*|spid=\([^|]*\).*/\1/p' <<<"$owner")"
      printf '%s\n' "$owner" | tee -a "$memory_log" >>"$log"
      if [[ "$spid" =~ ^[0-9]+$ ]]; then
        sample_output="$(docker compose -f "$root/compose.yaml" exec -T db sh -c '
          if [ ! -r "/proc/$2/smaps_rollup" ]; then
            printf "PMLE_WORKER_SOAK_PROCESS_MISSING|role=%s|spid=%s|sample_epoch=%s\n" \
              "$1" "$2" "$3"
            exit 0
          fi
          awk -v role="$1" -v spid="$2" -v sampled="$3" '\''
            /^(Rss|Pss|Pss_Anon|Pss_File|Pss_Shmem|Shared_Clean|Shared_Dirty|Private_Clean|Private_Dirty|Anonymous):/ {value[$1]=$2*1024}
            END {printf "PMLE_WORKER_SOAK_PROCESS|role=%s|spid=%s|sample_epoch=%s|rss=%d|pss=%d|pss_anon=%d|pss_file=%d|pss_shmem=%d|shared_clean=%d|shared_dirty=%d|private_clean=%d|private_dirty=%d|anonymous=%d\n",
              role,spid,sampled,value["Rss:"],value["Pss:"],
              value["Pss_Anon:"],value["Pss_File:"],value["Pss_Shmem:"],
              value["Shared_Clean:"],value["Shared_Dirty:"],
              value["Private_Clean:"],value["Private_Dirty:"],value["Anonymous:"]}
          '\'' "/proc/$2/smaps_rollup"
        ' _ "$role" "$spid" "$now" </dev/null)"
        printf '%s\n' "$sample_output" | tee -a "$memory_log" >>"$log"
        if [[ "$sample_output" == *PMLE_WORKER_SOAK_PROCESS_MISSING* ]]; then
          process_missing=1
        fi
      fi
    done <<<"$owner_rows"
  fi
  ((process_missing == 0)) || break
  sleep "$interval"
done

status=0
if ((process_missing != 0)) && kill -0 "$browser_pid" 2>/dev/null; then
  kill "$browser_pid" 2>/dev/null || true
fi
wait "$browser_pid" || status=$?
browser_pid=''
preserve_browser_evidence
if ((process_missing != 0)); then
  printf 'PMLE_WORKER_SOAK|FAIL|reason=unplanned_retained_process_replacement|evidence=%s\n' \
    "${log#$root/}" | tee -a "$log"
  run_terminal=1
  exit 1
fi
if ((status != 0)); then browser_failed=1;fi

memory_status=0
summary="$(awk -F'|' -v margin="$margin" '
  function field(name, i,p) {
    for(i=1;i<=NF;i++){split($i,p,"=");if(p[1]==name)return p[2]+0}return 0
  }
  /PMLE_WORKER_SOAK_PROCESS/ {
    role="";spid="";for(i=1;i<=NF;i++){split($i,p,"=");if(p[1]=="role")role=p[2];if(p[1]=="spid")spid=p[2]}
    rss=field("rss");pss=field("pss");priv=field("private_clean")+field("private_dirty")
    anon=field("pss_anon");shared_dirty=field("shared_dirty")
    if(!(role in count)){base_rss[role]=rss;base_pss[role]=pss;base_priv[role]=priv;base_anon[role]=anon;base_shared_dirty[role]=shared_dirty;first_spid[role]=spid;previous[role]=pss}
    count[role]++;if(spid!=first_spid[role])changed[role]=1
    if(rss>max_rss[role])max_rss[role]=rss;if(pss>max_pss[role])max_pss[role]=pss
    if(priv>max_priv[role])max_priv[role]=priv
    if(anon>max_anon[role])max_anon[role]=anon
    if(shared_dirty>max_shared_dirty[role])max_shared_dirty[role]=shared_dirty
    if(pss-previous[role]>=8388608)steps[role]++;previous[role]=pss
    end_rss[role]=rss;end_pss[role]=pss;end_priv[role]=priv
    end_anon[role]=anon;end_shared_dirty[role]=shared_dirty
  }
  END {
    roles[1]="AUTHORITY";roles[2]="STANDBY";ok=1
    for(j=1;j<=2;j++){
      r=roles[j];pass=count[r]>0&&!changed[r]&&max_rss[r]<=base_rss[r]+margin&&
        max_pss[r]<=base_pss[r]+margin&&max_priv[r]<=base_priv[r]+margin
      if(!pass)ok=0
      printf "PMLE_WORKER_SOAK_MEMORY|%s|role=%s|samples=%d|warmup_excluded=1|spid_stable=%d|margin=%d|rss_base=%d|rss_max=%d|rss_end=%d|pss_base=%d|pss_max=%d|pss_end=%d|private_base=%d|private_max=%d|private_end=%d|pss_anon_base=%d|pss_anon_max=%d|pss_anon_end=%d|shared_dirty_base=%d|shared_dirty_max=%d|shared_dirty_end=%d|plateau_steps_8m=%d\n",
        pass?"PASS":"FAIL",r,count[r]+0,changed[r]?0:1,margin,base_rss[r]+0,max_rss[r]+0,end_rss[r]+0,
        base_pss[r]+0,max_pss[r]+0,end_pss[r]+0,base_priv[r]+0,max_priv[r]+0,end_priv[r]+0,
        base_anon[r]+0,max_anon[r]+0,end_anon[r]+0,base_shared_dirty[r]+0,max_shared_dirty[r]+0,end_shared_dirty[r]+0,steps[r]+0
    }
    exit(ok?0:1)
  }' "$memory_log")" || memory_status=$?
printf '%s\n' "$summary" | tee -a "$log"

docker compose -f "$root/compose.yaml" exec -T db sqlplus -s / as sysdba <<SQL | tee -a "$log"
set heading off feedback off pages 0 verify off echo off lines 1000 trimspool on
alter session set container=FREEPDB1;
select 'PMLE_WORKER_SOAK_SLOW|tic='||c.tic||'|generation='||c.generation||
  '|elapsed_ms='||round(c.elapsed_ms,3)||'|started_utc='||
  to_char(sys_extract_utc(c.started_at),'YYYY-MM-DD"T"HH24:MI:SS.FF6')||'Z'||
  '|ended_utc='||to_char(sys_extract_utc(c.ended_at),'YYYY-MM-DD"T"HH24:MI:SS.FF6')||'Z'||
  '|ash_samples='||count(a.sample_time)||'|on_cpu='||
  sum(case when a.session_state='ON CPU' then 1 else 0 end)||'|resmgr='||
  sum(case when a.event like 'resmgr:%' then 1 else 0 end)||'|commit_io='||
  sum(case when a.event in('log file sync','log file parallel write') then 1 else 0 end)
from doom.doom_match_slow_call c left join v\$active_session_history a
  on a.session_id=c.worker_sid and sys_extract_utc(a.sample_time) between
    sys_extract_utc(c.started_at)-interval '1' second and
    sys_extract_utc(c.ended_at)+interval '1' second
where c.match_id='$match'
group by c.tic,c.generation,c.elapsed_ms,c.started_at,c.ended_at
order by c.tic;
select 'PMLE_WORKER_SOAK_RES_MGR|ash_samples='||count(*)||'|cpu_quantum='||
  sum(case when event='resmgr:cpu quantum' then 1 else 0 end)
from v\$active_session_history
where session_id in(
  select worker_sid from doom.doom_match_worker_control where match_id='$match'
  union all
  select worker_sid from doom.doom_match_standby_control where match_id='$match')
  and sample_time>=(select min(started_at) from doom.doom_match_slow_call where match_id='$match');
exit
SQL

if ((browser_failed != 0)); then
  printf 'PMLE_WORKER_SOAK|FAIL|reason=browser_gate|browser_status=%s|memory_status=%s|evidence=%s\n' \
    "$status" "$memory_status" "${log#$root/}" | tee -a "$log"
  run_terminal=1
  exit "$status"
elif ((memory_status == 0)); then
  printf 'PMLE_WORKER_SOAK|PASS|duration_s=%s|warmup_s=%s|memory_margin=%s|evidence=%s\n' \
    "$duration" "$warmup" "$margin" "${log#$root/}" | tee -a "$log"
  run_terminal=1
else
  printf 'PMLE_WORKER_SOAK|FAIL|duration_s=%s|warmup_s=%s|memory_margin=%s|evidence=%s\n' \
    "$duration" "$warmup" "$margin" "${log#$root/}" | tee -a "$log"
  run_terminal=1
  exit "$memory_status"
fi
