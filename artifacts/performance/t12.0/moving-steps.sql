whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off serveroutput on size unlimited timing off pages 100 lines 220

declare
  l_session varchar2(32);
  l_payload blob;
  l_started integer;
begin
  delete from game_sessions;
  commit;

  doom_api.new_game(3,l_session,l_payload);
  l_started:=dbms_utility.get_time;
  doom_api.step(
    l_session,
    to_clob('{"v":1,"commands":[{"turn":1,"forward":0,"strafe":0,"run":0,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":1}]}'),
    l_payload
  );
  dbms_output.put_line('ONE_MOVING_STEP_CENTISECONDS '||(dbms_utility.get_time-l_started));
  dbms_output.put_line('ONE_MOVING_STEP_PAYLOAD_BYTES '||dbms_lob.getlength(l_payload));

  delete from game_sessions;
  commit;

  doom_api.new_game(3,l_session,l_payload);
  l_started:=dbms_utility.get_time;
  doom_api.step(
    l_session,
    to_clob('{"v":1,"commands":[{"turn":0,"forward":1,"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":1},{"turn":0,"forward":1,"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":2},{"turn":0,"forward":1,"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":3},{"turn":0,"forward":1,"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE","cheat":"","seq":4}]}'),
    l_payload
  );
  dbms_output.put_line('FOUR_MOVING_STEPS_CENTISECONDS '||(dbms_utility.get_time-l_started));
  dbms_output.put_line('FOUR_MOVING_STEPS_PAYLOAD_BYTES '||dbms_lob.getlength(l_payload));
end;
/
