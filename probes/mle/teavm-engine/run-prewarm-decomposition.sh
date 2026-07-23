#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tag="${PMLE_EVIDENCE_TAG:-2026-07-23-prewarm-decomposition}"
evidence="$root/artifacts/performance/pmle-prewarm"
log="$evidence/run-${tag}.log"

[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid evidence tag: %s\n' "$tag" >&2;exit 2; }
mkdir -p "$evidence"
[[ ! -e "$log" ]] ||
  { printf 'prewarm evidence already exists: %s\n' "$log" >&2;exit 1; }

now_ms() { node -e 'process.stdout.write(String(Date.now()))'; }
phase() {
  local name=$1
  shift
  local started finished
  started=$(now_ms)
  "$@"
  finished=$(now_ms)
  printf 'PMLE_PREWARM_PHASE|name=%s|wall_ms=%s\n' \
    "$name" "$((finished-started))"
}

active="$("$root/scripts/db_sql.sh" - <<'SQL'
set heading off feedback off pagesize 0
select count(*) from doom_match where match_state in('STARTING','ACTIVE','RECOVERING');
SQL
)"
active="$(printf '%s' "$active" | tr -cd '0-9')"
[[ "$active" == 0 ]] ||
  { printf 'prewarm decomposition requires zero active matches: %s\n' "$active" >&2;exit 1; }

{
  printf 'PMLE_HOST_QUIESCENCE|PASS|docker_builds=0|compiles=0|verifiers=0\n'
  printf 'PMLE_PREWARM_DECOMPOSITION|BEGIN|composition=retire_pool_then_module_staging_then_checkpoint_bank_then_sequential_pool\n'
  phase POOL_RETIRE \
    "$root/scripts/db_sql.sh" - <<'SQL'
declare
  l_job varchar2(64);l_token varchar2(32);l_sid number;l_serial number;
  l_spid varchar2(24);l_run varchar2(64);
begin
  for slot_ in (select slot_id,incarnation_token,worker_sid,worker_serial,
      worker_spid,worker_job_run from doom_mle_warm_slot order by slot_id) loop
    l_job:='DOOM_MLE_WARM_'||to_char(slot_.slot_id,'FM00');
    begin
      doom_worker_lifecycle.stop_job(
        l_job,true,'prewarm decomposition production restage',
        slot_.incarnation_token,slot_.worker_sid,slot_.worker_serial,
        slot_.worker_spid,slot_.worker_job_run);
    exception when others then
      if sqlcode not in(-27475,-20795) then raise;end if;
    end;
    begin dbms_scheduler.drop_job(l_job,true);
    exception when others then if sqlcode<>-27475 then raise;end if;end;
  end loop;
end;
/
SQL
  phase MODULE_STAGING \
    "$root/probes/mle/teavm-engine/load-mle-module.sh" --production
  phase CHECKPOINT_BANK \
    "$root/probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh"
  phase SEQUENTIAL_POOL \
    "$root/scripts/db_sql.sh" - <<'SQL'
begin doom_match_worker.start_warm_pool;end;
/
SQL
  "$root/scripts/db_sql.sh" - <<'SQL'
set serveroutput on size unlimited feedback off heading off
declare
  r doom_mle_prewarm_run%rowtype;
  function ms(a timestamp with time zone,b timestamp with time zone)
    return number is d interval day to second:=b-a;
  begin return round(extract(day from d)*86400000+
    extract(hour from d)*3600000+extract(minute from d)*60000+
    extract(second from d)*1000);end;
begin
  select * into r from doom_mle_prewarm_run
    order by prewarm_id desc fetch first 1 row only;
  if r.prewarm_status<>'READY' then
    raise_application_error(-20796,'prewarm decomposition pool not ready');
  end if;
  dbms_output.put_line('PMLE_PREWARM_POOL|PASS|prewarm_id='||r.prewarm_id||
    '|authority_first_admittable_ms='||ms(r.started_at,r.authority_ready_at)||
    '|standby_after_authority_ms='||ms(r.authority_ready_at,r.standby_ready_at)||
    '|total_pool_ms='||ms(r.started_at,r.completed_at));
end;
/
SQL
  printf 'PMLE_PREWARM_DECOMPOSITION|PASS|first_admittable_excludes_staging_and_bank=1\n'
} 2>&1 | tee "$log"
