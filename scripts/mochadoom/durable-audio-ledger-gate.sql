whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;l_frame blob;
  l_status varchar2(4000);l_ticcmd raw(8);l_state_sha varchar2(64);
  l_frame_sha varchar2(64);l_generation number;l_count number;l_bad number;
  l_head varchar2(64);l_last varchar2(64);
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
  select generation into l_generation from doom_worker_control
    where worker_slot=3;
  commit;

  l_status:=doom_mocha_new_game(2,1,1);
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  for l_seq in 1..24 loop
    doom_mocha_bridge.step(l_session,l_lineage,l_generation,l_seq-1,l_seq,
      0,0,0,0,1,0,0,0,0,0,l_frame,l_status,l_ticcmd,l_state_sha,l_frame_sha);
  end loop;
  commit;

  select count(*) into l_count from audio_events
    where session_token=l_session and lineage=l_lineage
      and asset_kind='sound' and asset_name='DSPISTOL';
  if l_count<1 then
    raise_application_error(-20000,'durable pistol event missing');
  end if;
  select count(*) into l_bad from audio_events
    where session_token=l_session and lineage=l_lineage and
      (not regexp_like(previous_event_sha,'^[0-9a-f]{64}$') or
       event_sha<>lower(rawtohex(dbms_crypto.hash(json_object(
         'lineage' value lineage,'tic' value tic,'ordinal' value event_ordinal,
         'asset_kind' value asset_kind,'asset_name' value asset_name,
         'volume' value volume,'separation' value separation,
         'previous_event_sha' value previous_event_sha returning clob),
         dbms_crypto.hash_sh256))));
  if l_bad<>0 then
    raise_application_error(-20000,'durable audio hash mismatch='||l_bad);
  end if;
  select event_sha into l_last from audio_events
    where session_token=l_session and lineage=l_lineage
    order by tic desc,event_ordinal desc fetch first 1 row only;
  select event_sha into l_head from history_heads
    where session_token=l_session and lineage=l_lineage;
  if l_head<>l_last then
    raise_application_error(-20000,'durable audio head mismatch');
  end if;

  l_status:=doom_mocha_dispose;
  doom_mocha_bridge.reconstruct(l_session,l_lineage,l_status);
  if instr(l_status,'replayedCommands=24')=0 or
     instr(l_status,'frameSha256='||l_frame_sha)=0 then
    raise_application_error(-20000,'audio reconstruction mismatch '||l_status);
  end if;
  dbms_output.put_line('PASS MOCHADOOM-DURABLE-AUDIO commands=24 events='||
    l_count||' eventHead='||l_head||' frameSha='||l_frame_sha);
  dbms_lob.freetemporary(l_frame);
  cleanup;
exception when others then cleanup;raise;
end;
/
