whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off timing off

declare
  l_session varchar2(32);
  new_game_payload blob;
  step_payload blob;
  java_state blob;
  sql_state blob;
  sql_sha varchar2(64);
  java_sha varchar2(64);
  command_doc clob := to_clob(
    '{"v":1,"commands":[{"turn":1,"forward":0,"strafe":0,"run":0,' ||
    '"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE",' ||
    '"cheat":"","seq":1}]}'
  );
begin
  doom_api.new_game(3, l_session, new_game_payload);
  doom_tic_tx.apply_batch(l_session, command_doc, step_payload);
  select state_blob, state_sha
  into sql_state, sql_sha
  from tic_commands
  where session_token = l_session and command_seq = 1;

  dbms_lob.createtemporary(java_state, true);
  java_sha := doom_state_codec_fill(l_session, 0, java_state);
  dbms_output.put_line(
    'STATE_CODEC sql_bytes=' || dbms_lob.getlength(sql_state) ||
    ' java_bytes=' || dbms_lob.getlength(java_state) ||
    ' sql_sha=' || sql_sha || ' java_sha=' || java_sha ||
    ' compare=' || dbms_lob.compare(sql_state, java_state)
  );
  if sql_sha <> java_sha or dbms_lob.compare(sql_state, java_state) <> 0 then
    raise_application_error(-20000, 'OJVM state codec differs from SQL oracle');
  end if;
  rollback;
end;
/

exit
