-- Bounded retained-worker pool and AutoREST coordinator. Each active session
-- owns one fenced Scheduler slot; shared AQ consumers select only their slot's
-- correlation key. The installed execution handler remains rollback-only.

create or replace package doom_unified_worker authid definer as
  procedure run_slot(p_worker_slot in number);
  procedure start_worker(p_session in varchar2);
  procedure request_stop(p_session in varchar2);
  procedure request_stop_all;
end doom_unified_worker;
/

create or replace package body doom_unified_worker as
  c_disabled constant pls_integer:=-20720;
  c_invalid constant pls_integer:=-20721;
  c_capacity constant pls_integer:=-20722;
  c_max_slots constant pls_integer:=4;

  function config_number(p_key varchar2) return number is
    l_value number;
  begin
    select number_value into l_value from doom_config where config_key=p_key;
    return l_value;
  exception when no_data_found then
    raise_application_error(c_invalid,'missing worker configuration');
  end;

  function pool_size return pls_integer is
    l_size number:=config_number('UNIFIED_WORKER_POOL_SIZE');
  begin
    if l_size<>trunc(l_size) or l_size<1 or l_size>c_max_slots then
      raise_application_error(c_invalid,'invalid unified worker pool size');
    end if;
    return trunc(l_size);
  end;

  procedure require_enabled is
  begin
    if config_number('UNIFIED_WORKER_ENABLED')<>1 then
      raise_application_error(c_disabled,'unified worker is disabled');
    end if;
  end;

  procedure audit_event(
    p_request varchar2,p_slot number,p_generation number,p_event varchar2,
    p_detail varchar2 default null
  ) is
    pragma autonomous_transaction;
  begin
    insert into doom_worker_audit(
      request_id,worker_slot,generation,audit_event,detail)
    values(p_request,p_slot,p_generation,p_event,substr(p_detail,1,4000));
    commit;
  exception when others then rollback;
  end;

  procedure terminal_status(
    p_request varchar2,p_slot number,p_generation number,p_status varchar2,
    p_error varchar2
  ) is
    pragma autonomous_transaction;
  begin
    update doom_worker_request set request_status=p_status,
      response_generation=p_generation,error_text=substr(p_error,1,4000),
      completed_at=systimestamp
      where request_id=p_request and worker_slot=p_slot
        and request_status in('QUEUED','PROCESSING');
    commit;
  end;

  procedure respond(p_request varchar2) is
    l_options dbms_aq.enqueue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_payload raw(32767);l_message_id raw(16);
  begin
    l_options.visibility:=dbms_aq.immediate;
    l_properties.correlation:=p_request;
    l_payload:=utl_raw.cast_to_raw(p_request);
    dbms_aq.enqueue('DOOM_UNIFIED_RESPONSE_Q',l_options,l_properties,
      l_payload,l_message_id);
  end;

  procedure process_rollback_only(
    p_slot number,p_request varchar2,p_worker_generation in out number
  ) is
    l_request_slot number;l_session varchar2(32);l_lineage varchar2(64);
    l_generation number;l_expected_tic number;l_expected_seq number;
    l_status varchar2(16);l_target_session varchar2(32);
    l_target_lineage varchar2(64);l_ready number;l_db_lineage varchar2(64);
    l_db_tic number;l_db_seq number;l_error varchar2(4000);
  begin
    select worker_slot,session_token,save_lineage,generation,expected_tic,
      expected_command_seq,request_status
      into l_request_slot,l_session,l_lineage,l_generation,l_expected_tic,
        l_expected_seq,l_status
      from doom_worker_request where request_id=p_request for update;
    if l_status in('COMMITTED','ROLLED_BACK','FAILED') then rollback;return;end if;
    if l_request_slot<>p_slot then
      raise_application_error(c_invalid,'worker slot fence');
    end if;
    update doom_worker_request set request_status='PROCESSING'
      where request_id=p_request;

    select target_session,target_lineage,generation,ready
      into l_target_session,l_target_lineage,p_worker_generation,l_ready
      from doom_worker_control where worker_slot=p_slot for update;
    if l_ready<>1 or l_generation<>p_worker_generation or
       l_session<>l_target_session or l_lineage<>l_target_lineage then
      raise_application_error(c_invalid,'worker control fence');
    end if;
    select save_lineage,current_tic,last_command_seq
      into l_db_lineage,l_db_tic,l_db_seq from game_sessions
      where session_token=l_session for update;
    if l_db_lineage<>l_lineage or l_db_tic<>l_expected_tic or
       l_db_seq<>l_expected_seq then
      raise_application_error(c_invalid,'database frontier fence');
    end if;

    rollback;
    terminal_status(p_request,p_slot,p_worker_generation,'ROLLED_BACK',
      'rollback-only worker: no simulation mutation installed');
    audit_event(p_request,p_slot,p_worker_generation,'ROLLBACK_ONLY');
  exception when others then
    l_error:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    rollback;
    terminal_status(p_request,p_slot,p_worker_generation,'FAILED',l_error);
    audit_event(p_request,p_slot,p_worker_generation,'FAILED',l_error);
  end;

  procedure run_slot(p_worker_slot in number) is
    l_dequeue dbms_aq.dequeue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_payload raw(32767);l_message_id raw(16);l_request varchar2(32);
    l_generation number;l_stop number:=0;l_target varchar2(32);
    l_failure varchar2(4000);l_limit pls_integer;
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    require_enabled;l_limit:=pool_size;
    if p_worker_slot<1 or p_worker_slot>l_limit then
      raise_application_error(c_invalid,'worker slot is outside configured pool');
    end if;
    select generation,target_session into l_generation,l_target
      from doom_worker_control where worker_slot=p_worker_slot for update;
    if l_target is null then
      raise_application_error(c_invalid,'worker target is not configured');
    end if;
    l_generation:=l_generation+1;
    update doom_worker_control set generation=l_generation,ready=1,
      stop_requested=0,worker_sid=sys_context('USERENV','SID'),
      heartbeat=systimestamp,last_error=null where worker_slot=p_worker_slot;
    commit;
    audit_event(null,p_worker_slot,l_generation,'WORKER_READY',l_target);

    l_dequeue.wait:=1;l_dequeue.visibility:=dbms_aq.immediate;
    l_dequeue.navigation:=dbms_aq.first_message;
    l_dequeue.correlation:='SLOT_'||to_char(p_worker_slot,'FM00');
    loop
      begin
        dbms_aq.dequeue('DOOM_UNIFIED_REQUEST_Q',l_dequeue,l_properties,
          l_payload,l_message_id);
        l_request:=utl_raw.cast_to_varchar2(l_payload);
        process_rollback_only(p_worker_slot,l_request,l_generation);
        update doom_worker_control set heartbeat=systimestamp
          where worker_slot=p_worker_slot;
        commit;
        respond(l_request);
      exception when no_messages then null;
      end;
      select stop_requested into l_stop from doom_worker_control
        where worker_slot=p_worker_slot;
      exit when l_stop=1;
    end loop;
    update doom_worker_control set ready=0,stop_requested=0,worker_sid=null,
      target_session=null,target_lineage=null,heartbeat=systimestamp
      where worker_slot=p_worker_slot;
    commit;
    audit_event(null,p_worker_slot,l_generation,'WORKER_STOP',l_target);
  exception when others then
    l_failure:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    begin
      update doom_worker_control set ready=0,stop_requested=0,worker_sid=null,
        target_session=null,target_lineage=null,last_error=l_failure,
        heartbeat=systimestamp where worker_slot=p_worker_slot;
      commit;
      audit_event(null,p_worker_slot,l_generation,'WORKER_FATAL',l_failure);
    exception when others then null;end;
  end;

  procedure start_worker(p_session in varchar2) is
    l_lineage varchar2(64);l_slot number;l_running number;l_limit pls_integer;
  begin
    require_enabled;l_limit:=pool_size;
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
      raise_application_error(c_invalid,'invalid worker session');
    end if;
    select save_lineage into l_lineage from game_sessions
      where session_token=p_session;
    begin
      select worker_slot,ready into l_slot,l_running from doom_worker_control
        where target_session=p_session for update;
      if l_running=1 then return;end if;
    exception when no_data_found then
      l_slot:=null;
      for candidate in (
        select worker_slot from doom_worker_control
        where target_session is null and worker_slot<=l_limit
        order by worker_slot for update skip locked
      ) loop
        l_slot:=candidate.worker_slot;exit;
      end loop;
      if l_slot is null then
        raise_application_error(c_capacity,'unified worker pool is full');
      end if;
    end;
    select count(*) into l_running from user_scheduler_running_jobs
      where job_name='DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00');
    if l_running<>0 then
      raise_application_error(c_invalid,'worker slot is already running');
    end if;
    update doom_worker_control set target_session=p_session,
      target_lineage=l_lineage,ready=0,stop_requested=0,last_error=null
      where worker_slot=l_slot;
    commit;
    begin
      dbms_scheduler.run_job(
        'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),false);
    exception when others then
      update doom_worker_control set target_session=null,target_lineage=null
        where worker_slot=l_slot and ready=0 and target_session=p_session;
      commit;raise;
    end;
  exception when no_data_found then
    rollback;raise_application_error(c_invalid,'unknown worker session');
  end;

  procedure request_stop(p_session in varchar2) is
    pragma autonomous_transaction;
  begin
    update doom_worker_control set stop_requested=1
      where target_session=p_session and ready=1;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'worker session is not active');
    end if;
    commit;
  end;

  procedure request_stop_all is
    pragma autonomous_transaction;
  begin
    update doom_worker_control set stop_requested=1 where ready=1;
    commit;
  end;
