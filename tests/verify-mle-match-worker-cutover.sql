whenever sqlerror exit failure rollback
set define off serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_p0 varchar2(64);l_p1 varchar2(64);l_state varchar2(32);l_slot number;
  l_epoch number;l_generation number;l_tic number;l_accepted number;
  l_ready number;l_frontier number;l_payload blob;l_count number;
  l_state32 varchar2(64);l_checkpoint_sha varchar2(64);l_checkpoint_bytes number;
  l_job varchar2(64);l_error varchar2(2000);l_old_mode varchar2(16);
  l_chain32 varchar2(64);l_chain33_previous varchar2(64);
  l_started timestamp with time zone;l_start_ms number;l_recovery_ms number;
  l_standby_ms number;l_standby_status varchar2(16);l_standby_job varchar2(64);
  l_db_state varchar2(16);l_public_state varchar2(16);l_mode varchar2(16);
  l_skill number;l_episode number;l_map number;l_max_players number;
  l_member_count number;l_ready_count number;l_requester_slot number;
  l_public_epoch number;l_public_generation number;l_public_tic number;
  l_worker_mode varchar2(16);l_rejected number:=0;

  function elapsed_ms(p_started timestamp with time zone) return number is
    l_elapsed interval day to second:=systimestamp-p_started;
  begin
    return round(extract(day from l_elapsed)*86400000+
      extract(hour from l_elapsed)*3600000+
      extract(minute from l_elapsed)*60000+
      extract(second from l_elapsed)*1000,3);
  end;

  procedure cleanup is
    l_generation number;
  begin
    if l_match is not null then
      begin
        select generation,job_name into l_generation,l_job
          from doom_match_worker_control where match_id=l_match;
        begin doom_match_worker.stop_match(l_match,l_generation);exception when others then null;end;
        begin dbms_scheduler.stop_job(l_job,true);exception when others then null;end;
        begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
      exception when no_data_found then null;end;
      begin
        select job_name into l_standby_job from doom_match_standby_control
          where match_id=l_match;
        begin
          update doom_match_standby_control set stop_requested=1
            where match_id=l_match;commit;
          dbms_scheduler.stop_job(l_standby_job,true);
        exception when others then null;end;
        begin dbms_scheduler.drop_job(l_standby_job,true);exception when others then null;end;
      exception when no_data_found then null;end;
      delete from doom_match where match_id=l_match;
    end if;
    if l_old_mode is not null then
      update doom_config set text_value=l_old_mode
        where config_key='MATCH_WORKER_MODE';
    end if;
    commit;
  end;

  procedure wait_for_tic(p_tic number,p_generation number) is
  begin
    for attempt in 1..3000 loop
      select current_tic into l_tic from doom_match where match_id=l_match;
      exit when l_tic>=p_tic;
      select last_error into l_error from doom_match_worker_control
        where match_id=l_match and generation=p_generation;
      if l_error is not null then
        raise_application_error(-20799,'MLE worker failed: '||l_error);
      end if;
      dbms_session.sleep(.01);
    end loop;
    if l_tic<>p_tic then
      raise_application_error(-20799,'MLE worker tic timeout expected='||p_tic||
        ' actual='||l_tic);
    end if;
  end;

  procedure submit_vector(p_tic number,p_generation number) is
  begin
    doom_match_worker.submit_command(l_match,0,l_epoch,p_generation,p_tic,p_tic,
      hextoraw(case when mod(p_tic,2)=0 then '0800000000000000'
                    else '0001000000000000' end),l_accepted);
    if l_accepted<>1 then raise_application_error(-20799,'slot0 submit');end if;
    doom_match_worker.submit_command(l_match,1,l_epoch,p_generation,p_tic,p_tic,
      hextoraw(case when mod(p_tic,3)=0 then '00F8000000000000'
                    else '0000000000000000' end),l_accepted);
    if l_accepted<>1 then raise_application_error(-20799,'slot1 submit');end if;
    wait_for_tic(p_tic,p_generation);
  end;
