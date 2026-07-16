whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Production-shaped database-side latency: one persistent Scheduler/OJVM
-- owner, transactional AQ rendezvous, canonical state, durable delta/history,
-- direct render/codec/BLOB, commit, accept, and correlated response lookup.
declare
  c_warm constant pls_integer:=30;
  c_samples constant pls_integer:=300;
  session_ varchar2(32);lineage_ varchar2(64);initial_ blob;
  generation_ number;ready_ number;map_sha_ varchar2(64);error_ varchar2(4000);
  status_ varchar2(16);response_generation_ number;committed_tic_ number;
  committed_seq_ number;delta_version_ number;delta_count_ number;
  delta_sha_ varchar2(64);state_sha_ varchar2(64);frame_sha_ varchar2(64);
  response_bytes_ number;response_sha_ varchar2(64);delta_ blob;payload_ blob;
  tic_ number;seq_ number;old_wait_ number;old_capacity_ number;old_parity_ number;count_ number;
  history_interval_ number;
  started_ timestamp with time zone;samples_ sys.odcinumberlist:=sys.odcinumberlist();
  checkpoint_samples_ sys.odcinumberlist:=sys.odcinumberlist();
  regular_samples_ sys.odcinumberlist:=sys.odcinumberlist();
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
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    commit;
  end;
