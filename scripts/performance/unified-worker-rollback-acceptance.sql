whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Production-skeleton acceptance: default-off rollout plus two simultaneously
-- resident sessions, slot-isolated AQ consumption, idempotent rollback results,
-- ownership fencing and independent generation/restart behavior.

declare
  l_session_one varchar2(32);l_session_two varchar2(32);l_payload blob;
  l_blocked boolean:=false;l_old_capacity number;l_generation number;
  l_ready number;l_error varchar2(4000);
begin
  select number_value into l_old_capacity from doom_config
    where config_key='MAX_ACTIVE_SESSIONS' for update;
  insert into doom_worker_audit(request_id,audit_event,detail)
    values('dddddddddddddddddddddddddddddddd','ACCEPT_CAPACITY',to_char(l_old_capacity));
  update doom_config set number_value=greatest(number_value,512)
    where config_key='MAX_ACTIVE_SESSIONS';
  commit;
  doom_api.new_game(3,l_session_one,l_payload);
  doom_api.new_game(3,l_session_two,l_payload);
  begin
    doom_worker_api.claim(l_session_one,l_generation,l_ready,l_error);
  exception when others then
    if sqlcode=-20720 then l_blocked:=true;else raise;end if;
  end;
  if not l_blocked then
    raise_application_error(-20000,'default-off worker gate did not reject start');
  end if;
  insert into doom_worker_audit(request_id,audit_event,detail)
    values('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1','ACCEPT_SETUP',l_session_one);
  insert into doom_worker_audit(request_id,audit_event,detail)
    values('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2','ACCEPT_SETUP',l_session_two);
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  commit;
  doom_worker_api.claim(l_session_one,l_generation,l_ready,l_error);
  if l_ready<>1 or l_error is not null then
    raise_application_error(-20000,'first public worker claim failed');end if;
  doom_worker_api.claim(l_session_two,l_generation,l_ready,l_error);
  if l_ready<>1 or l_error is not null then
    raise_application_error(-20000,'second public worker claim failed');end if;
end;
/

declare
  l_ready number;l_slots number;l_sids number;l_errors number;
  l_deadline timestamp with time zone:=systimestamp+interval '20' second;
begin
  loop
    select count(*),count(distinct worker_slot),count(distinct worker_sid),
      sum(case when last_error is not null then 1 else 0 end)
      into l_ready,l_slots,l_sids,l_errors
      from doom_worker_control where ready=1;
    if l_errors<>0 then raise_application_error(-20000,'worker pool startup failure');end if;
    exit when l_ready=2 and l_slots=2 and l_sids=2;
    if systimestamp>l_deadline then
      raise_application_error(-20000,'two-worker start timeout');end if;
    dbms_session.sleep(.05);
  end loop;
end;
/

-- Submit both requests without waiting, then resolve by exact duplicate polls.
-- Shared response AQ must correlate each result to the correct request ID.
declare
  s1 varchar2(32);s2 varchar2(32);l1 varchar2(64);l2 varchar2(64);
  g1 number;g2 number;t1 number;t2 number;q1 number;q2 number;
  st1 varchar2(16);st2 varchar2(16);rg number;ct number;cs number;
  dv number;dc number;ds varchar2(64);db blob;pb blob;er varchar2(4000);
  deadline timestamp with time zone:=systimestamp+interval '20' second;
