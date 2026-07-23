whenever sqlerror exit failure rollback
set define off

-- One gateway owns Scheduler stops and retained-session reconciliation.
-- Callers may request work or stop intent; only RUN_WARM_SLOT and this
-- bounded janitor write DOOM_MLE_WARM_SLOT lifecycle state.
create or replace package doom_worker_lifecycle authid definer as
  procedure prepare_launch(
    p_slot in number,p_job_name in varchar2,p_incarnation out varchar2);
  procedure claim_ready_slot(
    p_match in varchar2,p_role in varchar2,p_slot out number,
    p_job_name out varchar2);
  procedure accept_assignment(
    p_slot in number,p_incarnation in varchar2,p_sid in number,
    p_serial in number,p_spid in varchar2,p_job_run in varchar2,
    p_assignment out number,p_match out varchar2,p_role out varchar2);
  procedure finish_assignment(
    p_assignment in number,p_status in varchar2,
    p_detail in varchar2 default null);
  function pending_stop(
    p_slot in number,p_incarnation in varchar2,p_sid in number,
    p_serial in number,p_spid in varchar2,p_job_run in varchar2)
    return number;
  procedure honor_stop(p_intent in number,p_detail in varchar2);
  procedure stop_job(
    p_job_name in varchar2,p_force in boolean,p_reason in varchar2,
    p_expected_incarnation in varchar2 default null,
    p_expected_sid in number default null,p_expected_serial in number default null,
    p_expected_spid in varchar2 default null,
    p_expected_job_run in varchar2 default null);
  procedure reconcile_warm_slots;
end doom_worker_lifecycle;
/

