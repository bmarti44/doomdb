whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_payload blob;l_saved_payload blob;
  l_saved_state varchar2(64);l_saved_frame varchar2(64);l_loaded_frame varchar2(64);
  l_old_lineage varchar2(64);l_new_lineage varchar2(64);l_tic number;
  l_payload_tic number;
  l_seq number;l_count number;l_active number;l_deadline timestamp with time zone;
  l_replay varchar2(32);l_replay_payload blob;

  function command_json(p_seq number,p_turn number,p_fire number) return clob is
  begin
    return '{"v":1,"commands":[{"seq":'||p_seq||',"turn":'||p_turn||
      ',"forward":1,"strafe":0,"run":1,"fire":'||p_fire||
      ',"use":0,"weapon":0,"pause":0,"automap":0,'||
      '"menu":"NONE","cheat":""}]}';
  end;
  function frame_sha(p_payload blob) return varchar2 is l_plain blob;begin
    l_plain:=doom_mocha_payload_plain(p_payload);
    return utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75));
  end;
  function frame_tic(p_payload blob) return number is l_plain blob;begin
    l_plain:=doom_mocha_payload_plain(p_payload);
    return to_number(rawtohex(dbms_lob.substr(l_plain,4,5)),'XXXXXXXX');
  end;
  procedure cleanup is
  begin
    if l_session is not null then
      update doom_worker_control set stop_requested=1
        where target_session=l_session;commit;
      l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
      loop
        select count(*) into l_active from doom_worker_control
          where target_session=l_session;
        exit when l_active=0 or systimestamp>=l_deadline;
        dbms_session.sleep(.1);
      end loop;
      delete from game_sessions where session_token=l_session;
    end if;
    update doom_config set text_value='SQL' where config_key='GAME_ENGINE';commit;
  end;
begin
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;
  doom_api.new_game(3,l_session,l_payload);
  for i in 1..24 loop
    doom_api.step(l_session,command_json(i,0,case when mod(i-1,8)=0 then 1 else 0 end),l_payload);
  end loop;
  dbms_lob.createtemporary(l_saved_payload,true,dbms_lob.call);
  dbms_lob.copy(l_saved_payload,l_payload,dbms_lob.getlength(l_payload));
  l_saved_frame:=frame_sha(l_payload);
  select save_lineage into l_old_lineage from game_sessions
    where session_token=l_session;
  doom_api.save_game(l_session,7,l_saved_state);
  for i in 25..34 loop
    doom_api.step(l_session,command_json(i,1,0),l_payload);
  end loop;
  doom_api.load_game(l_session,7,l_payload);
  l_loaded_frame:=frame_sha(l_payload);l_payload_tic:=frame_tic(l_payload);
  select save_lineage,current_tic,last_command_seq
    into l_new_lineage,l_tic,l_seq from game_sessions
    where session_token=l_session;
  if l_new_lineage=l_old_lineage or l_tic<>24 or l_payload_tic<>24 or l_seq<>34 or
     l_loaded_frame<>l_saved_frame or
     dbms_lob.compare(l_payload,l_saved_payload)<>0 then
    raise_application_error(-20000,'Mocha load seam mismatch tic='||l_tic||
      ' seq='||l_seq||' frame='||l_loaded_frame||'/'||l_saved_frame);
  end if;
  doom_api.step(l_session,command_json(35,-1,1),l_payload);
  select current_tic,last_command_seq into l_tic,l_seq from game_sessions
    where session_token=l_session;
  select count(*) into l_count from doom_mocha_command
    where session_token=l_session and save_lineage=l_new_lineage;
  if l_tic<>25 or l_seq<>35 or l_count<>25 then
    raise_application_error(-20000,'post-load continuation mismatch tic='||
      l_tic||' seq='||l_seq||' exact='||l_count);
  end if;
  doom_api.start_replay(l_session,0,25,l_replay);
  for i in 1..25 loop
    doom_api.step_replay(l_replay,l_replay_payload);
  end loop;
  if dbms_lob.compare(l_payload,l_replay_payload)<>0 then
    raise_application_error(-20000,'loaded-lineage replay mismatch');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-SAVE-LOAD savedTic=24 globalSeq=35'||
    ' branchCommands=25 replayFrames=25 stateSha='||l_saved_state||
    ' frameSha='||l_saved_frame);
  dbms_lob.freetemporary(l_saved_payload);
  cleanup;
exception when others then cleanup;raise;
end;
/