begin
  select text_value into l_old_mode from doom_config
    where config_key='MATCH_WORKER_MODE' for update;
  update doom_config set text_value='LOCKSTEP'
    where config_key='MATCH_WORKER_MODE';
  commit;

  doom_api.create_match('COOP',3,1,1,'MLE_CUTOVER_0',
    l_match,l_host,l_join,l_p0);
  l_p1:=null;
  doom_api.join_match(l_match,l_join,'MLE_CUTOVER_1',l_p1,l_slot);
  if l_slot<>1 then raise_application_error(-20799,'guest slot');end if;
  doom_api.ready_match(l_match,l_p0,1,l_state);
  l_started:=systimestamp;
  doom_api.ready_match(l_match,l_p1,1,l_state);
  -- The authority may publish tic zero internally before its recovery context
  -- finishes warming. That interval must remain publicly STARTING and closed
  -- to commands; otherwise the advertised warm-recovery SLA has a cold hole.
  for attempt in 1..750 loop
    select m.match_state,c.worker_status
      into l_db_state,l_state
      from doom_match m join doom_match_worker_control c
        on c.match_id=m.match_id and c.generation=1
      where m.match_id=l_match;
    exit when l_db_state='ACTIVE' and l_state='STARTING';
    if l_state='FAILED' then exit;end if;
    dbms_session.sleep(.2);
  end loop;
  if l_db_state<>'ACTIVE' or l_state<>'STARTING' then
    raise_application_error(-20799,'initial standby window not observed');
  end if;
  doom_api.match_status(l_match,l_p0,l_public_state,l_mode,l_skill,l_episode,
    l_map,l_max_players,l_member_count,l_ready_count,l_requester_slot,
    l_public_epoch,l_public_generation,l_public_tic,l_worker_mode);
  if l_public_state<>'STARTING' or l_public_generation<>1 or l_public_tic<>0 then
    raise_application_error(-20799,'public admission fence');
  end if;
  begin
    doom_match_worker.submit_command(l_match,0,l_public_epoch,1,1,1,
      hextoraw('0000000000000000'),l_accepted);
  exception when others then
    if sqlcode=-20731 and instr(sqlerrm,'worker is not ready')>0 then
      l_rejected:=1;rollback;
    else raise;end if;
  end;
  if l_rejected<>1 then
    raise_application_error(-20799,'pre-admission command was accepted');
  end if;
  for attempt in 1..1200 loop
    exit when l_state='ACTIVE';
    select case when worker_status='READY' then 'ACTIVE'
                when worker_status='FAILED' then 'FAILED'
                else 'STARTING' end,
           last_error
      into l_state,l_error
      from doom_match_worker_control where match_id=l_match;
    exit when l_state in('ACTIVE','FAILED');
    dbms_session.sleep(.2);
  end loop;
  if l_state<>'ACTIVE' then
    raise_application_error(-20799,
      'MLE worker did not complete standby-gated admission: '||
      l_state||' '||l_error);
  end if;
  l_start_ms:=elapsed_ms(l_started);
  select membership_epoch,generation,current_tic into l_epoch,l_generation,l_tic
    from doom_match where match_id=l_match;
  if l_generation<>1 or l_tic<>0 then
    raise_application_error(-20799,'initial MLE frontier');
  end if;
  select count(*) into l_count from doom_match_tic
    where match_id=l_match and tic=0 and generation=1;
  if l_count<>1 then raise_application_error(-20799,'MLE tic zero absent');end if;
  select count(*) into l_count from doom_match_frame where match_id=l_match;
  if l_count<>0 then
    raise_application_error(-20799,'legacy live frame path remains reachable');
  end if;

  for tic_ in 1..32 loop submit_vector(tic_,1);end loop;
  select state_sha into l_state32 from doom_match_tic
    where match_id=l_match and tic=32;
  select checkpoint_sha,checkpoint_bytes into l_checkpoint_sha,l_checkpoint_bytes
    from doom_match_checkpoint where match_id=l_match and tic=32;
  if l_checkpoint_bytes<1000 or
     not regexp_like(l_checkpoint_sha,'^[0-9a-f]{64}$') then
    raise_application_error(-20799,'DMC1 checkpoint invalid');
  end if;
  select count(*) into l_count from doom_match_transition where match_id=l_match;
  if l_count<>32 then raise_application_error(-20799,'DMD1 transition count');end if;
  select chain_sha into l_chain32 from doom_match_transition
    where match_id=l_match and tic=32;

  doom_api.poll_match_transitions(l_match,l_p0,0,0,64,
    l_ready,l_frontier,l_payload);
  if l_ready<>1 or l_frontier<>32 or
     utl_raw.cast_to_varchar2(dbms_lob.substr(l_payload,4,1))<>'DMB1' then
    raise_application_error(-20799,'DMB1 public batch');
  end if;

  l_started:=systimestamp;l_standby_status:=null;
  for attempt in 1..900 loop
    select standby_status,last_error into l_standby_status,l_error
      from doom_match_standby_control where match_id=l_match;
    exit when l_standby_status in('READY','FAILED');
    dbms_session.sleep(.2);
  end loop;
  l_standby_ms:=elapsed_ms(l_started);
  if l_standby_status<>'READY' then
    raise_application_error(-20799,'MLE standby failed: '||l_error);
  end if;

  select job_name into l_job from doom_match_worker_control where match_id=l_match;
  begin dbms_scheduler.stop_job(l_job,true);exception when others then null;end;
  begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
  l_started:=systimestamp;
  doom_match_worker.recover_match(l_match,180000,l_state);
  if l_state<>'ACTIVE' then
    raise_application_error(-20799,'MLE checkpoint recovery did not start');
  end if;
  l_recovery_ms:=elapsed_ms(l_started);
  if l_recovery_ms>30000 then
    raise_application_error(-20799,'warm recovery SLA ms='||l_recovery_ms);
  end if;
  select generation,current_tic into l_generation,l_tic
    from doom_match where match_id=l_match;
  if l_generation<>2 or l_tic<>32 then
    raise_application_error(-20799,'recovery frontier');
  end if;
  select count(*) into l_count from doom_match_tic
    where match_id=l_match and tic=32 and generation=2 and state_sha=l_state32;
  if l_count<>1 then raise_application_error(-20799,'recovered state identity');end if;

  submit_vector(33,2);
  select previous_chain_sha into l_chain33_previous
    from doom_match_transition where match_id=l_match and tic=33;
  if l_chain33_previous<>l_chain32 then
    raise_application_error(-20799,'DMD1 recovery chain discontinuity');
  end if;
  select count(*) into l_count from doom_match_transition
    where match_id=l_match and tic=33 and generation=2;
  if l_count<>1 then raise_application_error(-20799,'generation-2 transition');end if;
  select count(*) into l_count from doom_match_frame where match_id=l_match;
  if l_count<>0 then raise_application_error(-20799,'OJVM frame rows after recovery');end if;

  dbms_output.put_line('PMLE_WORKER_CUTOVER|PASS|tics=33|checkpoint_tic=32|'||
    'recovery_generation=2|dmd1=33|legacy_frames=0|engine=MLE|'||
    'public_admission=STANDBY_READY|pre_admission_command=REJECTED|'||
    'cold_start_ms='||l_start_ms||'|standby_wait_ms='||l_standby_ms||
    '|warm_recovery_ms='||l_recovery_ms);
  cleanup;
exception when others then
  l_error:=sqlerrm;cleanup;raise_application_error(-20799,l_error);
end;
/
