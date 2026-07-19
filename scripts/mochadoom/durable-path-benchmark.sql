whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  type numbers_t is table of number index by pls_integer;
  l_values numbers_t;l_session varchar2(32);l_lineage varchar2(64);
  l_payload blob;l_frame blob;l_status varchar2(4000);l_ticcmd raw(8);
  l_state_sha varchar2(64);l_frame_sha varchar2(64);l_generation number;
  l_started timestamp with time zone;
  l_span interval day to second;l_value number;

  function elapsed_us(p_span interval day to second) return number is
  begin
    return round((extract(day from p_span)*86400+extract(hour from p_span)*3600+
      extract(minute from p_span)*60+extract(second from p_span))*1000000);
  end;

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
  select generation into l_generation from doom_worker_control
    where worker_slot=3;
  commit;
  l_status:=doom_mocha_new_game(2,1,1);
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);

  for l_index in 1..330 loop
    l_started:=systimestamp;
    doom_mocha_bridge.step(l_session,l_lineage,l_generation,l_index-1,l_index,
      0,1,0,1,case when mod(l_index-1,8)=0 then 1 else 0 end,0,0,
      0,0,0,0,l_frame,l_status,l_ticcmd,l_state_sha,l_frame_sha);
    commit write immediate wait;
    if l_index>30 then
      l_values(l_index-30):=elapsed_us(systimestamp-l_started);
    end if;
  end loop;

  for l_index in 2..300 loop
    l_value:=l_values(l_index);
    declare l_scan pls_integer:=l_index-1;begin
      while l_scan>=1 and l_values(l_scan)>l_value loop
        l_values(l_scan+1):=l_values(l_scan);l_scan:=l_scan-1;
      end loop;
      l_values(l_scan+1):=l_value;
    end;
  end loop;
  l_status:=doom_mocha_dispose;
  doom_mocha_bridge.reconstruct(l_session,l_lineage,l_status);
  if instr(l_status,'replayedCommands=330')=0 or
     instr(l_status,'frameSha256='||l_frame_sha)=0 then
    raise_application_error(-20000,'post-benchmark reconstruction mismatch');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-DURABLE-PATH samples=300'||
    ' p50Micros='||l_values(150)||' p95Micros='||l_values(285)||
    ' p99Micros='||l_values(297)||' maxMicros='||l_values(300)||
    ' replayedCommands=330 stateSha='||l_state_sha||' frameSha='||l_frame_sha||
    ' payloadBytes='||dbms_lob.getlength(l_frame));
  dbms_lob.freetemporary(l_frame);
  cleanup;
exception when others then cleanup;raise;
end;
/
