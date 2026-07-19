whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_first varchar2(32);l_second varchar2(32);l_payload blob;
  l_previous_engine varchar2(4000);
  l_slot number;l_probe number;l_deadline timestamp with time zone;
  l_started timestamp with time zone;l_cold_ms number;l_warm_ms number;
  l_frame_sha varchar2(64);l_plain blob;
  c_tic_zero constant varchar2(64):=
    'a1c9b0378eed9e82425cae593b82dfa44715627d8aa635562b450e4c1af3d3b5';

  procedure drop_session(p_session varchar2) is
  begin
    if p_session is null then return;end if;
    begin doom_unified_worker.request_stop(p_session);
    exception when others then null;end;
    delete from game_sessions where session_token=p_session;
    commit;
  end;
begin
  select text_value into l_previous_engine from doom_config
    where config_key='GAME_ENGINE';
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;

  -- The first claim arms a standby as a side effect.
  l_started:=systimestamp;
  doom_api.new_game(3,l_first,l_payload);
  l_cold_ms:=round((extract(minute from systimestamp-l_started)*60+
    extract(second from systimestamp-l_started))*1000);

  -- Wait for the armed standby to finish constructing its engine.
  l_deadline:=systimestamp+numtodsinterval(90,'SECOND');
  loop
    select count(*) into l_probe from doom_worker_audit
      where audit_event='STANDBY_WARM' and created_at>=l_started;
    exit when l_probe>=1 or systimestamp>=l_deadline;
    dbms_session.sleep(.5);
  end loop;
  if l_probe<1 then
    raise_application_error(-20000,'standby engine never reported warm');
  end if;
  select worker_slot into l_slot from doom_worker_control
    where standby=1 and target_session is null;

  -- The second claim must consume the standby and skip cold construction.
  l_started:=systimestamp;
  doom_api.new_game(3,l_second,l_payload);
  l_warm_ms:=round((extract(minute from systimestamp-l_started)*60+
    extract(second from systimestamp-l_started))*1000);
  select count(*) into l_probe from doom_worker_audit
    where audit_event='STANDBY_CLAIMED' and detail=l_second
      and created_at>=l_started;
  if l_probe<>1 then
    raise_application_error(-20000,'second claim did not consume the standby');
  end if;
  select count(*) into l_probe from doom_worker_control
    where worker_slot=l_slot and target_session=l_second and ready=1
      and standby=0;
  if l_probe<>1 then
    raise_application_error(-20000,'standby slot did not become the live owner');
  end if;

  -- The standby-claimed session must publish the exact canonical tic-zero
  -- frame: identical bytes to a cold construction.
  l_plain:=doom_mocha_payload_plain(l_payload);
  if utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,4,1))<>'DMF3' then
    raise_application_error(-20000,'standby payload is not DMF3');
  end if;
  l_frame_sha:=utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75));
  if l_frame_sha<>c_tic_zero then
    raise_application_error(-20000,'standby tic-zero frame diverged: '||
      l_frame_sha);
  end if;

  dbms_output.put_line('PASS MOCHADOOM-STANDBY slot='||l_slot||
    ' coldMs='||l_cold_ms||' warmMs='||l_warm_ms||
    ' frameSha='||l_frame_sha);
  drop_session(l_first);
  drop_session(l_second);
  update doom_config set text_value=coalesce(l_previous_engine,text_value)
    where config_key='GAME_ENGINE';
  commit;
exception when others then
  drop_session(l_first);
  drop_session(l_second);
  update doom_config set text_value=coalesce(l_previous_engine,text_value)
    where config_key='GAME_ENGINE';
  commit;
  raise;
end;
/
