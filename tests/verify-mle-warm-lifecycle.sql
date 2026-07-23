whenever sqlerror exit failure rollback
set serveroutput on

declare
  l_job constant varchar2(64):='DOOM_MLE_WARM_01';
  l_token varchar2(32);l_sid number;l_serial number;l_spid varchar2(24);
  l_job_run varchar2(64);l_status varchar2(16);l_intent_status varchar2(16);
  l_count number;l_seen number;

  procedure capture_slot is
  begin
    select incarnation_token,worker_sid,worker_serial,worker_spid,worker_job_run
      into l_token,l_sid,l_serial,l_spid,l_job_run
      from doom_mle_warm_slot where slot_id=1;
  end;

  procedure create_sleep_job(p_seconds number) is
  begin
    begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    dbms_scheduler.create_job(
      job_name=>l_job,job_type=>'PLSQL_BLOCK',
      job_action=>'begin dbms_session.sleep('||to_char(p_seconds,'FM9990')||');end;',
      enabled=>true,auto_drop=>false);
    l_seen:=0;
    for i in 1..200 loop
      select count(*) into l_seen from user_scheduler_running_jobs
        where job_name=l_job;
      exit when l_seen=1;
      dbms_session.sleep(.05);
    end loop;
    if l_seen<>1 then
      raise_application_error(-20000,'lifecycle fixture job did not start');
    end if;
    select r.session_id,s.serial#,p.spid
      into l_sid,l_serial,l_spid
      from user_scheduler_running_jobs r
      join v$session s on s.sid=r.session_id
      join v$process p on p.addr=s.paddr
      where r.job_name=l_job;
    l_token:=lower(rawtohex(dbms_crypto.randombytes(16)));
    l_job_run:=l_token||':fixture';
    -- Test fixture only: production slot writes remain confined to
    -- RUN_WARM_SLOT and DOOM_WORKER_LIFECYCLE.
    update doom_mle_warm_slot set slot_status='WARMING',
      assigned_match=null,assigned_role=null,worker_sid=l_sid,
      worker_serial=l_serial,worker_spid=l_spid,worker_job_run=l_job_run,
      incarnation_token=l_token,stop_requested=0,heartbeat=systimestamp,
      last_error=null where slot_id=1;
    commit;
  end;
begin
  select count(*) into l_count from doom_mle_warm_slot
    where slot_id=1 and slot_status='READY'
      and incarnation_token is not null and worker_sid is not null
      and worker_serial is not null and worker_spid is not null
      and worker_job_run is not null;
  if l_count<>1 then
    raise_application_error(-20000,'lifecycle gate requires ready slot 1');
  end if;

  capture_slot;
  begin
    doom_worker_lifecycle.stop_job(
      l_job,true,'lifecycle mismatch rejection gate',
      rpad('0',32,'0'),l_sid,l_serial,l_spid,l_job_run);
    raise_application_error(-20000,'incarnation mismatch was accepted');
  exception when others then
    if sqlcode<>-20771 then raise;end if;
  end;
  select intent_status into l_intent_status from doom_worker_stop_intent
    where intent_id=(select max(intent_id) from doom_worker_stop_intent);
  select count(*) into l_count from user_scheduler_running_jobs
    where job_name=l_job and session_id=l_sid;
  if l_intent_status<>'REJECTED' or l_count<>1 then
    raise_application_error(-20000,'incarnation mismatch gate failed');
  end if;
  dbms_output.put_line(
    'PMLE_WARM_LIFECYCLE|PASS|scenario=incarnation_mismatch_rejected');

  doom_worker_lifecycle.stop_job(
    l_job,true,'lifecycle cooperative intent gate',
    l_token,l_sid,l_serial,l_spid,l_job_run);
  select intent_status into l_intent_status from doom_worker_stop_intent
    where intent_id=(select max(intent_id) from doom_worker_stop_intent);
  select slot_status into l_status from doom_mle_warm_slot where slot_id=1;
  if l_intent_status<>'HONORED' or l_status<>'STOPPED' then
    raise_application_error(-20000,'cooperative stop intent was not honored');
  end if;
  dbms_output.put_line(
    'PMLE_WARM_LIFECYCLE|PASS|scenario=stop_intent_honored');

  create_sleep_job(2);
  dbms_session.sleep(3);
  doom_worker_lifecycle.reconcile_warm_slots;
  select slot_status into l_status from doom_mle_warm_slot where slot_id=1;
  if l_status<>'FAILED' then
    raise_application_error(-20000,'stale row was not reconciled');
  end if;
  select count(*) into l_count from doom_mle_warm_slot where slot_id=1
    and worker_sid is null and worker_serial is null and worker_spid is null
    and worker_job_run is null and incarnation_token is null;
  if l_count<>1 then
    raise_application_error(-20000,'stale row retained partial identity');
  end if;
  dbms_output.put_line(
    'PMLE_WARM_LIFECYCLE|PASS|scenario=stale_row_reconciled');

  create_sleep_job(60);
  doom_worker_lifecycle.stop_job(
    l_job,true,'lifecycle bounded force-reset gate',
    l_token,l_sid,l_serial,l_spid,l_job_run);
  select intent_status into l_intent_status from doom_worker_stop_intent
    where intent_id=(select max(intent_id) from doom_worker_stop_intent);
  select slot_status into l_status from doom_mle_warm_slot where slot_id=1;
  select count(*) into l_count from doom_mle_warm_slot where slot_id=1
    and worker_sid is null and worker_serial is null and worker_spid is null
    and worker_job_run is null and incarnation_token is null;
  if l_intent_status<>'FORCED' or l_status<>'STOPPED' or l_count<>1 then
    raise_application_error(-20000,'bounded force path did not reset slot');
  end if;
  dbms_output.put_line(
    'PMLE_WARM_LIFECYCLE|PASS|scenario=force_path_reset');

  begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
  doom_match_worker.start_warm_pool;
  dbms_output.put_line(
    'PMLE_WARM_LIFECYCLE|PASS|scenarios=4|pool_restored=1');
exception when others then
  begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
  begin doom_match_worker.start_warm_pool;exception when others then null;end;
  raise;
end;
/