end doom_unified_worker;
/

create or replace package doom_worker_api authid definer as
  procedure claim(
    p_session in varchar2,p_generation out number,p_ready out number,
    p_error out varchar2);

  procedure worker_status(
    p_session in varchar2,p_generation out number,p_ready out number,
    p_heartbeat out timestamp with time zone,p_error out varchar2);

  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_request in varchar2,p_expected_tic in number,p_expected_seq in number,
    p_command_version in number,p_command_count in number,p_command in raw,
    p_wait_seconds in number,
    p_status out varchar2,p_response_generation out number,
    p_committed_tic out number,p_committed_seq out number,
    p_delta_version out number,p_delta_count out number,
    p_delta_sha out varchar2,p_delta out blob,p_payload out blob,
    p_error out varchar2);
end doom_worker_api;
/

create or replace package body doom_worker_api as
  c_disabled constant pls_integer:=-20720;
  c_invalid constant pls_integer:=-20721;

  function config_number(p_key varchar2) return number is
    l_value number;
  begin
    select number_value into l_value from doom_config where config_key=p_key;
    return l_value;
  exception when no_data_found then
    raise_application_error(c_invalid,'missing worker configuration');
  end;

  procedure require_enabled is
  begin
    if config_number('UNIFIED_WORKER_ENABLED')<>1 then
      raise_application_error(c_disabled,'unified worker is disabled');
    end if;
  end;

  procedure submit_request(
    p_session varchar2,p_lineage varchar2,p_generation number,p_request varchar2,
    p_expected_tic number,p_expected_seq number,p_command_version number,
    p_command_count number,p_command raw,p_status out varchar2
  ) is
    pragma autonomous_transaction;
    l_options dbms_aq.enqueue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_message_id raw(16);l_payload raw(32767);l_sha varchar2(64);
    l_slot number;l_session varchar2(32);l_lineage varchar2(64);
    l_generation number;l_tic number;l_seq number;l_version number;
    l_count number;l_command raw(2000);
  begin
    require_enabled;
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') or
       p_lineage is null or not regexp_like(p_lineage,'^[0-9a-f]{64}$') or
       p_request is null or not regexp_like(p_request,'^[0-9a-f]{32}$') or
       p_generation<1 or p_expected_tic<0 or p_expected_seq<0 or
       p_command_version not between 1 and 255 or
       p_command_count not between 1 and 255 or p_command is null or
       utl_raw.length(p_command)>least(2000,
         config_number('UNIFIED_WORKER_MAX_PACK_BYTES')) then
      raise_application_error(c_invalid,'invalid unified worker request');
    end if;
    -- Terminal idempotency is a durable request property, not a worker-cache
    -- property. Resolve exact existing requests before applying the current
    -- slot/generation fence so a lost response can replay after reconstruction.
    begin
      select worker_slot,session_token,save_lineage,generation,expected_tic,
        expected_command_seq,command_version,command_count,command_pack,
        request_status
        into l_slot,l_session,l_lineage,l_generation,l_tic,l_seq,l_version,
          l_count,l_command,p_status
        from doom_worker_request where request_id=p_request;
      if l_session<>p_session or l_lineage<>p_lineage or
         l_generation<>p_generation or l_tic<>p_expected_tic or
         l_seq<>p_expected_seq or l_version<>p_command_version or
         l_count<>p_command_count or utl_raw.compare(l_command,p_command)<>0 then
        raise_application_error(c_invalid,'conflicting duplicate request');
      end if;
      if p_status in('COMMITTED','ROLLED_BACK','FAILED') then commit;return;end if;
    exception when no_data_found then null;
    end;
    begin
      select worker_slot into l_slot from doom_worker_control
        where target_session=p_session and target_lineage=p_lineage
          and generation=p_generation and ready=1;
    exception when no_data_found then
      raise_application_error(c_invalid,'worker ownership fence');
    end;
    select lower(rawtohex(standard_hash(p_command,'SHA256'))) into l_sha from dual;
    begin
      insert into doom_worker_request(request_id,worker_slot,session_token,
        save_lineage,generation,expected_tic,expected_command_seq,command_version,
        command_count,command_bytes,command_sha,command_pack,request_status,created_at)
      values(p_request,l_slot,p_session,p_lineage,p_generation,p_expected_tic,
        p_expected_seq,p_command_version,p_command_count,utl_raw.length(p_command),
        l_sha,p_command,'QUEUED',systimestamp);
      l_options.visibility:=dbms_aq.immediate;
      l_properties.correlation:='SLOT_'||to_char(l_slot,'FM00');
      l_payload:=utl_raw.cast_to_raw(p_request);
      dbms_aq.enqueue('DOOM_UNIFIED_REQUEST_Q',l_options,l_properties,
        l_payload,l_message_id);
      p_status:='QUEUED';commit;
    exception when dup_val_on_index then
      select worker_slot,session_token,save_lineage,generation,expected_tic,
        expected_command_seq,command_version,command_count,command_pack,request_status
        into l_slot,l_session,l_lineage,l_generation,l_tic,l_seq,l_version,
          l_count,l_command,p_status
        from doom_worker_request where request_id=p_request;
      if l_session<>p_session or l_lineage<>p_lineage or
         l_generation<>p_generation or l_tic<>p_expected_tic or
         l_seq<>p_expected_seq or l_version<>p_command_version or
         l_count<>p_command_count or utl_raw.compare(l_command,p_command)<>0 then
        raise_application_error(c_invalid,'conflicting duplicate request');
      end if;
      commit;
    end;
  end;

  procedure worker_status(
    p_session in varchar2,p_generation out number,p_ready out number,
    p_heartbeat out timestamp with time zone,p_error out varchar2
  ) is
  begin
    require_enabled;
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
      raise_application_error(c_invalid,'invalid worker session');
    end if;
    select generation,ready,heartbeat,last_error
      into p_generation,p_ready,p_heartbeat,p_error
      from doom_worker_control where target_session=p_session;
  exception when no_data_found then
    raise_application_error(c_invalid,'worker session is not active');
  end;

  procedure claim(
    p_session in varchar2,p_generation out number,p_ready out number,
    p_error out varchar2
  ) is
    l_heartbeat timestamp with time zone;
    l_deadline timestamp with time zone;
  begin
    require_enabled;
    doom_unified_worker.start_worker(p_session);
    l_deadline:=systimestamp+
      numtodsinterval(config_number('UNIFIED_WORKER_WAIT_SECONDS'),'SECOND');
    loop
      begin
        worker_status(p_session,p_generation,p_ready,l_heartbeat,p_error);
        exit when p_ready=1 or p_error is not null;
      exception when others then
        if sqlcode<>c_invalid then raise;end if;
      end;
      if systimestamp>=l_deadline then
        p_generation:=null;p_ready:=0;p_error:='worker claim timeout';return;
      end if;
      dbms_session.sleep(.05);
    end loop;
  end;

  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_request in varchar2,p_expected_tic in number,p_expected_seq in number,
    p_command_version in number,p_command_count in number,p_command in raw,
    p_wait_seconds in number,p_status out varchar2,p_response_generation out number,
    p_committed_tic out number,p_committed_seq out number,
    p_delta_version out number,p_delta_count out number,p_delta_sha out varchar2,
    p_delta out blob,p_payload out blob,p_error out varchar2
  ) is
    l_status varchar2(16);l_max_wait number;
    l_dequeue dbms_aq.dequeue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_response raw(32767);l_message_id raw(16);
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    p_committed_tic:=null;p_committed_seq:=null;p_delta_version:=null;
    p_delta_count:=null;p_delta_sha:=null;p_delta:=null;p_payload:=null;p_error:=null;
    l_max_wait:=config_number('UNIFIED_WORKER_WAIT_SECONDS');
    if p_wait_seconds is null or p_wait_seconds<0 or p_wait_seconds>l_max_wait then
      raise_application_error(c_invalid,'invalid worker wait');
    end if;
    submit_request(p_session,p_lineage,p_generation,p_request,p_expected_tic,
      p_expected_seq,p_command_version,p_command_count,p_command,l_status);
    l_dequeue.wait:=case when l_status in('COMMITTED','ROLLED_BACK','FAILED')
      then 0 else trunc(p_wait_seconds) end;
    l_dequeue.visibility:=dbms_aq.immediate;
    l_dequeue.navigation:=dbms_aq.first_message;
    l_dequeue.correlation:=p_request;
    begin
      dbms_aq.dequeue('DOOM_UNIFIED_RESPONSE_Q',l_dequeue,l_properties,
        l_response,l_message_id);
    exception when no_messages then null;
    end;
    select request_status,response_generation,error_text
      into p_status,p_response_generation,p_error
      from doom_worker_request where request_id=p_request;
    if p_status='COMMITTED' then
      select committed_tic,committed_command_seq,delta_version,delta_count,
        delta_sha,delta_blob,response_blob
        into p_committed_tic,p_committed_seq,p_delta_version,p_delta_count,
          p_delta_sha,p_delta,p_payload
        from doom_worker_result where request_id=p_request;
    end if;
  end;
end doom_worker_api;
/

begin
  for l_slot in 1..4 loop
    dbms_scheduler.create_job(
      job_name=>'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),
      job_type=>'PLSQL_BLOCK',
      job_action=>'begin doom_unified_worker.run_slot('||to_char(l_slot)||'); end;',
      enabled=>false,auto_drop=>false);
  end loop;
end;
/
