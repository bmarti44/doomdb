whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  type sha_list is table of varchar2(64) index by pls_integer;
  l_expected sha_list;l_session varchar2(32);l_replay varchar2(32);
  l_payload blob;l_initial blob;l_repeat blob;l_sha varchar2(64);
  l_tic number;l_active number;l_deadline timestamp with time zone;
  l_min_bytes number;l_max_bytes number;

  function command_json(p_seq number) return clob is
  begin
    return '{"v":1,"commands":[{"seq":'||p_seq||
      ',"turn":'||case when mod(p_seq,5)=0 then 1 else 0 end||
      ',"forward":1,"strafe":0,"run":1,"fire":'||
      case when mod(p_seq-1,6)=0 then 1 else 0 end||
      ',"use":0,"weapon":0,"pause":0,"automap":0,'||
      '"menu":"NONE","cheat":""}]}';
  end;

  procedure payload_identity(
    p_payload blob,p_tic out number,p_frame_sha out varchar2
  ) is
    l_plain blob;
  begin
    l_plain:=doom_mocha_payload_plain(p_payload);
    p_tic:=to_number(rawtohex(dbms_lob.substr(l_plain,4,5)),'XXXXXXXX');
    p_frame_sha:=utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,64,75));
    if dbms_lob.istemporary(l_plain)=1 then dbms_lob.freetemporary(l_plain);end if;
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
  dbms_lob.createtemporary(l_initial,true,dbms_lob.call);
  dbms_lob.copy(l_initial,l_payload,dbms_lob.getlength(l_payload));
  payload_identity(l_payload,l_tic,l_expected(0));
  if l_tic<>0 then raise_application_error(-20000,'initial replay tic mismatch');end if;
  for i in 1..12 loop
    doom_api.step(l_session,command_json(i),l_payload);
    payload_identity(l_payload,l_tic,l_expected(i));
    if l_tic<>i then raise_application_error(-20000,'source replay tic mismatch');end if;
  end loop;
  select min(dbms_lob.getlength(r.response_blob)),
    max(dbms_lob.getlength(r.response_blob)) into l_min_bytes,l_max_bytes
    from doom_mocha_frame_ledger f join doom_worker_result r
      on r.request_id=f.request_id where f.session_token=l_session;
  if l_min_bytes is null or l_min_bytes=0 then
    raise_application_error(-20000,'empty replay frame ledger min='||
      coalesce(to_char(l_min_bytes),'NULL')||' max='||
      coalesce(to_char(l_max_bytes),'NULL'));
  end if;

  doom_api.start_replay(l_session,0,0,l_replay);
  doom_api.step_replay(l_replay,l_payload);
  if dbms_lob.compare(l_payload,l_initial)<>0 then
    raise_application_error(-20000,'tic-zero replay payload mismatch');
  end if;

  doom_api.start_replay(l_session,0,12,l_replay);
  for i in 1..12 loop
    doom_api.step_replay(l_replay,l_payload);
    payload_identity(l_payload,l_tic,l_sha);
    if l_tic<>i or l_sha<>l_expected(i) then
      raise_application_error(-20000,'replay mismatch tic='||i);
    end if;
  end loop;
  dbms_lob.createtemporary(l_repeat,true,dbms_lob.call);
  dbms_lob.copy(l_repeat,l_payload,dbms_lob.getlength(l_payload));
  doom_api.step_replay(l_replay,l_payload);
  if dbms_lob.compare(l_payload,l_repeat)<>0 then
    raise_application_error(-20000,'completed replay was not idempotent');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-REPLAY tics=12 ticZeroExact=1' ||
    ' completedIdempotent=1 finalFrame='||l_expected(12));
  if dbms_lob.istemporary(l_initial)=1 then dbms_lob.freetemporary(l_initial);end if;
  if dbms_lob.istemporary(l_repeat)=1 then dbms_lob.freetemporary(l_repeat);end if;
  cleanup;
exception when others then cleanup;raise;
end;
/
