whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;l_frame blob;
  l_status varchar2(4000);l_ticcmd raw(8);l_state_sha varchar2(64);
  l_frame_sha varchar2(64);l_generation number;l_count number;l_seq number:=0;
  l_previous_engine varchar2(4000);
  l_slot_deadline timestamp with time zone;l_slot_free number;

  function field(p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(l_status,'|'||p_name||'=');l_end pls_integer;
  begin
    if l_start=0 then raise_application_error(-20000,'missing status '||p_name);end if;
    l_start:=l_start+length(p_name)+2;l_end:=instr(l_status,'|',l_start);
    return substr(l_status,l_start,
      case when l_end=0 then length(l_status)+1 else l_end end-l_start);
  end;

  procedure step(p_pause number,p_automap number,p_menu number,
    p_cheat number default 0) is
  begin
    l_seq:=l_seq+1;
    doom_mocha_bridge.step(l_session,l_lineage,l_generation,l_seq-1,l_seq,
      0,0,0,0,0,0,0,p_pause,p_automap,p_menu,p_cheat,l_frame,l_status,l_ticcmd,
      l_state_sha,l_frame_sha);
    if l_status not like 'ok|%' then raise_application_error(-20000,l_status);end if;
  end;

  procedure cleanup is
  begin
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null
      where worker_slot=3 and target_session=l_session;
    if l_session is not null then delete from game_sessions where session_token=l_session;end if;
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
  select save_lineage into l_lineage from game_sessions where session_token=l_session;
  doom_mocha_bridge.create_lineage(l_session,l_lineage,3,1,1);
  update doom_worker_control set target_session=l_session,target_lineage=l_lineage,
    state_map_sha=l_lineage,generation=generation+1,ready=1,stop_requested=0,
    worker_sid=sys_context('USERENV','SID')
    where worker_slot=3 and target_session is null;
  if sql%rowcount<>1 then raise_application_error(-20000,'test worker unavailable');end if;
  select generation into l_generation from doom_worker_control where worker_slot=3;
  commit;
  l_status:=doom_mocha_new_game(2,1,1);
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);

  step(1,0,0);
  if field('paused')<>'1' or rawtohex(utl_raw.substr(l_ticcmd,8,1))<>'81' then
    raise_application_error(-20000,'pause-on mismatch '||l_status);
  end if;
  step(0,0,0);
  if field('paused')<>'1' then raise_application_error(-20000,'pause hold mismatch');end if;
  step(1,0,0);
  if field('paused')<>'0' then raise_application_error(-20000,'pause-off mismatch');end if;

  step(0,1,0);
  if field('automap')<>'1' or rawtohex(utl_raw.substr(l_ticcmd,5,2))<>'0002' then
    raise_application_error(-20000,'automap-on mismatch '||l_status);
  end if;
  step(0,0,0);
  if field('automap')<>'1' then raise_application_error(-20000,'automap hold mismatch');end if;
  step(0,1,0);
  if field('automap')<>'0' then raise_application_error(-20000,'automap-off mismatch');end if;

  step(0,0,1);
  if field('menu')<>'1' or rawtohex(utl_raw.substr(l_ticcmd,5,2))<>'0004' then
    raise_application_error(-20000,'menu-on mismatch '||l_status);
  end if;
  commit;
  select count(*) into l_count from tic_commands where session_token=l_session
    and lineage=l_lineage and pause_toggle=1;
  if l_count<>2 then raise_application_error(-20000,'durable pause rows='||l_count);end if;
  select count(*) into l_count from tic_commands where session_token=l_session
    and lineage=l_lineage and automap_toggle=1;
  if l_count<>2 then raise_application_error(-20000,'durable automap rows='||l_count);end if;
  select count(*) into l_count from tic_commands where session_token=l_session
    and lineage=l_lineage and menu_action='OPTIONS';
  if l_count<>1 then raise_application_error(-20000,'durable menu rows='||l_count);end if;

  step(0,0,1);
  if field('menu')<>'0' then raise_application_error(-20000,'menu-off mismatch');end if;
  step(0,0,0,1);
  if field('god')<>'1' or field('playerHealth')<>'100' or
     rawtohex(utl_raw.substr(l_ticcmd,5,2))<>'0008' then
    raise_application_error(-20000,'god-on mismatch '||l_status);end if;
  step(0,0,0,1);
  if field('god')<>'0' then raise_application_error(-20000,'god-off mismatch');end if;
  step(0,0,0,3);
  if field('noclip')<>'1' or rawtohex(utl_raw.substr(l_ticcmd,5,2))<>'0018' then
    raise_application_error(-20000,'noclip-on mismatch '||l_status);end if;
  step(0,0,0,3);
  if field('noclip')<>'0' then raise_application_error(-20000,'noclip-off mismatch');end if;
  step(0,0,0,4);
  if field('fullmap')<>'1' or rawtohex(utl_raw.substr(l_ticcmd,5,2))<>'0020' then
    raise_application_error(-20000,'fullmap-on mismatch '||l_status);end if;
  step(0,0,0,4);
  if field('fullmap')<>'0' then raise_application_error(-20000,'fullmap-off mismatch');end if;
  step(0,0,0,2);
  if field('ownedWeapons')<>'9' or field('ownedKeys')<>'6' or
     field('armor')<>'200' or rawtohex(utl_raw.substr(l_ticcmd,5,2))<>'0010' then
    raise_application_error(-20000,'all-items mismatch '||l_status);end if;
  commit;
  select count(*) into l_count from tic_commands where session_token=l_session
    and lineage=l_lineage and cheat_code in('GOD','NOCLIP','FULLMAP','ALL');
  if l_count<>7 then raise_application_error(-20000,'durable cheat rows='||l_count);end if;

  l_status:=doom_mocha_dispose;
  doom_mocha_bridge.reconstruct(l_session,l_lineage,l_status);
  if instr(l_status,'replayedCommands=15')=0 or field('paused')<>'0' or
     field('automap')<>'0' or field('menu')<>'0' or field('god')<>'0' or
     field('noclip')<>'0' or field('fullmap')<>'0' or
     field('ownedWeapons')<>'9' or field('ownedKeys')<>'6' or
     instr(l_status,'frameSha256='||l_frame_sha)=0 then
    raise_application_error(-20000,'control reconstruction mismatch '||l_status);
  end if;

  dbms_output.put_line('PASS MOCHADOOM-PRESENTATION-CONTROLS commands=15' ||
    ' pause=0 automap=0 menu=0 cheats=7 stateSha='||l_state_sha||
    ' frameSha='||l_frame_sha);
  dbms_lob.freetemporary(l_frame);
  cleanup;
exception when others then cleanup;raise;
end;
/