begin
  select max(case when request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1' then detail end),
    max(case when request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2' then detail end)
    into s1,s2 from doom_worker_audit where audit_event='ACCEPT_SETUP';
  select c.target_lineage,c.generation,g.current_tic,g.last_command_seq
    into l1,g1,t1,q1 from doom_worker_control c join game_sessions g
      on g.session_token=c.target_session where c.target_session=s1;
  select c.target_lineage,c.generation,g.current_tic,g.last_command_seq
    into l2,g2,t2,q2 from doom_worker_control c join game_sessions g
      on g.session_token=c.target_session where c.target_session=s2;

  doom_worker_api.step(s1,l1,g1,'11111111111111111111111111111111',
    t1,q1,1,1,hextoraw('01010000'),0,st1,rg,ct,cs,dv,dc,ds,db,pb,er);
  doom_worker_api.step(s2,l2,g2,'22222222222222222222222222222222',
    t2,q2,1,1,hextoraw('01020000'),0,st2,rg,ct,cs,dv,dc,ds,db,pb,er);
  loop
    doom_worker_api.step(s1,l1,g1,'11111111111111111111111111111111',
      t1,q1,1,1,hextoraw('01010000'),1,st1,rg,ct,cs,dv,dc,ds,db,pb,er);
    doom_worker_api.step(s2,l2,g2,'22222222222222222222222222222222',
      t2,q2,1,1,hextoraw('01020000'),1,st2,rg,ct,cs,dv,dc,ds,db,pb,er);
    exit when st1='ROLLED_BACK' and st2='ROLLED_BACK';
    if systimestamp>deadline then
      raise_application_error(-20000,'two-session response timeout');end if;
  end loop;

  declare
    at1 number;at2 number;aq1 number;aq2 number;slot_count number;
    event_count number;
  begin
    select current_tic,last_command_seq into at1,aq1 from game_sessions
      where session_token=s1;
    select current_tic,last_command_seq into at2,aq2 from game_sessions
      where session_token=s2;
    select count(distinct worker_slot) into slot_count from doom_worker_request
      where request_id in('11111111111111111111111111111111',
        '22222222222222222222222222222222');
    select count(*) into event_count from doom_worker_audit
      where request_id in('11111111111111111111111111111111',
        '22222222222222222222222222222222') and audit_event='ROLLBACK_ONLY';
    if at1<>t1 or aq1<>q1 or at2<>t2 or aq2<>q2 or
       slot_count<>2 or event_count<>2 then
      raise_application_error(-20000,'two-session rollback isolation failure');
    end if;
  end;

  -- A valid session token with another worker's unguessable lineage is rejected
  -- before a durable request or queue message can be created.
  begin
    doom_worker_api.step(s1,l2,g1,'33333333333333333333333333333333',
      t1,q1,1,1,hextoraw('01030000'),0,st1,rg,ct,cs,dv,dc,ds,db,pb,er);
    raise_application_error(-20000,'cross-session ownership accepted');
  exception when others then
    if sqlcode<>-20721 then raise;end if;
  end;
  dbms_output.put_line('unified_worker_default_off=PASS');
  dbms_output.put_line('unified_worker_two_session_isolation=PASS');
  dbms_output.put_line('unified_worker_response_correlation=PASS');
end;
/

-- Restart only session one. Session two must retain its independent generation
-- and continue serving requests throughout the other slot's reconstruction.
declare s1 varchar2(32);slot1 number;generation1 number;
begin
  select detail into s1 from doom_worker_audit
    where request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1'
      and audit_event='ACCEPT_SETUP';
  select worker_slot,generation into slot1,generation1 from doom_worker_control
    where target_session=s1;
  update doom_worker_audit set worker_slot=slot1,generation=generation1
    where request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1'
      and audit_event='ACCEPT_SETUP';
  commit;
  doom_unified_worker.request_stop(s1);
end;
/
declare
  s1 varchar2(32);slot1 number;running_ number;owned_ number;
  deadline timestamp with time zone:=systimestamp+interval '15' second;
begin
  select detail,worker_slot into s1,slot1 from doom_worker_audit
    where request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1'
      and audit_event='ACCEPT_SETUP';
  loop
    select count(*) into owned_ from doom_worker_control where target_session=s1;
    select count(*) into running_ from user_scheduler_running_jobs
      where job_name='DOOM_UNIFIED_WORKER_'||to_char(slot1,'FM00');
    exit when owned_=0 and running_=0;
    if systimestamp>deadline then raise_application_error(-20000,'single stop timeout');end if;
    dbms_session.sleep(.05);
  end loop;
  declare generation_ number;ready_ number;error_ varchar2(4000);begin
    doom_worker_api.claim(s1,generation_,ready_,error_);
    if ready_<>1 or error_ is not null then
      raise_application_error(-20000,'public worker reclaim failed');end if;
  end;
end;
/

declare
  s1 varchar2(32);s2 varchar2(32);g1_old number;g1_new number;g2 number;
  g2_now number;ready2 number;l1 varchar2(64);t1 number;q1 number;
  st varchar2(16);rg number;ct number;cs number;dv number;dc number;
  ds varchar2(64);db blob;pb blob;er varchar2(4000);blocked boolean:=false;
  deadline timestamp with time zone:=systimestamp+interval '20' second;
begin
  select max(case when request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1' then detail end),
    max(case when request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2' then detail end)
    into s1,s2 from doom_worker_audit where audit_event='ACCEPT_SETUP';
  select generation into g1_old from doom_worker_audit
    where request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1'
      and audit_event='ACCEPT_SETUP';
  select generation into g2 from doom_worker_control where target_session=s2;
  loop
    select count(*) into g1_new from doom_worker_control
      where target_session=s1 and ready=1 and generation>g1_old;
    exit when g1_new=1;
    if systimestamp>deadline then raise_application_error(-20000,'single restart timeout');end if;
    dbms_session.sleep(.05);
  end loop;
  select c.generation,c.target_lineage,g.current_tic,g.last_command_seq
    into g1_new,l1,t1,q1 from doom_worker_control c join game_sessions g
      on g.session_token=c.target_session where c.target_session=s1;
  select generation,ready into g2_now,ready2 from doom_worker_control
    where target_session=s2;
  if g2_now<>g2 or ready2<>1 then
    raise_application_error(-20000,'unrelated worker generation changed');end if;
  -- A lost terminal response remains replayable from the durable ledger even
  -- though the session's live worker generation has advanced.
  doom_worker_api.step(s1,l1,g1_old,'11111111111111111111111111111111',
    t1,q1,1,1,hextoraw('01010000'),10,st,rg,ct,cs,dv,dc,ds,db,pb,er);
  if st<>'ROLLED_BACK' or rg<>g1_old then
    raise_application_error(-20000,'terminal cross-generation replay failed');end if;
  begin
    doom_worker_api.step(s1,l1,g1_old,'44444444444444444444444444444444',
      t1,q1,1,1,hextoraw('01040000'),0,st,rg,ct,cs,dv,dc,ds,db,pb,er);
  exception when others then
    if sqlcode=-20721 then blocked:=true;else raise;end if;
  end;
  if not blocked then raise_application_error(-20000,'stale generation accepted');end if;
  doom_worker_api.step(s1,l1,g1_new,'55555555555555555555555555555555',
    t1,q1,1,1,hextoraw('01050000'),10,st,rg,ct,cs,dv,dc,ds,db,pb,er);
  if st<>'ROLLED_BACK' or rg<>g1_new then
    raise_application_error(-20000,'restarted worker response mismatch');end if;
  dbms_output.put_line('unified_worker_independent_generation=PASS');
  dbms_output.put_line('unified_worker_terminal_replay=PASS');
  dbms_output.put_line('unified_worker_restart_fence=PASS');
end;
/

begin doom_unified_worker.request_stop_all;end;
/
declare
  running_ number;ready_ number;s1 varchar2(32);s2 varchar2(32);old_capacity number;
  deadline timestamp with time zone:=systimestamp+interval '15' second;
begin
  loop
    select count(*) into running_ from user_scheduler_running_jobs
      where job_name like 'DOOM_UNIFIED_WORKER___';
    select count(*) into ready_ from doom_worker_control where ready=1;
    exit when running_=0 and ready_=0;
    if systimestamp>deadline then raise_application_error(-20000,'pool stop timeout');end if;
    dbms_session.sleep(.05);
  end loop;
  select max(case when request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1' then detail end),
    max(case when request_id='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2' then detail end),
    to_number(max(case when request_id='dddddddddddddddddddddddddddddddd' then detail end))
    into s1,s2,old_capacity from doom_worker_audit
    where audit_event in('ACCEPT_SETUP','ACCEPT_CAPACITY');
  delete from game_sessions where session_token in(s1,s2);
  delete from doom_worker_audit
    where request_id is null and detail in(s1,s2);
  delete from doom_worker_audit where request_id in(
    'dddddddddddddddddddddddddddddddd','eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1',
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee2','11111111111111111111111111111111',
    '22222222222222222222222222222222','33333333333333333333333333333333',
    '44444444444444444444444444444444','55555555555555555555555555555555');
  update doom_worker_control set target_session=null,target_lineage=null,ready=0,
    stop_requested=0,worker_sid=null,last_error=null;
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=old_capacity where config_key='MAX_ACTIVE_SESSIONS';
  commit;
end;
/
