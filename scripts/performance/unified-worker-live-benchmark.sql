whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Production-shaped database-side latency: one persistent Scheduler/OJVM
-- owner, transactional AQ rendezvous, canonical state, durable delta/history,
-- direct render/codec/BLOB, commit, accept, and correlated response lookup.
declare
  c_warm constant pls_integer:=500;
  c_samples constant pls_integer:=300;
  session_ varchar2(32);lineage_ varchar2(64);initial_ blob;
  generation_ number;ready_ number;map_sha_ varchar2(64);error_ varchar2(4000);
  status_ varchar2(16);response_generation_ number;committed_tic_ number;
  committed_seq_ number;delta_version_ number;delta_count_ number;
  delta_sha_ varchar2(64);state_sha_ varchar2(64);frame_sha_ varchar2(64);
  response_bytes_ number;response_sha_ varchar2(64);delta_ blob;payload_ blob;
  tic_ number;seq_ number;old_wait_ number;old_capacity_ number;count_ number;
  started_ timestamp with time zone;samples_ sys.odcinumberlist:=sys.odcinumberlist();
  p50_ number;p95_ number;max_ number;min_bytes_ number:=null;max_bytes_ number:=0;
  deadline_ timestamp with time zone;

  function elapsed_ms_(p_started timestamp with time zone) return number is
    span_ interval day to second:=systimestamp-p_started;
  begin
    return (extract(day from span_)*86400+extract(hour from span_)*3600+
      extract(minute from span_)*60+extract(second from span_))*1000;
  end;

  function command_(p_seq number) return raw is
    turn_ varchar2(2);strafe_ varchar2(2);run_ varchar2(2);
  begin
    turn_:=case mod(p_seq,9) when 0 then '01' when 4 then 'ff' else '00' end;
    strafe_:=case when mod(p_seq,17)=0 then '01' else '00' end;
    run_:=case when mod(p_seq,5)=0 then '01' else '00' end;
    return hextoraw('444d53430201000000000000'||
      lpad(to_char(p_seq,'fmxxxxxxxx'),8,'0')||turn_||'01'||strafe_||run_||
      '00000000');
  end;

  procedure cleanup_ is
  begin
    begin doom_unified_worker.request_stop_all;exception when others then null;end;
    begin
      deadline_:=systimestamp+interval '20' second;
      loop
        select count(*) into count_ from user_scheduler_running_jobs
          where job_name like 'DOOM_UNIFIED_WORKER___';
        exit when count_=0 or systimestamp>deadline_;
        dbms_session.sleep(.05);
      end loop;
    exception when others then null;end;
    if session_ is not null then delete from game_sessions where session_token=session_;end if;
    update doom_worker_control set target_session=null,target_lineage=null,
      state_map_sha=null,ready=0,stop_requested=0,worker_sid=null,last_error=null;
    update doom_config set number_value=0
      where config_key in('UNIFIED_WORKER_ENABLED','UNIFIED_WORKER_FAILPOINT');
    if old_wait_ is not null then update doom_config set number_value=old_wait_
      where config_key='UNIFIED_WORKER_WAIT_SECONDS';end if;
    if old_capacity_ is not null then update doom_config set number_value=old_capacity_
      where config_key='MAX_ACTIVE_SESSIONS';end if;
    commit;
  end;
