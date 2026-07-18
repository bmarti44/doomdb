whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;l_frame blob;
  l_plain blob;
  l_status varchar2(4000);l_ticcmd raw(8);l_state_sha varchar2(64);
  l_frame_sha varchar2(64);l_audio_length number;l_audio varchar2(4000);

  procedure cleanup is
  begin
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null
      where worker_slot=3 and target_session=l_session;
    if l_session is not null then
      delete from game_sessions where session_token=l_session;
    end if;
    commit;
    begin l_status:=doom_mocha_dispose;exception when others then null;end;
  end;
begin
  doom_api.new_game(3,l_session,l_payload);
  select save_lineage into l_lineage from game_sessions
    where session_token=l_session;
  doom_mocha_bridge.create_lineage(l_session,l_lineage,3,1,1);
  update doom_worker_control set target_session=l_session,
    target_lineage=l_lineage,state_map_sha=l_lineage,generation=generation+1,
    ready=1,stop_requested=0,worker_sid=sys_context('USERENV','SID')
    where worker_slot=3 and target_session is null;
  if sql%rowcount<>1 then
    raise_application_error(-20000,'test worker slot unavailable');
  end if;
  commit;

  l_status:=doom_mocha_new_game(2,1,1);
  if l_status not like 'ok|state=new-game%' then
    raise_application_error(-20000,l_status);
  end if;
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  declare l_generation number;begin
    select generation into l_generation from doom_worker_control
      where worker_slot=3;
    doom_mocha_bridge.step(l_session,l_lineage,l_generation,0,1,
      1,1,1,1,1,1,3,0,0,0,l_frame,l_status,l_ticcmd,l_state_sha,l_frame_sha);
  end;
  if rawtohex(l_ticcmd)<>'3228FEC000000017' or
     dbms_lob.getlength(l_frame) not between 1000 and 64142 or
     rawtohex(dbms_lob.substr(l_frame,2,1))<>'1F8B' then
    raise_application_error(-20000,'durable bridge result mismatch');
  end if;
  l_plain:=doom_mocha_payload_plain(l_frame);
  l_audio_length:=to_number(rawtohex(dbms_lob.substr(l_plain,2,139)),'XXXX');
  l_audio:=utl_raw.cast_to_varchar2(
    dbms_lob.substr(l_plain,l_audio_length,141));
  if dbms_lob.getlength(l_plain)<>64140+l_audio_length or
     utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,4,1))<>'DMF3' or
     rawtohex(dbms_lob.substr(l_plain,4,5))<>'00000001' or
     utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,11))<>l_state_sha or
     utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75))<>l_frame_sha or
     not regexp_like(l_audio,'^\[.*\]$') then
    raise_application_error(-20000,'DMF3 envelope mismatch plain='||
      dbms_lob.getlength(l_plain)||' audioLength='||l_audio_length||
      ' audio='||l_audio);
  end if;
  commit;

  l_status:=doom_mocha_dispose;
  doom_mocha_bridge.reconstruct(l_session,l_lineage,l_status);
  if instr(l_status,'replayedCommands=1')=0 or
     instr(l_status,'frameSha256='||l_frame_sha)=0 then
    raise_application_error(-20000,'durable reconstruction mismatch '||l_status);
  end if;
  dbms_output.put_line('PASS MOCHADOOM-DURABLE-BRIDGE ticcmd='||
    lower(rawtohex(l_ticcmd))||' stateSha='||l_state_sha||
    ' frameSha='||l_frame_sha||' audio='||l_audio||
    ' payloadBytes='||dbms_lob.getlength(l_frame));
  dbms_lob.freetemporary(l_frame);
  if dbms_lob.istemporary(l_plain)=1 then dbms_lob.freetemporary(l_plain);end if;
  cleanup;
exception when others then
  cleanup;
  raise;
end;
/
