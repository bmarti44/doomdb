whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_a varchar2(32);l_b varchar2(32);l_payload blob;l_request varchar2(32);
  l_ready number;l_deadline timestamp with time zone;l_plain blob;
  l_a_sha varchar2(64);l_b_sha varchar2(64);l_rows number;l_slots number;

  function command_json(p_seq number,p_turn number) return clob is
  begin
    return '{"v":1,"commands":[{"seq":'||p_seq||',"turn":'||p_turn||
      ',"forward":1,"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,'||
      '"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
  end;

  function await_sha(p_session varchar2,p_seq number) return varchar2 is
  begin
    l_deadline:=systimestamp+numtodsinterval(30,'SECOND');
    loop
      doom_api.poll_frame(p_session,p_seq,100,l_ready,l_payload);
      exit when l_ready=1;
      if systimestamp>=l_deadline then
        raise_application_error(-20000,'concurrent frame timeout');
      end if;
    end loop;
    l_plain:=doom_mocha_payload_plain(l_payload);
    return utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75));
  end;

  procedure stop_one(p_session varchar2) is
  begin
    if p_session is not null then
      update doom_worker_control set stop_requested=1
        where target_session=p_session;
    end if;
  end;

  procedure cleanup is
    l_active number;
  begin
    stop_one(l_a);stop_one(l_b);commit;
    l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
    loop
      select count(*) into l_active from doom_worker_control
        where target_session in(l_a,l_b);
      exit when l_active=0 or systimestamp>=l_deadline;
      dbms_session.sleep(.1);
    end loop;
    if l_a is not null then delete from game_sessions where session_token=l_a;end if;
    if l_b is not null then delete from game_sessions where session_token=l_b;end if;
    update doom_config set text_value='SQL' where config_key='GAME_ENGINE';commit;
  end;
begin
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;
  doom_api.new_game(3,l_a,l_payload);doom_api.new_game(3,l_b,l_payload);
  -- First submissions claim two distinct retained Scheduler sessions.
  doom_api.submit_step(l_a,command_json(1,0),l_request);
  doom_api.submit_step(l_b,command_json(1,0),l_request);
  for l_seq in 2..30 loop
    doom_api.submit_step(l_a,command_json(l_seq,0),l_request);
    doom_api.submit_step(l_b,command_json(l_seq,0),l_request);
  end loop;
  l_a_sha:=await_sha(l_a,30);l_b_sha:=await_sha(l_b,30);
  if l_a_sha<>l_b_sha then
    raise_application_error(-20000,'identical concurrent sessions diverged');
  end if;
  select count(distinct worker_slot) into l_slots from doom_worker_control
    where target_session in(l_a,l_b) and ready=1;
  select count(*) into l_rows from doom_mocha_command
    where session_token in(l_a,l_b);
  if l_slots<>2 or l_rows<>60 then
    raise_application_error(-20000,'concurrent ownership/ledger mismatch');
  end if;

  doom_api.submit_step(l_a,command_json(31,1),l_request);
  doom_api.submit_step(l_b,command_json(31,-1),l_request);
  l_a_sha:=await_sha(l_a,31);l_b_sha:=await_sha(l_b,31);
  if l_a_sha=l_b_sha then
    raise_application_error(-20000,'divergent concurrent inputs cross-talk');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-CONCURRENT sessions=2 workers=2'||
    ' exactRows=62 isolatedFinalFrames=1');
  cleanup;
exception when others then cleanup;raise;
end;
/
