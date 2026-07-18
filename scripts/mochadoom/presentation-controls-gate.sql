whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;l_frame blob;
  l_status varchar2(4000);l_ticcmd raw(8);l_state_sha varchar2(64);
  l_frame_sha varchar2(64);l_generation number;l_count number;l_seq number:=0;

  function field(p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(l_status,'|'||p_name||'=');l_end pls_integer;
  begin
    if l_start=0 then raise_application_error(-20000,'missing status '||p_name);end if;
    l_start:=l_start+length(p_name)+2;l_end:=instr(l_status,'|',l_start);
    return substr(l_status,l_start,
      case when l_end=0 then length(l_status)+1 else l_end end-l_start);
  end;

  procedure step(p_pause number,p_automap number,p_menu number) is
  begin
    l_seq:=l_seq+1;
    doom_mocha_bridge.step(l_session,l_lineage,l_generation,l_seq-1,l_seq,
      0,0,0,0,0,0,0,p_pause,p_automap,p_menu,l_frame,l_status,l_ticcmd,
      l_state_sha,l_frame_sha);
    if l_status not like 'ok|%' then raise_application_error(-20000,l_status);end if;
  end;

  procedure cleanup is
  begin
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null
      where worker_slot=3 and target_session=l_session;
    if l_session is not null then delete from game_sessions where session_token=l_session;end if;
    commit;
    begin l_status:=doom_mocha_dispose;exception when others then null;end;
  end;
begin
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

  l_status:=doom_mocha_dispose;
  doom_mocha_bridge.reconstruct(l_session,l_lineage,l_status);
  if instr(l_status,'replayedCommands=7')=0 or field('paused')<>'0' or
     field('automap')<>'0' or field('menu')<>'1' or
     instr(l_status,'frameSha256='||l_frame_sha)=0 then
    raise_application_error(-20000,'presentation reconstruction mismatch '||l_status);
  end if;
  step(0,0,1);
  if field('menu')<>'0' then raise_application_error(-20000,'menu-off mismatch');end if;

  dbms_output.put_line('PASS MOCHADOOM-PRESENTATION-CONTROLS commands=8' ||
    ' pause=0 automap=0 menu=0 stateSha='||l_state_sha||' frameSha='||l_frame_sha);
  dbms_lob.freetemporary(l_frame);
  cleanup;
exception when others then cleanup;raise;
end;
/
