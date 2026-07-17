whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Public-package regression for repeated CLAIM lock release and dynamic STEP
-- selection. The HTTP-only transport timing gate wraps this same package call.
declare
  session_ varchar2(32);payload_ blob;commands_ clob;generation_ number;
  ready_ number;map_sha_ varchar2(64);error_ varchar2(4000);tic_ number;seq_ number;
  old_enabled_ number;started_ timestamp with time zone;elapsed_ interval day to second;
  elapsed_ms_ number;requests_ number;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop(session_);exception when others then null;end;
    update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';
    if session_ is not null then delete from game_sessions where session_token=session_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  select number_value into old_enabled_ from doom_config
    where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  commit;
  doom_api.new_game(3,session_,payload_);
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  if ready_<>1 or error_ is not null then
    raise_application_error(-20000,'first public worker claim failed');end if;
  -- This second ready-worker claim formerly leaked a FOR UPDATE lock and made
  -- the resident worker wait until the public request timed out.
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  if ready_<>1 or error_ is not null then
    raise_application_error(-20000,'repeated public worker claim failed');end if;

  commands_:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":1,'||
    '"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,"pause":0,'||
    '"automap":0,"menu":"NONE","cheat":""}]}';
  started_:=systimestamp;
  doom_api.step(session_,commands_,payload_);
  elapsed_:=systimestamp-started_;
  elapsed_ms_:=extract(day from elapsed_)*86400000+
    extract(hour from elapsed_)*3600000+extract(minute from elapsed_)*60000+
    extract(second from elapsed_)*1000;
  select current_tic,last_command_seq into tic_,seq_ from game_sessions
    where session_token=session_;
  select count(*) into requests_ from doom_worker_request
    where session_token=session_ and request_status='COMMITTED';
  dbms_output.put_line('FIRST_DIAGNOSTIC tic='||tic_||' seq='||seq_||
    ' worker_requests='||requests_||' bytes='||
    case when payload_ is null then -1 else dbms_lob.getlength(payload_) end);
  if tic_<>1 or seq_<>1 or requests_<>1 or payload_ is null or
     dbms_lob.getlength(payload_)=0 then
    raise_application_error(-20000,'public worker STEP contract failed');end if;

  -- An unsupported action must stop the retained owner before SQL advances;
  -- the following movement command must reconstruct and resume on tic 3.
  commands_:='{"v":1,"commands":[{"seq":2,"turn":0,"forward":0,'||
    '"strafe":0,"run":0,"fire":1,"use":0,"weapon":0,"pause":0,'||
    '"automap":0,"menu":"NONE","cheat":""}]}';
  doom_api.step(session_,commands_,payload_);
  commands_:='{"v":1,"commands":[{"seq":3,"turn":1,"forward":1,'||
    '"strafe":0,"run":1,"fire":0,"use":0,"weapon":0,"pause":0,'||
    '"automap":0,"menu":"NONE","cheat":""}]}';
  doom_api.step(session_,commands_,payload_);
  select current_tic,last_command_seq into tic_,seq_ from game_sessions
    where session_token=session_;
  select count(*) into requests_ from doom_worker_request
    where session_token=session_ and request_status='COMMITTED';
  dbms_output.put_line('FALLBACK_DIAGNOSTIC tic='||tic_||' seq='||seq_||
    ' worker_requests='||requests_||' bytes='||
    case when payload_ is null then -1 else dbms_lob.getlength(payload_) end);
  if tic_<>3 or seq_<>3 or requests_<>2 or payload_ is null or
     dbms_lob.getlength(payload_)=0 then
    raise_application_error(-20000,'worker/SQL/worker fallback contract failed');end if;
  dbms_output.put_line('AUTOREST_WORKER_STEP_OK tic='||tic_||' seq='||seq_||
    ' worker_requests='||requests_||' bytes='||dbms_lob.getlength(payload_)||
    ' first_package_ms='||round(elapsed_ms_,3));
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;begin
    cleanup_;
    raise_application_error(-20000,'acceptance failed ['||code_||'] '||message_);
  end;
end;
/

exit
