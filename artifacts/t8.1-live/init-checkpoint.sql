set serveroutput on size unlimited
set feedback on
set sqlblanklines on
declare
  l_session varchar2(32);
  l_payload blob;
  l_state_sha varchar2(64);
begin
  doom_api.new_game(3,l_session,l_payload);
  doom_history.save_game(l_session,96,l_state_sha);
  execute immediate 'set constraints all immediate';
  dbms_output.put_line('EVAL_TUNING_INIT_SAVED|AUTHORITATIVE_TIC0=1|session='||
    l_session||'|slot=96|seq=0|state_sha='||l_state_sha);
  commit;
end;
/
