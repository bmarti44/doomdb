whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_payload blob;l_plain blob;l_cache blob;
  l_tic number;l_generation number;l_worker_generation number;
  l_ready number;l_active number;
  l_deadline timestamp with time zone;l_frame_sha varchar2(64);
  l_previous_engine varchar2(4000);
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
    update doom_config set text_value=coalesce(l_previous_engine,text_value)
      where config_key='GAME_ENGINE';
    commit;
  end;
begin
  select text_value into l_previous_engine from doom_config
    where config_key='GAME_ENGINE';
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';commit;
  doom_api.new_game(3,l_session,l_payload);
  l_plain:=doom_mocha_payload_plain(l_payload);
  if utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,4,1))<>'DMF3' then
    raise_application_error(-20000,'initial payload is not DMF3');
  end if;
  l_tic:=to_number(rawtohex(dbms_lob.substr(l_plain,4,5)),'XXXXXXXX');
  l_frame_sha:=utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75));
  select c.generation,c.response_blob,w.generation,w.ready
    into l_generation,l_cache,l_worker_generation,l_ready
    from doom_mocha_frame_cache c join doom_worker_control w
      on w.target_session=c.session_token and w.generation=c.generation
    where c.session_token=l_session and c.tic=0;
  if l_tic<>0 or l_ready<>1 or l_generation<>l_worker_generation or
     dbms_lob.compare(l_payload,l_cache)<>0 then
    raise_application_error(-20000,'initial retained frame mismatch tic='||
      l_tic||' ready='||l_ready);
  end if;
  dbms_output.put_line('PASS MOCHADOOM-INITIAL-FRAME tic=0 generation='||
    l_generation||' payloadBytes='||dbms_lob.getlength(l_payload)||
    ' frameSha='||l_frame_sha);
  cleanup;
exception when others then cleanup;raise;
end;
/
