whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Default-off, live commit, exact replay, pre/post-commit failure, combined
-- reconstruction, response correlation and restart acceptance.
declare
  session_ varchar2(32);lineage_ varchar2(64);initial_ blob;
  generation_ number;ready_ number;map_sha_ varchar2(64);error_ varchar2(4000);
  status_ varchar2(16);response_generation_ number;committed_tic_ number;
  committed_seq_ number;delta_version_ number;delta_count_ number;
  delta_sha_ varchar2(64);state_sha_ varchar2(64);frame_sha_ varchar2(64);
  response_bytes_ number;response_sha_ varchar2(64);delta_ blob;payload_ blob;
  tic_ number;seq_ number;old_wait_ number;old_capacity_ number;
  count_ number;
  deadline_ timestamp with time zone;
  blocked_ boolean;

  function command_(p_seq number,p_forward number default 1) return raw is
    movement_ varchar2(2);
  begin
    movement_:=case p_forward when -1 then 'ff' when 0 then '00' else '01' end;
    return hextoraw('444d53430201000000000000'||
      lpad(to_char(p_seq,'fmxxxxxxxx'),8,'0')||'00'||movement_||
      '0000'||'00000000');
  end;

  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;

  procedure assert_ready_(p_generation number,p_message varchar2) is
    lineage_check_ varchar2(64);map_check_ varchar2(64);generation_check_ number;
    ready_check_ number;error_check_ varchar2(4000);
  begin
    select target_lineage,state_map_sha,generation,ready,last_error
      into lineage_check_,map_check_,generation_check_,ready_check_,error_check_
      from doom_worker_control where target_session=session_;
    assert_(lineage_check_=lineage_ and map_check_=map_sha_ and
      generation_check_=p_generation and ready_check_=1 and error_check_ is null,
      p_message);
  end;

  procedure invoke_(
    p_request varchar2,p_generation number,p_tic number,p_seq number,
    p_command raw,p_wait number default 30
  ) is
  begin
    doom_worker_api.step(session_,lineage_,p_generation,p_request,p_tic,p_seq,
      2,1,p_command,p_wait,status_,response_generation_,committed_tic_,
      committed_seq_,delta_version_,delta_count_,delta_sha_,state_sha_,
      frame_sha_,response_bytes_,response_sha_,delta_,payload_,error_);
  end;

  procedure assert_committed_(
    p_request varchar2,p_tic number,p_seq number
  ) is
    state_blob_ blob;stored_delta_ blob;stored_response_ blob;
    stored_state_ varchar2(64);stored_frame_ varchar2(64);
    bytes_ number;sha_ varchar2(64);
  begin
    assert_(status_='COMMITTED','request not committed '||p_request||' '||
      status_||' '||error_);
    assert_(committed_tic_=p_tic and committed_seq_=p_seq,
      'committed frontier '||p_request);
    assert_(delta_version_=1 and delta_count_=1 and
      regexp_like(delta_sha_,'^[0-9a-f]{64}$') and
      regexp_like(state_sha_,'^[0-9a-f]{64}$') and
      regexp_like(frame_sha_,'^[0-9a-f]{64}$') and
      regexp_like(response_sha_,'^[0-9a-f]{64}$'),
      'committed metadata '||p_request);
    assert_(response_bytes_=dbms_lob.getlength(payload_) and response_bytes_>0,
      'response bytes '||p_request);
    sha_:=lower(rawtohex(dbms_crypto.hash(payload_,dbms_crypto.hash_sh256)));
    assert_(sha_=response_sha_,'response SHA '||p_request);
    sha_:=lower(rawtohex(dbms_crypto.hash(delta_,dbms_crypto.hash_sh256)));
    assert_(sha_=delta_sha_,'delta SHA '||p_request);
    select state_blob,state_sha,frame_sha into state_blob_,stored_state_,stored_frame_
      from tic_commands where session_token=session_ and command_seq=p_seq;
    assert_(stored_state_=state_sha_ and stored_frame_=frame_sha_ and
      lower(rawtohex(dbms_crypto.hash(state_blob_,dbms_crypto.hash_sh256)))=state_sha_,
      'tic ledger metadata '||p_request);
    select delta_blob,response_blob,delta_bytes into stored_delta_,stored_response_,bytes_
      from doom_worker_result where request_id=p_request;
    assert_(dbms_lob.compare(stored_delta_,delta_)=0 and
      dbms_lob.compare(stored_response_,payload_)=0 and
      bytes_=dbms_lob.getlength(delta_),'durable result bytes '||p_request);
  end;

  procedure wait_stopped_ is
    running_ number;owned_ number;
  begin
    deadline_:=systimestamp+interval '30' second;
    loop
      select count(*) into running_ from user_scheduler_running_jobs
        where job_name like 'DOOM_UNIFIED_WORKER___';
      select count(*) into owned_ from doom_worker_control
        where target_session=session_;
      exit when running_=0 and owned_=0;
      if systimestamp>deadline_ then
        raise_application_error(-20000,'worker stop timeout');
      end if;
      dbms_session.sleep(.05);
    end loop;
  end;

  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop_all;exception when others then null;end;
    begin
      deadline_:=systimestamp+interval '15' second;
      loop
        select count(*) into count_ from user_scheduler_running_jobs
          where job_name like 'DOOM_UNIFIED_WORKER___';
        exit when count_=0 or systimestamp>deadline_;
        dbms_session.sleep(.05);
      end loop;
    exception when others then null;end;
    if session_ is not null then
      delete from game_sessions where session_token=session_;
    end if;
    delete from doom_worker_audit where request_id in(
      '10000000000000000000000000000001',
      '10000000000000000000000000000002',
      '10000000000000000000000000000003',
      '10000000000000000000000000000004',
      '10000000000000000000000000000005',
      '10000000000000000000000000000006',
      '10000000000000000000000000000007');
    delete from doom_worker_audit
      where request_id='10000000000000000000000000000008';
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null,last_error=null;
    update doom_config set number_value=0
      where config_key in('UNIFIED_WORKER_ENABLED','UNIFIED_WORKER_FAILPOINT');
    if old_wait_ is not null then
      update doom_config set number_value=old_wait_
        where config_key='UNIFIED_WORKER_WAIT_SECONDS';
    end if;
    if old_capacity_ is not null then
      update doom_config set number_value=old_capacity_
        where config_key='MAX_ACTIVE_SESSIONS';
    end if;
    commit;
  end;