create or replace package body doom_worker_lifecycle as
  c_error constant pls_integer:=-20771;
  c_stop_wait_tenths constant pls_integer:=50;

  function requestor return varchar2 is
  begin
    return substr(sys_context('USERENV','SESSION_USER')||':'||
      nvl(sys_context('USERENV','MODULE'),'NO_MODULE')||':'||
      nvl(sys_context('USERENV','ACTION'),'NO_ACTION'),1,128);
  end;

  procedure reject_assignment(p_slot number,p_detail varchar2) is
  begin
    update doom_mle_warm_assignment set assignment_status='REJECTED',
      finished_at=localtimestamp at time zone 'UTC',failure_detail=substr(p_detail,1,2000)
      where slot_id=p_slot and assignment_status in('PENDING','ACCEPTED');
  end;

  procedure reconcile_warm_slots is
    l_count number;l_serial number;l_spid varchar2(24);l_running number;
  begin
    for slot_ in (
      select slot_id,job_name,slot_status,incarnation_token,worker_sid,
        worker_serial,worker_spid,worker_job_run
      from doom_mle_warm_slot
      where slot_status in('WARMING','READY','CLAIMED','RUNNING')
      for update skip locked
    ) loop
      l_count:=0;l_serial:=null;l_spid:=null;l_running:=0;
      if slot_.worker_sid is not null then
        begin
          select s.serial#,p.spid into l_serial,l_spid
          from v$session s join v$process p on p.addr=s.paddr
          where s.sid=slot_.worker_sid;
          l_count:=1;
        exception when no_data_found then l_count:=0;end;
      end if;
      select count(*) into l_running from user_scheduler_running_jobs
        where job_name=slot_.job_name and session_id=slot_.worker_sid;
      if slot_.incarnation_token is null or slot_.worker_serial is null or
         slot_.worker_spid is null or slot_.worker_job_run is null or
         l_count<>1 or l_running<>1 or l_serial<>slot_.worker_serial or
         l_spid<>slot_.worker_spid then
        reject_assignment(slot_.slot_id,'janitor incarnation mismatch');
        update doom_mle_warm_slot set slot_status='FAILED',
          assigned_match=null,assigned_role=null,worker_sid=null,
          worker_serial=null,worker_spid=null,worker_job_run=null,
          incarnation_token=null,stop_requested=0,heartbeat=localtimestamp at time zone 'UTC',
          last_error='janitor: scheduler/session incarnation mismatch'
          where slot_id=slot_.slot_id
            and nvl(incarnation_token,'-')=
                nvl(slot_.incarnation_token,'-');
      end if;
    end loop;
    commit;
  end;

  procedure prepare_launch(
    p_slot in number,p_job_name in varchar2,p_incarnation out varchar2
  ) is
    l_status varchar2(16);
  begin
    if p_slot not in(1,2) or
       p_job_name<>'DOOM_MLE_WARM_'||to_char(p_slot,'FM00') then
      raise_application_error(c_error,'invalid warm launch');
    end if;
    reconcile_warm_slots;
    select slot_status into l_status from doom_mle_warm_slot
      where slot_id=p_slot for update;
    if l_status not in('STOPPED','FAILED') then
      raise_application_error(c_error,'warm slot is not launchable');
    end if;
    p_incarnation:=lower(rawtohex(dbms_crypto.randombytes(16)));
    merge into doom_mle_warm_launch d using (
      select p_slot slot_id from dual
    ) s on(d.slot_id=s.slot_id)
    when matched then update set job_name=p_job_name,
      incarnation_token=p_incarnation,requested_at=localtimestamp at time zone 'UTC',
      launch_status='REQUESTED'
    when not matched then insert(
      slot_id,job_name,incarnation_token,requested_at,launch_status)
      values(p_slot,p_job_name,p_incarnation,localtimestamp at time zone 'UTC','REQUESTED');
    commit;
  end;

  procedure claim_ready_slot(
    p_match in varchar2,p_role in varchar2,p_slot out number,
    p_job_name out varchar2
  ) is
    l_token varchar2(32);l_sid number;l_serial number;l_spid varchar2(24);
    l_run varchar2(64);
  begin
    p_slot:=0;p_job_name:=null;
    if not regexp_like(p_match,'^[0-9a-f]{32}$') or
       p_role not in('AUTHORITY','STANDBY') then
      raise_application_error(c_error,'invalid warm assignment');
    end if;
    for slot_ in (
      select s.slot_id,s.job_name,s.incarnation_token,s.worker_sid,
        s.worker_serial,s.worker_spid,s.worker_job_run
      from doom_mle_warm_slot s
      where s.slot_status='READY' and s.stop_requested=0
        and exists(
          select 1 from user_scheduler_running_jobs r
          where r.job_name=s.job_name and r.session_id=s.worker_sid)
        and not exists(
          select 1 from doom_mle_warm_assignment a
          where a.slot_id=s.slot_id
            and a.assignment_status in('PENDING','ACCEPTED'))
      order by s.slot_id
      for update of s.slot_status skip locked
    ) loop
      p_slot:=slot_.slot_id;p_job_name:=slot_.job_name;
      l_token:=slot_.incarnation_token;l_sid:=slot_.worker_sid;
      l_serial:=slot_.worker_serial;l_spid:=slot_.worker_spid;
      l_run:=slot_.worker_job_run;
      exit;
    end loop;
    if p_slot=0 then return;end if;
    insert into doom_mle_warm_assignment(
      slot_id,job_name,incarnation_token,worker_sid,worker_serial,worker_spid,
      worker_job_run,match_id,assigned_role,assignment_status,requested_at)
    values(p_slot,p_job_name,l_token,l_sid,l_serial,l_spid,l_run,p_match,p_role,
      'PENDING',localtimestamp at time zone 'UTC');
  end;

  procedure accept_assignment(
    p_slot in number,p_incarnation in varchar2,p_sid in number,
    p_serial in number,p_spid in varchar2,p_job_run in varchar2,
    p_assignment out number,p_match out varchar2,p_role out varchar2
  ) is
  begin
    p_assignment:=0;p_match:=null;p_role:=null;
    for assignment_ in (
      select assignment_id,match_id,assigned_role
      from doom_mle_warm_assignment
      where slot_id=p_slot and assignment_status='PENDING'
        and incarnation_token=p_incarnation and worker_sid=p_sid
        and worker_serial=p_serial and worker_spid=p_spid
        and worker_job_run=p_job_run
      order by assignment_id
      for update skip locked
    ) loop
      p_assignment:=assignment_.assignment_id;
      p_match:=assignment_.match_id;p_role:=assignment_.assigned_role;
      exit;
    end loop;
    if p_assignment=0 then return;end if;
    update doom_mle_warm_assignment set assignment_status='ACCEPTED',
      accepted_at=localtimestamp at time zone 'UTC' where assignment_id=p_assignment
      and assignment_status='PENDING';
    if sql%rowcount<>1 then
      raise_application_error(c_error,'warm assignment accept fence');
    end if;
  end;

  procedure finish_assignment(
    p_assignment in number,p_status in varchar2,
    p_detail in varchar2 default null
  ) is
    l_status varchar2(16);
  begin
    l_status:=case when p_status='FINISHED' then 'FINISHED' else 'FAILED' end;
    update doom_mle_warm_assignment set assignment_status=l_status,
      finished_at=localtimestamp at time zone 'UTC',failure_detail=substr(p_detail,1,2000)
      where assignment_id=p_assignment and assignment_status='ACCEPTED';
    if sql%rowcount<>1 then
      raise_application_error(c_error,'warm assignment finish fence');
    end if;
  end;

  function pending_stop(
    p_slot in number,p_incarnation in varchar2,p_sid in number,
    p_serial in number,p_spid in varchar2,p_job_run in varchar2
  ) return number is
    l_intent number;
  begin
    select intent_id into l_intent from (
      select intent_id from doom_worker_stop_intent
      where slot_id=p_slot and incarnation_token=p_incarnation
        and target_sid=p_sid and target_serial=p_serial
        and target_spid=p_spid and target_job_run=p_job_run
        and intent_status='PENDING'
      order by intent_id
    ) where rownum=1;
    return l_intent;
  exception when no_data_found then return 0;
  end;

  procedure honor_stop(p_intent in number,p_detail in varchar2) is
  begin
    update doom_worker_stop_intent set intent_status='HONORED',
      resolved_at=localtimestamp at time zone 'UTC',resolution_detail=substr(p_detail,1,2000)
      where intent_id=p_intent and intent_status='PENDING';
  end;

  procedure stop_job(
    p_job_name in varchar2,p_force in boolean,p_reason in varchar2,
    p_expected_incarnation in varchar2 default null,
    p_expected_sid in number default null,p_expected_serial in number default null,
    p_expected_spid in varchar2 default null,
    p_expected_job_run in varchar2 default null
  ) is
    l_slot number;l_token varchar2(32);l_sid number;l_serial number;
    l_spid varchar2(24);l_run varchar2(64);l_intent number;l_status varchar2(16);
    l_count number:=0;l_match boolean:=true;l_requestor varchar2(128);
    l_error varchar2(2000);
  begin
    l_requestor:=requestor;
    if p_job_name is null or p_reason is null then
      raise_application_error(c_error,'stop intent requires job and reason');
    end if;
    begin
      select slot_id,incarnation_token,worker_sid,worker_serial,worker_spid,
        worker_job_run,slot_status
      into l_slot,l_token,l_sid,l_serial,l_spid,l_run,l_status
      from doom_mle_warm_slot where job_name=upper(p_job_name) for update;
    exception when no_data_found then
      l_slot:=null;l_token:=null;l_sid:=null;l_serial:=null;l_spid:=null;
      l_run:=null;l_status:=null;
    end;
    -- A legacy or janitor-reset row has no trustworthy incarnation. Treat
    -- its Scheduler job as generic; no slot mutation may be based on a
    -- partial identity tuple.
    if l_status in('STOPPED','FAILED') and l_token is null and l_sid is null
       and l_serial is null and l_spid is null and l_run is null then
      l_slot:=null;
    end if;
    if l_slot is not null then
      l_match:=p_expected_incarnation is not null
        and p_expected_sid is not null and p_expected_serial is not null
        and p_expected_spid is not null and p_expected_job_run is not null
        and p_expected_incarnation=l_token and p_expected_sid=l_sid and
        p_expected_serial=l_serial and p_expected_spid=l_spid and
        p_expected_job_run=l_run;
      if l_match is null or not l_match then
        insert into doom_worker_stop_intent(
          job_name,slot_id,incarnation_token,target_sid,target_serial,target_spid,
          target_job_run,requestor,reason,requested_at,honor_deadline,
          intent_status,resolved_at,resolution_detail)
        values(upper(p_job_name),l_slot,l_token,l_sid,l_serial,l_spid,l_run,
          l_requestor,p_reason,localtimestamp at time zone 'UTC',localtimestamp at time zone 'UTC','REJECTED',localtimestamp at time zone 'UTC',
          'expected incarnation mismatch');
        commit;
        raise_application_error(c_error,'stop incarnation mismatch');
      end if;
    end if;
    insert into doom_worker_stop_intent(
      job_name,slot_id,incarnation_token,target_sid,target_serial,target_spid,
      target_job_run,requestor,reason,requested_at,honor_deadline,intent_status)
    values(upper(p_job_name),l_slot,l_token,l_sid,l_serial,l_spid,l_run,
      l_requestor,p_reason,localtimestamp at time zone 'UTC',localtimestamp at time zone 'UTC'+numtodsinterval(5,'SECOND'),'PENDING')
    returning intent_id into l_intent;
    commit;
    if l_slot is null then
      begin
        dbms_scheduler.stop_job(upper(p_job_name),p_force);
        update doom_worker_stop_intent set intent_status='HONORED',
          resolved_at=localtimestamp at time zone 'UTC',resolution_detail='generic scheduler stop'
          where intent_id=l_intent;
      exception when others then
        if sqlcode in(-27475,-27366) then
          update doom_worker_stop_intent set intent_status='STALE',
            resolved_at=localtimestamp at time zone 'UTC',
            resolution_detail='job absent or already stopped'
            where intent_id=l_intent and intent_status='PENDING';
        else
          l_error:=sqlerrm;
          update doom_worker_stop_intent set intent_status='REJECTED',
            resolved_at=localtimestamp at time zone 'UTC',
            resolution_detail=substr(l_error,1,2000)
            where intent_id=l_intent and intent_status='PENDING';
          commit;raise;
        end if;
      end;
      commit;return;
    end if;
    for i in 1..c_stop_wait_tenths loop
      select intent_status into l_status from doom_worker_stop_intent
        where intent_id=l_intent;
      exit when l_status<>'PENDING';
      dbms_session.sleep(.1);
    end loop;
    select intent_status into l_status from doom_worker_stop_intent
      where intent_id=l_intent for update;
    if l_status<>'PENDING' then commit;return;end if;
    if not p_force then
      update doom_worker_stop_intent set intent_status='REJECTED',
        resolved_at=localtimestamp at time zone 'UTC',resolution_detail='intent honor timeout'
        where intent_id=l_intent;
      commit;return;
    end if;
    select count(*) into l_count from doom_mle_warm_slot
      where slot_id=l_slot and incarnation_token=l_token and worker_sid=l_sid
        and worker_serial=l_serial and worker_spid=l_spid
        and worker_job_run=l_run;
    if l_count<>1 then
      update doom_worker_stop_intent set intent_status='STALE',
        resolved_at=localtimestamp at time zone 'UTC',resolution_detail='incarnation changed before force'
        where intent_id=l_intent;
      commit;return;
    end if;
    begin dbms_scheduler.stop_job(upper(p_job_name),true);
    exception when others then if sqlcode<>-27475 then raise;end if;end;
    reject_assignment(l_slot,'forced stop intent '||l_intent);
    update doom_mle_warm_slot set slot_status='STOPPED',
      assigned_match=null,assigned_role=null,worker_sid=null,worker_serial=null,
      worker_spid=null,worker_job_run=null,incarnation_token=null,
      stop_requested=0,heartbeat=localtimestamp at time zone 'UTC',
      last_error='forced lifecycle stop: '||substr(p_reason,1,1900)
      where slot_id=l_slot and incarnation_token=l_token and worker_sid=l_sid
        and worker_serial=l_serial and worker_spid=l_spid
        and worker_job_run=l_run;
    update doom_worker_stop_intent set intent_status='FORCED',
      resolved_at=localtimestamp at time zone 'UTC',resolution_detail='forced after bounded honor timeout'
      where intent_id=l_intent;
    commit;
  end;
end doom_worker_lifecycle;
/
