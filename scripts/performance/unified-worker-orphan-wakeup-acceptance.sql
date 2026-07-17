whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- A committed AQ wakeup may outlive the request row removed by a cascading
-- game-session delete. The resident worker must consume that orphan and keep
-- serving the next owner instead of terminating with NO_DATA_FOUND.
declare
  session_ varchar2(32);lineage_ varchar2(64);initial_ blob;request_ varchar2(32);
  generation_ number;ready_ number;map_sha_ varchar2(64);error_ varchar2(4000);
  tic_ number;seq_ number;old_enabled_ number;old_wait_ number;
  enqueue_options_ dbms_aq.enqueue_options_t;
  message_properties_ dbms_aq.message_properties_t;
  message_id_ raw(16);payload_raw_ raw(32767);
  status_ varchar2(16);response_generation_ number;committed_tic_ number;
  committed_seq_ number;delta_version_ number;delta_count_ number;
  delta_sha_ varchar2(64);state_sha_ varchar2(64);frame_sha_ varchar2(64);
  response_bytes_ number;response_sha_ varchar2(64);delta_ blob;response_ blob;
  deadline_ timestamp with time zone;count_ number;

  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop_all;exception when others then null;end;
    deadline_:=systimestamp+interval '20' second;
    loop
      select count(*) into count_ from user_scheduler_running_jobs
        where job_name like 'DOOM_UNIFIED_WORKER___';
      exit when count_=0 or systimestamp>deadline_;
      dbms_session.sleep(.05);
    end loop;
    if session_ is not null then delete from game_sessions where session_token=session_;end if;
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null,last_error=null;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_wait_ is not null then update doom_config set number_value=old_wait_
      where config_key='UNIFIED_WORKER_WAIT_SECONDS';end if;
    commit;
  exception when others then null;
  end;
begin
  select number_value into old_enabled_ from doom_config
    where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_wait_ from doom_config
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=30 where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  commit;

  message_properties_.correlation:='SLOT_01';
  message_properties_.priority:=0;
  enqueue_options_.visibility:=dbms_aq.on_commit;
  payload_raw_:=utl_raw.cast_to_raw('ffffffffffffffffffffffffffffffff');
  dbms_aq.enqueue('DOOM_UNIFIED_REQUEST_Q',enqueue_options_,
    message_properties_,payload_raw_,message_id_);
  commit;

  doom_api.new_game(3,session_,initial_);
  request_:=lower(rawtohex(sys_guid()));
  select save_lineage,current_tic,last_command_seq into lineage_,tic_,seq_
    from game_sessions where session_token=session_;
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  assert_(ready_=1 and error_ is null,'worker did not become ready');
  dbms_session.sleep(.25);
  select count(*) into count_ from doom_worker_control
    where target_session=session_ and generation=generation_ and ready=1
      and last_error is null;
  assert_(count_=1,'orphan wakeup terminated worker');

  doom_worker_api.step(session_,lineage_,generation_,
    request_,tic_,seq_,2,1,
    hextoraw('444d53430201000000000000000000010001000000000000'),30,
    status_,response_generation_,committed_tic_,committed_seq_,delta_version_,
    delta_count_,delta_sha_,state_sha_,frame_sha_,response_bytes_,response_sha_,
    delta_,response_,error_);
  assert_(status_='COMMITTED' and error_ is null and committed_tic_=tic_+1 and
    committed_seq_=seq_+1 and response_generation_=generation_,
    'worker did not serve request after orphan: '||status_||' '||error_);
  dbms_output.put_line('UNIFIED_WORKER_ORPHAN_WAKEUP_ACCEPTANCE_OK generation='||
    generation_||' tic='||committed_tic_);
  cleanup_;
exception when others then
  error_:=sqlerrm||' '||dbms_utility.format_error_backtrace;
  cleanup_;
  raise_application_error(-20000,substr(error_,1,1900));
end;
/

exit