begin
  select number_value into old_wait_ from doom_config
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  select number_value into old_capacity_ from doom_config
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=30
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  update doom_config set number_value=greatest(number_value,128)
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=0
    where config_key in('UNIFIED_WORKER_ENABLED','UNIFIED_WORKER_FAILPOINT');
  commit;

  doom_api.new_game(3,session_,initial_);
  select save_lineage,current_tic,last_command_seq into lineage_,tic_,seq_
    from game_sessions where session_token=session_;

  blocked_:=false;
  begin
    doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  exception when others then
    if sqlcode=-20720 then blocked_:=true;else raise;end if;
  end;
  assert_(blocked_,'default-off claim was accepted');
  dbms_output.put_line('unified_worker_default_off=PASS');

  update doom_config set number_value=1
    where config_key='UNIFIED_WORKER_ENABLED';
  commit;
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  assert_(ready_=1 and error_ is null and
    regexp_like(map_sha_,'^[0-9a-f]{64}$'),'worker load/warm readiness');
  -- OJVM statics are session-private: READY is published by the Scheduler
  -- session only after its combined load/warm succeeds. The first committed
  -- request below is the cross-session behavioral proof.
  assert_ready_(generation_,'startup combined recovery control');
  dbms_output.put_line('unified_worker_combined_ready=PASS generation='||generation_);

  invoke_('10000000000000000000000000000001',generation_,tic_,seq_,
    command_(seq_+1));
  assert_committed_('10000000000000000000000000000001',tic_+1,seq_+1);
  tic_:=committed_tic_;seq_:=committed_seq_;
  dbms_output.put_line('unified_worker_live_commit=PASS response_bytes='||
    response_bytes_);

  -- The completion signal has been consumed; exact replay comes from durable
  -- request/result rows and cannot advance the frontier again.
  invoke_('10000000000000000000000000000001',generation_,tic_-1,seq_-1,
    command_(seq_),0);
  assert_committed_('10000000000000000000000000000001',tic_,seq_);
  select current_tic,last_command_seq into committed_tic_,committed_seq_
    from game_sessions where session_token=session_;
  assert_(committed_tic_=tic_ and committed_seq_=seq_,'terminal replay advanced state');
  blocked_:=false;
  begin
    invoke_('10000000000000000000000000000001',generation_,tic_-1,seq_-1,
      command_(seq_,-1),0);
  exception when others then
    if sqlcode=-20721 then blocked_:=true;else raise;end if;
  end;
  assert_(blocked_,'conflicting duplicate request accepted');
  dbms_output.put_line('unified_worker_terminal_replay=PASS');

  -- Fail after Java prepare and after strict relational apply.  Both must roll
  -- SQL back and discard renderer/simulation pending state.
  for failpoint_ in 1..4 loop
    if failpoint_=2 then continue;end if;
    update doom_config set number_value=failpoint_
      where config_key='UNIFIED_WORKER_FAILPOINT';
    commit;
    invoke_(case failpoint_ when 1 then
        '10000000000000000000000000000002'
      when 3 then '10000000000000000000000000000003'
      else '10000000000000000000000000000008' end,
      generation_,tic_,seq_,command_(seq_+1));
    assert_(status_='FAILED' and
      ((failpoint_<>4 and response_generation_=generation_) or
       (failpoint_=4 and response_generation_>generation_)),
      'precommit failure terminal status '||failpoint_);
    if failpoint_=4 then generation_:=response_generation_;end if;
    select current_tic,last_command_seq into committed_tic_,committed_seq_
      from game_sessions where session_token=session_;
    assert_(committed_tic_=tic_ and committed_seq_=seq_,
      'precommit failure leaked frontier '||failpoint_);
    select count(*) into count_ from tic_commands
      where session_token=session_ and command_seq=seq_+1;
    assert_(count_=0,'precommit failure leaked ledger '||failpoint_);
    assert_ready_(generation_,'precommit discard/recovery control');
  end loop;
  dbms_output.put_line(
    'unified_worker_precommit_rollback_discard_recovery=PASS generation='||
    generation_);

  -- Commit succeeds but accept is failed deliberately.  The completion signal
  -- is held until combined SQL/renderer reconstruction advances generation.
  update doom_config set number_value=2
    where config_key='UNIFIED_WORKER_FAILPOINT';
  commit;
  invoke_('10000000000000000000000000000004',generation_,tic_,seq_,
    command_(seq_+1));
  assert_committed_('10000000000000000000000000000004',tic_+1,seq_+1);
  assert_(response_generation_>generation_,'postcommit recovery generation');
  generation_:=response_generation_;tic_:=committed_tic_;seq_:=committed_seq_;
  doom_worker_api.worker_status(session_,committed_tic_,ready_,state_sha_,
    deadline_,error_);
  assert_(committed_tic_=generation_ and ready_=1 and state_sha_=map_sha_ and
    error_ is null,'postcommit recovery control');
  assert_ready_(generation_,'postcommit combined recovery control');
  dbms_output.put_line('unified_worker_postcommit_recovery=PASS generation='||
    generation_);

  update doom_config set number_value=0
    where config_key='UNIFIED_WORKER_FAILPOINT';
  commit;
  invoke_('10000000000000000000000000000005',generation_,tic_,seq_,
    command_(seq_+1));
  assert_committed_('10000000000000000000000000000005',tic_+1,seq_+1);
  tic_:=committed_tic_;seq_:=committed_seq_;

  -- Restart reconstructs both owners before READY and fences the old generation.
  doom_unified_worker.request_stop(session_);
  wait_stopped_;
  committed_tic_:=generation_;
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  assert_(ready_=1 and generation_>committed_tic_ and error_ is null,
    'worker restart generation');
  blocked_:=false;
  begin
    invoke_('10000000000000000000000000000006',committed_tic_,tic_,seq_,
      command_(seq_+1),0);
  exception when others then
    if sqlcode=-20721 then blocked_:=true;else raise;end if;
  end;
  assert_(blocked_,'stale generation accepted');
  invoke_('10000000000000000000000000000007',generation_,tic_,seq_,
    command_(seq_+1));
  assert_committed_('10000000000000000000000000000007',tic_+1,seq_+1);
  dbms_output.put_line('unified_worker_restart_fence=PASS generation='||
    generation_);

  doom_unified_worker.request_stop(session_);
  wait_stopped_;
  cleanup_;
  dbms_output.put_line('UNIFIED_WORKER_LIVE_ACCEPTANCE_OK');
exception when others then
  error_:=sqlerrm||' '||dbms_utility.format_error_backtrace;
  cleanup_;
  raise_application_error(-20000,substr(error_,1,1900));
end;
/

exit