begin
  select number_value into old_wait_ from doom_config
    where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  select number_value into old_capacity_ from doom_config
    where config_key='MAX_ACTIVE_SESSIONS';
  select number_value into old_parity_ from doom_config
    where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  select number_value into history_interval_ from doom_config
    where config_key='HISTORY_SNAPSHOT_INTERVAL';
  update doom_config set number_value=30 where config_key='UNIFIED_WORKER_WAIT_SECONDS';
  update doom_config set number_value=greatest(number_value,128)
    where config_key='MAX_ACTIVE_SESSIONS';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_FAILPOINT';
  update doom_config set number_value=c_warm+c_samples
    where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
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
      if mod(committed_tic_,history_interval_)=0 then checkpoint_samples_.extend;
        checkpoint_samples_(checkpoint_samples_.count):=samples_(samples_.count);
      else regular_samples_.extend;
        regular_samples_(regular_samples_.count):=samples_(samples_.count);end if;
    end if;
  end loop;
  select count(*) into count_ from tic_commands c
    where c.session_token=session_ and c.lineage=lineage_
      and c.command_seq between 1 and tic_
      and ((mod(c.tic,history_interval_)=0 and
            (dbms_lob.getlength(c.state_blob)=0 or c.state_sha<>
              lower(rawtohex(dbms_crypto.hash(c.state_blob,dbms_crypto.hash_sh256)))))
        or (mod(c.tic,history_interval_)<>0 and
            (dbms_lob.getlength(c.state_blob)<>0 or c.state_sha<>
              (select lower(rawtohex(dbms_crypto.hash(utl_i18n.string_to_raw(
                'DOOM_STATE_CHAIN_V1|'||lineage_||'|'||
                to_char(c.tic,'TM9','NLS_NUMERIC_CHARACTERS=''.,''')||'|'||
                c.command_sha||'|'||x.delta_sha,'AL32UTF8'),dbms_crypto.hash_sh256)))
               from doom_worker_request r join doom_worker_result x
                 on x.request_id=r.request_id
               where r.session_token=session_ and x.committed_command_seq=c.command_seq))));
  if count_<>0 then raise_application_error(-20000,'checkpoint state contract mismatches='||count_);end if;
  select count(*) into count_ from tic_commands
    where session_token=session_ and lineage=lineage_
      and mod(tic,history_interval_)=0 and command_seq between 1 and tic_;
  if count_<>floor(tic_/history_interval_) then
    raise_application_error(-20000,'checkpoint state count='||count_);
  end if;
  dbms_output.put_line('unified_worker_checkpoint_state_contract=OK|'||count_||'|'||history_interval_);
  select count(*) into count_ from (
    select e.*,lag(event_sha,1,rpad('0',64,'0')) over(
      order by tic,event_ordinal) expected_previous
    from game_events e where session_token=session_ and lineage=lineage_
  ) where previous_event_sha<>expected_previous or event_sha<>
    lower(rawtohex(dbms_crypto.hash(json_object(
      'lineage' value lineage,'tic' value tic,'ordinal' value event_ordinal,
      'type' value event_type,'actor' value actor_mobj_id,'target' value target_mobj_id,
      'number' value number_value,'text' value text_value,
      'previous_event_sha' value previous_event_sha returning clob),
      dbms_crypto.hash_sh256)));
  if count_<>0 then raise_application_error(-20000,'event chain mismatches='||count_);end if;
  select count(*) into count_ from history_heads h where h.session_token=session_
    and h.lineage=lineage_ and h.event_sha<>coalesce((select event_sha from game_events
      where session_token=session_ and lineage=lineage_
      order by tic desc,event_ordinal desc fetch first 1 row only),rpad('0',64,'0'));
  if count_<>0 then raise_application_error(-20000,'event head mismatch');end if;
  dbms_output.put_line('unified_worker_event_chain_contract=OK');
  select detail into error_ from doom_worker_audit
    where request_id=(select r.request_id from doom_worker_request r
      join doom_worker_result x on x.request_id=r.request_id
      where r.session_token=session_ and x.committed_tic=tic_)
      and audit_event='PARITY_OK';
  dbms_output.put_line('unified_worker_owner_sql_parity='||error_);
  select percentile_cont(.5) within group(order by column_value),
    percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(samples_);
  dbms_output.put_line('UNIFIED_WORKER_LIVE_BENCHMARK_OK samples='||samples_.count||
    ' frontier='||tic_||'|'||seq_||' generation='||generation_||
    ' response_bytes='||min_bytes_||'|'||max_bytes_);
  dbms_output.put_line('unified_worker_caller_ms='||round(p50_,3)||'|'||
    round(p95_,3)||'|'||round(max_,3));
  select percentile_cont(.5) within group(order by column_value),
    percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(checkpoint_samples_);
  dbms_output.put_line('unified_worker_caller_checkpoint_ms='||round(p50_,3)||'|'||
    round(p95_,3)||'|'||round(max_,3));
  select percentile_cont(.5) within group(order by column_value),
    percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(regular_samples_);
  dbms_output.put_line('unified_worker_caller_regular_ms='||round(p50_,3)||'|'||
    round(p95_,3)||'|'||round(max_,3));
  for stage_ in (
    with measured as (
      select x.committed_tic,x.prepare_us,x.apply_us,x.state_us,x.state_encode_us,
        x.state_blob_us,x.state_compare_us,x.state_object_encode_us,x.state_changed,
        x.state_reused,x.state_removed,x.render_us,x.render_call_us,x.render_update_us,
        x.render_kernel_us,x.codec_us,x.blob_us,x.response_copy_us,x.response_hash_us,
        x.history_us,x.history_encode_us,x.history_blob_us,x.history_persist_us,x.finalize_us,
        x.commit_us,
        row_number() over(order by r.created_at,r.request_id) sample_no
      from doom_worker_request r join doom_worker_result x
        on x.request_id=r.request_id
      where r.session_token=session_ and r.request_status='COMMITTED'
    ), values_ as (
      select 'prepare' stage,prepare_us/1000 value from measured where sample_no>c_warm
      union all select 'apply',apply_us/1000 from measured where sample_no>c_warm
      union all select 'state',state_us/1000 from measured where sample_no>c_warm
      union all select 'state_encode',state_encode_us/1000 from measured where sample_no>c_warm
      union all select 'state_blob',state_blob_us/1000 from measured where sample_no>c_warm
      union all select 'state_compare',state_compare_us/1000 from measured where sample_no>c_warm
      union all select 'state_object_encode',state_object_encode_us/1000 from measured where sample_no>c_warm
      union all select 'state_changed',state_changed from measured where sample_no>c_warm
      union all select 'state_reused',state_reused from measured where sample_no>c_warm
      union all select 'state_removed',state_removed from measured where sample_no>c_warm
      union all select 'render',render_us/1000 from measured where sample_no>c_warm
      union all select 'render_call',render_call_us/1000 from measured where sample_no>c_warm
      union all select 'render_update',render_update_us/1000 from measured where sample_no>c_warm
      union all select 'render_other',greatest(render_us-render_kernel_us-
        codec_us-blob_us,0)/1000 from measured where sample_no>c_warm
      union all select 'render_kernel',render_kernel_us/1000 from measured where sample_no>c_warm
      union all select 'codec',codec_us/1000 from measured where sample_no>c_warm
      union all select 'blob',blob_us/1000 from measured where sample_no>c_warm
      union all select 'response_copy',response_copy_us/1000 from measured where sample_no>c_warm
      union all select 'response_hash',response_hash_us/1000 from measured where sample_no>c_warm
      union all select 'history',history_us/1000 from measured
        where sample_no>c_warm and history_us is not null
      union all select 'history_encode',history_encode_us/1000 from measured
        where sample_no>c_warm and history_encode_us is not null
      union all select 'history_blob',history_blob_us/1000 from measured
        where sample_no>c_warm and history_blob_us is not null
      union all select 'history_persist',history_persist_us/1000 from measured
        where sample_no>c_warm and history_persist_us is not null
      union all select 'finalize',finalize_us/1000 from measured where sample_no>c_warm
      union all select 'finalize_checkpoint',finalize_us/1000 from measured
        where sample_no>c_warm and history_us is not null
      union all select 'finalize_regular',finalize_us/1000 from measured
        where sample_no>c_warm and history_us is null
      union all select 'commit',commit_us/1000 from measured where sample_no>c_warm
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
