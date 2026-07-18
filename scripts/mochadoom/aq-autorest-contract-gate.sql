whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_session varchar2(32);l_payload blob;l_duplicate blob;l_plain blob;
  l_commands clob;l_tic number;l_seq number;l_rows number;l_sha varchar2(64);
  l_duplicate_sha varchar2(64);l_deadline timestamp with time zone;

  procedure stop_and_clean is
    l_active number;
  begin
    if l_session is not null then
      begin doom_unified_worker.request_stop(l_session);exception when others then null;end;
      l_deadline:=systimestamp+numtodsinterval(8,'SECOND');
      loop
        select count(*) into l_active from doom_worker_control
          where target_session=l_session;
        exit when l_active=0 or systimestamp>=l_deadline;
        dbms_session.sleep(.1);
      end loop;
      delete from game_sessions where session_token=l_session;
    end if;
    update doom_config set text_value='SQL' where config_key='GAME_ENGINE';
    commit;
  end;
begin
  update doom_config set text_value='MOCHA' where config_key='GAME_ENGINE';
  if sql%rowcount<>1 then raise_application_error(-20000,'engine selector missing');end if;
  commit;
  doom_api.new_game(3,l_session,l_payload);
  l_commands:='{"v":1,"commands":[{"seq":1,"turn":1,"forward":1,'||
    '"strafe":1,"run":1,"fire":1,"use":0,"weapon":3,"pause":0,'||
    '"automap":0,"menu":"NONE","cheat":""}]}';
  doom_api.step(l_session,l_commands,l_payload);
  l_plain:=doom_mocha_payload_plain(l_payload);
  if dbms_lob.getlength(l_plain)<>64142 or
     utl_raw.cast_to_varchar2(dbms_lob.substr(l_plain,4,1))<>'DMF3' or
     rawtohex(dbms_lob.substr(l_plain,4,5))<>'00000001' then
    raise_application_error(-20000,'AQ DMF3 response mismatch');
  end if;
  select current_tic,last_command_seq into l_tic,l_seq from game_sessions
    where session_token=l_session;
  select count(*) into l_rows from doom_mocha_command
    where session_token=l_session;
  if l_tic<>1 or l_seq<>1 or l_rows<>1 then
    raise_application_error(-20000,'AQ frontier/ledger mismatch');
  end if;
  l_sha:=lower(rawtohex(dbms_crypto.hash(l_payload,dbms_crypto.hash_sh256)));
  doom_api.step(l_session,l_commands,l_duplicate);
  l_duplicate_sha:=lower(rawtohex(
    dbms_crypto.hash(l_duplicate,dbms_crypto.hash_sh256)));
  select current_tic,last_command_seq into l_tic,l_seq from game_sessions
    where session_token=l_session;
  select count(*) into l_rows from doom_mocha_command
    where session_token=l_session;
  if l_sha<>l_duplicate_sha or l_tic<>1 or l_seq<>1 or l_rows<>1 then
    raise_application_error(-20000,'AQ duplicate idempotency mismatch');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-AQ-CONTRACT tic=1 seq=1'||
    ' exactRows=1 payloadBytes='||dbms_lob.getlength(l_payload)||
    ' payloadSha='||l_sha);
  stop_and_clean;
exception when others then stop_and_clean;raise;
end;
/
