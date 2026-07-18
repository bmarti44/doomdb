whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_a varchar2(32);l_b varchar2(32);l_payload blob;l_request varchar2(32);
  l_ready number;l_deadline timestamp with time zone;l_plain blob;
  l_a_sha varchar2(64);l_b_sha varchar2(64);l_slot number;l_old_generation number;
  l_new_generation number;l_running number;l_rows number;

  function command_json(p_seq number) return clob is
  begin
    return '{"v":1,"commands":[{"seq":'||p_seq||
      ',"turn":0,"forward":1,"strafe":0,"run":1,"fire":'||
      case when mod(p_seq-1,8)=0 then '1' else '0' end||
      ',"use":0,"weapon":0,"pause":0,"automap":0,'||
      '"menu":"NONE","cheat":""}]}';
  end;

  function await_sha(p_session varchar2,p_seq number) return varchar2 is
  begin
    l_deadline:=systimestamp+numtodsinterval(30,'SECOND');
    loop
      doom_api.poll_frame(p_session,p_seq,100,l_ready,l_payload);
      exit when l_ready=1;
      if systimestamp>=l_deadline then
        raise_application_error(-20000,'crash seam frame timeout');
      end if;
    end loop;
    l_plain:=doom_mocha_payload_plain(l_payload);
    return utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75));
  end;

  procedure cleanup is
    l_active number;
  begin
    update doom_worker_control set stop_requested=1
      where target_session in(l_a,l_b);commit;
    l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
    loop
      select count(*) into l_active from doom_worker_control
        where target_session in(l_a,l_b);
      exit when l_active=0 or systimestamp>=l_deadline;
      dbms_session.sleep(.1);
    end loop;
    -- A force-stopped Scheduler session can leave a deliberately stale READY
    -- row if the restart assertion itself fails. Keep this gate self-cleaning.
    update doom_worker_control c set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null
      where target_session in(l_a,l_b) and not exists(
        select 1 from user_scheduler_running_jobs j where
          j.job_name='DOOM_UNIFIED_WORKER_'||to_char(c.worker_slot,'FM00'));
    if l_a is not null then delete from game_sessions where session_token=l_a;end if;
    if l_b is not null then delete from game_sessions where session_token=l_b;end if;
    update doom_config set text_value='SQL' where config_key='GAME_ENGINE';commit;
  end;
begin
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;
  doom_api.new_game(3,l_a,l_payload);doom_api.new_game(3,l_b,l_payload);
  for l_seq in 1..50 loop
    doom_api.submit_step(l_a,command_json(l_seq),l_request);
    doom_api.submit_step(l_b,command_json(l_seq),l_request);
  end loop;
  l_a_sha:=await_sha(l_a,50);l_b_sha:=await_sha(l_b,50);
  if l_a_sha<>l_b_sha then raise_application_error(-20000,'pre-seam mismatch');end if;
  select worker_slot,generation into l_slot,l_old_generation
    from doom_worker_control where target_session=l_a and ready=1;
  dbms_scheduler.stop_job(
    'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),true);
  l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
  loop
    select count(*) into l_running from user_scheduler_running_jobs
      where job_name='DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00');
    exit when l_running=0 or systimestamp>=l_deadline;
    dbms_session.sleep(.1);
  end loop;

  doom_api.submit_step(l_a,command_json(51),l_request);
  doom_api.submit_step(l_b,command_json(51),l_request);
  l_a_sha:=await_sha(l_a,51);l_b_sha:=await_sha(l_b,51);
  if l_a_sha<>l_b_sha then
    raise_application_error(-20000,'post-crash reconstruction diverged');
  end if;
  select generation into l_new_generation from doom_worker_control
    where target_session=l_a and ready=1;
  select count(*) into l_rows from doom_mocha_command
    where session_token in(l_a,l_b);
  if l_new_generation<=l_old_generation or l_rows<>102 then
    raise_application_error(-20000,'crash generation/ledger mismatch');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-CRASH-RECONSTRUCT oldGeneration='||
    l_old_generation||' newGeneration='||l_new_generation||
    ' commands=102 identicalFrameAfterSeam=1');
  cleanup;
exception when others then cleanup;raise;
end;
/
