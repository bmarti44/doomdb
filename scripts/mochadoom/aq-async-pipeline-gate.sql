whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_payload blob;l_request varchar2(32);
  l_duplicate varchar2(32);l_ready number;l_deadline timestamp with time zone;
  l_tic number;l_seq number;l_rows number;l_results number;

  function command_json(p_seq number,p_turn number,p_forward number,
    p_strafe number,p_run number,p_fire number) return clob is
  begin
    return '{"v":1,"commands":[{"seq":'||p_seq||',"turn":'||p_turn||
      ',"forward":'||p_forward||',"strafe":'||p_strafe||',"run":'||p_run||
      ',"fire":'||p_fire||',"use":0,"weapon":0,"pause":0,'||
      '"automap":0,"menu":"NONE","cheat":""}]}';
  end;

  procedure await_frame(p_seq number) is
  begin
    l_deadline:=systimestamp+numtodsinterval(30,'SECOND');
    loop
      doom_api.poll_frame(l_session,p_seq,100,l_ready,l_payload);
      exit when l_ready=1;
      if systimestamp>=l_deadline then
        raise_application_error(-20000,'async frame timeout seq='||p_seq);
      end if;
    end loop;
    if utl_raw.cast_to_varchar2(dbms_lob.substr(
         doom_mocha_payload_plain(l_payload),4,1)) not in('DMF3','DMF4') then
      raise_application_error(-20000,'async payload codec mismatch');
    end if;
  end;

  procedure stop_and_clean is
    l_active number;
  begin
    if l_session is not null then
      begin doom_unified_worker.request_stop(l_session);exception when others then null;end;
      l_deadline:=systimestamp+numtodsinterval(8,'SECOND');
      loop
        select count(*) into l_active from doom_worker_control
          where target_session=l_session;
        exit when l_active=0 or systimestamp>=l_deadline;
        dbms_session.sleep(.1);
      end loop;
      delete from game_sessions where session_token=l_session;
    end if;
    update doom_config set text_value='SQL' where config_key='GAME_ENGINE';
    commit;
  end;
begin
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;
  doom_api.new_game(3,l_session,l_payload);

  doom_api.submit_step(l_session,command_json(1,0,1,0,1,1),l_request);
  doom_api.submit_step(l_session,command_json(1,0,1,0,1,1),l_duplicate);
  if l_duplicate<>l_request then
    raise_application_error(-20000,'async duplicate request mismatch');
  end if;
  await_frame(1);

  -- Submit four keyboard-state commands without waiting for their frames.
  for l_command in 2..5 loop
    doom_api.submit_step(l_session,command_json(l_command,
      case when mod(l_command,2)=0 then 1 else -1 end,1,
      case when l_command=4 then 1 else 0 end,1,
      case when l_command=5 then 1 else 0 end),l_request);
  end loop;
  await_frame(5);
  select current_tic,last_command_seq into l_tic,l_seq from game_sessions
    where session_token=l_session;
  select count(*) into l_rows from doom_mocha_command
    where session_token=l_session;
  select count(*) into l_results from doom_worker_request q
    join doom_worker_result r on r.request_id=q.request_id
    where q.session_token=l_session and q.request_status='COMMITTED';
  if l_tic<>5 or l_seq<>5 or l_rows<>5 or l_results<>5 then
    raise_application_error(-20000,'async pipeline frontier mismatch');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-AQ-ASYNC tic=5 seq=5 exactRows=5'||
    ' committedResults=5 finalPayloadBytes='||dbms_lob.getlength(l_payload));
  stop_and_clean;
exception when others then stop_and_clean;raise;
end;
/