begin
  select number_value into old_wait_ from doom_config
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  select number_value into old_capacity_ from doom_config
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=30 where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  update doom_config set number_value=greatest(number_value,128)
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';
  commit;

  doom_api.new_game(3,session_,initial_);
  select save_lineage,current_tic,last_command_seq into lineage_,tic_,seq_
    from game_sessions where session_token=session_;
  doom_worker_api.claim(session_,generation_,ready_,map_sha_,error_);
  if ready_<>1 or error_ is not null then
    raise_application_error(-20000,'worker benchmark claim '||error_);
  end if;

  for sample_ in 1..c_warm+c_samples loop
    started_:=systimestamp;
    doom_worker_api.step(session_,lineage_,generation_,lower(rawtohex(sys_guid())),
      tic_,seq_,2,1,command_(seq_+1),30,status_,response_generation_,committed_tic_,
      committed_seq_,delta_version_,delta_count_,delta_sha_,state_sha_,frame_sha_,
      response_bytes_,response_sha_,delta_,payload_,error_);
    if status_<>'COMMITTED' or error_ is not null or committed_tic_<>tic_+1 or
       committed_seq_<>seq_+1 or response_generation_<>generation_ or
       delta_version_<>1 or delta_count_<>1 or response_bytes_<=0 or
       response_bytes_<>dbms_lob.getlength(payload_) or
       lower(rawtohex(dbms_crypto.hash(payload_,dbms_crypto.hash_sh256)))<>response_sha_ then
      raise_application_error(-20000,'worker benchmark mismatch sample='||sample_||
        ' status='||status_||' error='||error_);
    end if;
    tic_:=committed_tic_;seq_:=committed_seq_;
    min_bytes_:=case when min_bytes_ is null then response_bytes_
      else least(min_bytes_,response_bytes_) end;
    max_bytes_:=greatest(max_bytes_,response_bytes_);
    if sample_>c_warm then
      samples_.extend;samples_(samples_.count):=elapsed_ms_(started_);
    end if;
  end loop;
  select percentile_cont(.5) within group(order by column_value),
    percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(samples_);
  dbms_output.put_line('UNIFIED_WORKER_LIVE_BENCHMARK_OK samples='||samples_.count||
    ' frontier='||tic_||'|'||seq_||' generation='||generation_||
    ' response_bytes='||min_bytes_||'|'||max_bytes_);
  dbms_output.put_line('unified_worker_caller_ms='||round(p50_,3)||'|'||
    round(p95_,3)||'|'||round(max_,3));
  for stage_ in (
    with measured as (
      select x.committed_tic,x.prepare_us,x.apply_us,x.state_us,x.render_us,x.render_kernel_us,
        x.codec_us,x.blob_us,x.finalize_us,
        row_number() over(order by r.created_at,r.request_id) sample_no
      from doom_worker_request r join doom_worker_result x
        on x.request_id=r.request_id
      where r.session_token=session_ and r.request_status='COMMITTED'
    ), values_ as (
      select 'prepare' stage,prepare_us/1000 value from measured where sample_no>500
      union all select 'apply',apply_us/1000 from measured where sample_no>500
      union all select 'state',state_us/1000 from measured where sample_no>500
      union all select 'render',render_us/1000 from measured where sample_no>500
      union all select 'render_kernel',render_kernel_us/1000 from measured where sample_no>500
      union all select 'codec',codec_us/1000 from measured where sample_no>500
      union all select 'blob',blob_us/1000 from measured where sample_no>500
      union all select 'finalize',finalize_us/1000 from measured where sample_no>500
      union all select 'finalize_checkpoint',finalize_us/1000 from measured
        where sample_no>500 and mod(committed_tic,4)=0
      union all select 'finalize_regular',finalize_us/1000 from measured
        where sample_no>500 and mod(committed_tic,4)<>0
    )
    select stage,percentile_cont(.5) within group(order by value) p50,
      percentile_cont(.95) within group(order by value) p95,max(value) maximum
    from values_ group by stage order by stage
  ) loop
    dbms_output.put_line('unified_worker_'||stage_.stage||'_ms='||
      round(stage_.p50,3)||'|'||round(stage_.p95,3)||'|'||round(stage_.maximum,3));
  end loop;
  cleanup_;
exception when others then
  error_:=sqlerrm||' '||dbms_utility.format_error_backtrace;
  cleanup_;
  raise_application_error(-20000,substr(error_,1,1900));
end;
/

exit
