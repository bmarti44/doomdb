whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;l_frame blob;
  l_plain blob;
  l_status varchar2(4000);l_ticcmd raw(8);l_state_sha varchar2(64);
  l_frame_sha varchar2(64);l_audio_length number;l_audio varchar2(4000);
  l_previous_engine varchar2(4000);
  l_slot_deadline timestamp with time zone;l_slot_free number;

  procedure cleanup is
  begin
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null
      where worker_slot=3 and target_session=l_session;
    if l_session is not null then
      delete from game_sessions where session_token=l_session;
    end if;
    update doom_config set text_value=coalesce(l_previous_engine,text_value)
      where config_key='GAME_ENGINE';
    commit;
    begin l_status:=doom_mocha_dispose;exception when others then null;end;
  end;
begin
  -- This gate drives the bridge directly through its manual slot-3 harness.
  -- A MOCHA selector would make NEW_GAME claim a real worker for the session,
  -- colliding with that harness on the unique TARGET_SESSION constraint.
  select text_value into l_previous_engine from doom_config
    where config_key='GAME_ENGINE';
  update doom_config set text_value='SQL' where config_key='GAME_ENGINE';commit;
  -- Slot 3 is this gate's dedicated harness slot. A ready idle worker may
  -- legitimately hold it under the 600-second retention; ask it to stop and
  -- wait for the slot before claiming it manually.
  update doom_worker_control set stop_requested=1
    where worker_slot=3 and target_session is not null and ready=1;
  commit;
  l_slot_deadline:=systimestamp+numtodsinterval(15,'SECOND');
  loop
    select count(*) into l_slot_free from doom_worker_control
      where worker_slot=3 and target_session is null;
    exit when l_slot_free=1 or systimestamp>=l_slot_deadline;
    dbms_session.sleep(.2);
  end loop;
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
      1,1,1,1,1,1,3,0,0,0,0,l_frame,l_status,l_ticcmd,l_state_sha,l_frame_sha);
  end;
  if rawtohex(l_ticcmd)<>'3228FEC000000017' or
     dbms_lob.getlength(l_frame) not between 64142 and 68142 or
     rawtohex(dbms_lob.substr(l_frame,4,1))<>'444D4633' then
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
