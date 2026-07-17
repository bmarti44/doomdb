whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  session_ varchar2(32);lineage_ varchar2(64);initial_ blob;request_ varchar2(32);
  generation_ number;ready_ number;map_sha_ varchar2(64);error_ varchar2(4000);
  tic_ number;seq_ number;old_enabled_ number;old_overlap_ number;old_wait_ number;
  old_failpoint_ number;failed_request_ varchar2(32);failed_tic_ number;failed_seq_ number;
  status_ varchar2(16);response_generation_ number;committed_tic_ number;
  committed_seq_ number;delta_version_ number;delta_count_ number;
  delta_sha_ varchar2(64);state_sha_ varchar2(64);frame_sha_ varchar2(64);
  response_bytes_ number;response_sha_ varchar2(64);delta_ blob;response_ blob;
  deadline_ timestamp with time zone;count_ number;stage_status_ varchar2(24);
  stage_frame_ varchar2(64);stage_response_ varchar2(64);stage_bytes_ number;
  pack_bytes_ number;render_us_ number;stage_blob_ blob;
  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;
  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop_all;exception when others then null;end;
    begin if session_ is not null then doom_render_worker.request_stop(session_);end if;
      exception when others then null;end;
    deadline_:=systimestamp+interval '20' second;
    loop
      select count(*) into count_ from user_scheduler_running_jobs
        where job_name like 'DOOM\_UNIFIED\_WORKER\_%' escape '\'
           or job_name like 'DOOM\_RENDER\_WORKER\_%' escape '\';
      exit when count_=0 or systimestamp>deadline_;dbms_session.sleep(.05);
    end loop;
    if session_ is not null then delete from game_sessions where session_token=session_;end if;
    update doom_worker_control set target_session=null,target_lineage=null,state_map_sha=null,
      ready=0,stop_requested=0,worker_sid=null,last_error=null;
    update doom_render_worker_control set target_session=null,target_lineage=null,state_map_sha=null,
      ready=0,stop_requested=0,worker_sid=null,last_error=null;
    update doom_config set number_value=old_enabled_ where config_key='UNIFIED_WORKER_ENABLED';
    update doom_config set number_value=old_overlap_ where config_key='RENDER_OVERLAP_ENABLED';
    update doom_config set number_value=old_wait_ where config_key='RENDER_OVERLAP_WAIT_MS';commit;
    update doom_config set number_value=old_failpoint_ where config_key='UNIFIED_WORKER_FAILPOINT';commit;
  exception when others then null;
  end;
begin
  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_overlap_ from doom_config where config_key='RENDER_OVERLAP_ENABLED';
  select number_value into old_wait_ from doom_config where config_key='RENDER_OVERLAP_WAIT_MS';
  select number_value into old_failpoint_ from doom_config where config_key='UNIFIED_WORKER_FAILPOINT';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='RENDER_OVERLAP_ENABLED';
  update doom_config set number_value=1000 where config_key='RENDER_OVERLAP_WAIT_MS';commit;

  doom_api.new_game(3,session_,initial_);request_:=lower(rawtohex(sys_guid()));
  select save_lineage,current_tic,last_command_seq into lineage_,tic_,seq_
    from game_sessions where session_token=session_;
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  assert_(ready_=1 and error_ is null,'simulation worker did not become ready');
  deadline_:=systimestamp+interval '30' second;
  loop
    select count(*) into count_ from doom_render_worker_control
      where target_session=session_ and ready=1 and last_error is null;
    exit when count_=1 or systimestamp>=deadline_;dbms_session.sleep(.01);
  end loop;
  assert_(count_=1,'render worker did not become ready');

  doom_worker_api.step(session_,lineage_,generation_,request_,tic_,seq_,2,1,
    hextoraw('444d53430201000000000000000000010001000000000000'),30,
    status_,response_generation_,committed_tic_,committed_seq_,delta_version_,
    delta_count_,delta_sha_,state_sha_,frame_sha_,response_bytes_,response_sha_,
    delta_,response_,error_);
  assert_(status_='COMMITTED' and error_ is null and committed_tic_=tic_+1 and
    committed_seq_=seq_+1 and response_generation_=generation_,
    'overlap request failed: '||status_||' '||error_);
  deadline_:=systimestamp+interval '5' second;
  loop
    select stage_status,frame_sha,response_sha,response_bytes,render_pack_bytes,render_us,response_blob
      into stage_status_,stage_frame_,stage_response_,stage_bytes_,pack_bytes_,render_us_,stage_blob_
      from doom_render_stage where request_id=request_;
    exit when stage_status_ in('ACCEPTED','FAILED') or systimestamp>=deadline_;
    dbms_session.sleep(.005);
  end loop;
  assert_(stage_status_='ACCEPTED','render stage not accepted: '||stage_status_);
  assert_(stage_frame_=frame_sha_ and stage_response_=response_sha_ and
    stage_bytes_=response_bytes_ and dbms_lob.compare(response_,stage_blob_)=0,
    'staged/final response mismatch');
  -- A failure after the separate renderer has staged bytes but before the
  -- authoritative transaction commits must roll SQL back and discard the
  -- render worker's pending arrays.
  failed_request_:=lower(rawtohex(sys_guid()));failed_tic_:=committed_tic_;failed_seq_:=committed_seq_;
  update doom_config set number_value=5 where config_key='UNIFIED_WORKER_FAILPOINT';commit;
  doom_worker_api.step(session_,lineage_,generation_,failed_request_,failed_tic_,failed_seq_,2,1,
    hextoraw('444d53430201000000000000000000020001000000000000'),0,
    status_,response_generation_,committed_tic_,committed_seq_,delta_version_,
    delta_count_,delta_sha_,state_sha_,frame_sha_,response_bytes_,response_sha_,
    delta_,response_,error_);
  deadline_:=systimestamp+interval '5' second;
  loop
    select request_status into status_ from doom_worker_request where request_id=failed_request_;
    exit when status_='FAILED' or systimestamp>=deadline_;dbms_session.sleep(.005);
  end loop;
  assert_(status_='FAILED','post-render failpoint did not fail request');
  deadline_:=systimestamp+interval '5' second;
  loop
    select stage_status into stage_status_ from doom_render_stage where request_id=failed_request_;
    exit when stage_status_ in('DISCARDED','FAILED') or systimestamp>=deadline_;dbms_session.sleep(.005);
  end loop;
  assert_(stage_status_='DISCARDED','post-render failure did not discard stage: '||stage_status_);
  select current_tic,last_command_seq into committed_tic_,committed_seq_
    from game_sessions where session_token=session_;
  assert_(committed_tic_=failed_tic_ and committed_seq_=failed_seq_,
    'post-render failure leaked authoritative frontier');
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';commit;
  dbms_output.put_line('UNIFIED_RENDER_OVERLAP_ACCEPTANCE_OK generation='||generation_||
    ' tic='||committed_tic_||' pack_bytes='||pack_bytes_||' render_ms='||round(render_us_/1000,3)||
    ' rollback_stage='||stage_status_);
  cleanup_;
exception when others then
  error_:=sqlerrm||' '||dbms_utility.format_error_backtrace;cleanup_;
  raise_application_error(-20000,substr(error_,1,1900));
end;
/

exit
