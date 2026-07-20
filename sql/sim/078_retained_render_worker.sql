-- Default-off resident renderer used to overlap exact frame generation with
-- authoritative relational apply. AQ carries only a bounded packed delta;
-- the staged response remains pending until simulation explicitly decides it.

create or replace package doom_render_worker authid definer as
  procedure run_slot(p_worker_slot in number);
  procedure start_worker(
    p_worker_slot in number,p_session in varchar2,p_lineage in varchar2,
    p_state_map_sha in varchar2);
  procedure enqueue_stage(
    p_worker_slot in number,p_request in varchar2,p_state_sha in varchar2,
    p_render_pack in raw);
  procedure await_stage(
    p_request in varchar2,p_wait_ms in number,p_status out varchar2,
    p_frame_sha out varchar2,p_response_bytes out number,
    p_response_sha out varchar2,p_payload out blob,p_error out varchar2);
  procedure decide(p_request in varchar2,p_decision in varchar2);
  procedure request_stop(p_session in varchar2);
end doom_render_worker;
/

create or replace package body doom_render_worker as
  c_invalid constant pls_integer:=-20731;
  c_payload_prefix constant pls_integer:=96;

  function config_number(p_key varchar2) return number is l_value number;
  begin select number_value into l_value from doom_config where config_key=p_key;return l_value;
  exception when no_data_found then raise_application_error(c_invalid,'missing render-worker configuration');end;

  function elapsed_us(p_started timestamp with time zone) return number is
    l_span interval day to second:=systimestamp-p_started;
  begin return round((extract(day from l_span)*86400+extract(hour from l_span)*3600+
    extract(minute from l_span)*60+extract(second from l_span))*1000000);end;

  procedure require_ok(p_value varchar2,p_label varchar2) is
  begin if p_value is null or p_value not like 'OK%' then
    raise_application_error(c_invalid,p_label||': '||substr(p_value,1,3000));end if;end;

  procedure mark_failed(
    p_request varchar2,p_slot number,p_generation number,p_error varchar2
  ) is pragma autonomous_transaction;
  begin
    update doom_render_stage set stage_status='FAILED',error_text=substr(p_error,1,4000),
      decided_at=systimestamp where request_id=p_request and render_slot=p_slot
      and render_generation=p_generation and stage_status not in('ACCEPTED','DISCARDED');
    commit;
  exception when others then rollback;
  end;

  procedure enqueue_stage(
    p_worker_slot in number,p_request in varchar2,p_state_sha in varchar2,
    p_render_pack in raw
  ) is
    pragma autonomous_transaction;
    l_options dbms_aq.enqueue_options_t;l_properties dbms_aq.message_properties_t;
    l_payload raw(32767);l_message_id raw(16);l_bytes pls_integer;
  begin
    l_bytes:=utl_raw.length(p_render_pack);
    if p_worker_slot not between 1 and 4 or
       not regexp_like(p_request,'^[0-9a-f]{32}$') or
       not regexp_like(p_state_sha,'^[0-9a-f]{64}$') or
       l_bytes is null or l_bytes<1 or l_bytes>32671 then
      raise_application_error(c_invalid,'invalid render task envelope');
    end if;
    l_payload:=utl_raw.concat(utl_raw.cast_to_raw(p_request),
      utl_raw.cast_to_raw(p_state_sha),p_render_pack);
    l_options.visibility:=dbms_aq.immediate;
    l_properties.correlation:='SLOT_'||to_char(p_worker_slot,'FM00');
    dbms_aq.enqueue('DOOM_RENDER_TASK_Q',l_options,l_properties,l_payload,l_message_id);
    commit;
  exception when others then rollback;raise;
  end;

  procedure await_stage(
    p_request in varchar2,p_wait_ms in number,p_status out varchar2,
    p_frame_sha out varchar2,p_response_bytes out number,
    p_response_sha out varchar2,p_payload out blob,p_error out varchar2
  ) is
    l_started timestamp with time zone:=systimestamp;
  begin
    if p_wait_ms<1 or p_wait_ms>5000 then raise_application_error(c_invalid,'invalid render wait');end if;
    loop
      begin
        select stage_status,frame_sha,response_bytes,response_sha,response_blob,error_text
          into p_status,p_frame_sha,p_response_bytes,p_response_sha,p_payload,p_error
          from doom_render_stage where request_id=p_request;
        return;
      exception when no_data_found then null;end;
      if elapsed_us(l_started)>=p_wait_ms*1000 then p_status:='TIMEOUT';p_error:='render stage timeout';return;end if;
      dbms_session.sleep(.001);
    end loop;
  end;

  procedure decide(p_request in varchar2,p_decision in varchar2) is
    pragma autonomous_transaction;
    l_status varchar2(24):=case p_decision when 'ACCEPT' then 'ACCEPT_REQUESTED'
      when 'DISCARD' then 'DISCARD_REQUESTED' end;
  begin
    if l_status is null then raise_application_error(c_invalid,'invalid render decision');end if;
    update doom_render_stage set stage_status=l_status,decided_at=systimestamp
      where request_id=p_request and stage_status='STAGED';
    if sql%rowcount<>1 then raise_application_error(c_invalid,'render decision fence');end if;
    commit;
  exception when others then rollback;raise;
  end;

  procedure process_task(
    p_slot number,p_generation number,p_session varchar2,p_lineage varchar2,
    p_payload raw
  ) is
    l_request varchar2(32);l_state_sha varchar2(64);l_pack raw(32767);
    l_sim_generation number;l_expected_tic number;l_expected_seq number;
    l_result varchar2(4000);l_frame_sha varchar2(64);l_response blob;l_locator blob;
    l_response_bytes number;l_response_sha varchar2(64);l_pack_sha varchar2(64);
    l_render_us number;l_started timestamp with time zone;l_status varchar2(24);
    l_deadline timestamp with time zone;l_error varchar2(4000);l_pending number:=0;
    l_pack_offset pls_integer:=c_payload_prefix+1;
  begin
    if utl_raw.length(p_payload)<=c_payload_prefix then
      raise_application_error(c_invalid,'short render task envelope');end if;
    l_request:=utl_raw.cast_to_varchar2(utl_raw.substr(p_payload,1,32));
    l_state_sha:=utl_raw.cast_to_varchar2(utl_raw.substr(p_payload,33,64));
    l_pack:=utl_raw.substr(p_payload,l_pack_offset);
    select generation,expected_tic+1,expected_command_seq+1 into
      l_sim_generation,l_expected_tic,l_expected_seq
      from doom_worker_request where request_id=l_request and worker_slot=p_slot
        and session_token=p_session and save_lineage=p_lineage
        and request_status in('QUEUED','PROCESSING');
    l_pack_sha:=lower(rawtohex(dbms_crypto.hash(l_pack,dbms_crypto.hash_sh256)));
    dbms_lob.createtemporary(l_response,true,dbms_lob.call);l_started:=systimestamp;
    l_frame_sha:=doom_retained_render_pack(p_session,p_generation,l_request,
      l_pack,l_state_sha,l_response);l_render_us:=elapsed_us(l_started);
    if not regexp_like(l_frame_sha,'^[0-9a-f]{64}$') then
      raise_application_error(c_invalid,'packed renderer: '||substr(l_frame_sha,1,3000));end if;
    l_pending:=1;l_response_bytes:=dbms_lob.getlength(l_response);
    l_response_sha:=lower(rawtohex(dbms_crypto.hash(l_response,dbms_crypto.hash_sh256)));
    insert into doom_render_stage(request_id,render_slot,session_token,save_lineage,
      simulation_generation,render_generation,expected_tic,expected_command_seq,
      state_sha,render_pack_bytes,render_pack_sha,stage_status,frame_sha,
      response_bytes,response_sha,render_us,render_kernel_us,codec_us,response_blob)
    values(l_request,p_slot,p_session,p_lineage,l_sim_generation,p_generation,
      l_expected_tic,l_expected_seq,l_state_sha,utl_raw.length(l_pack),l_pack_sha,
      'STAGED',l_frame_sha,l_response_bytes,l_response_sha,l_render_us,
      round(doom_bsp_last_render_ns/1000),round(doom_bsp_last_codec_ns/1000),empty_blob())
    returning response_blob into l_locator;
    dbms_lob.copy(l_locator,l_response,l_response_bytes,1,1);commit;
    l_deadline:=systimestamp+numtodsinterval(config_number('RENDER_OVERLAP_DECISION_MS')/1000,'SECOND');
    loop
      select stage_status into l_status from doom_render_stage where request_id=l_request;
      exit when l_status in('ACCEPT_REQUESTED','DISCARD_REQUESTED');
      if systimestamp>=l_deadline then l_status:='DISCARD_REQUESTED';
        update doom_render_stage set stage_status=l_status,error_text='render decision timeout',
          decided_at=systimestamp where request_id=l_request and stage_status='STAGED';commit;exit;end if;
      dbms_session.sleep(.001);
    end loop;
    if l_status='ACCEPT_REQUESTED' then
      require_ok(doom_retained_render_accept(p_session,p_generation,l_request),'render accept');
      l_pending:=0;update doom_render_stage set stage_status='ACCEPTED',decided_at=systimestamp
        where request_id=l_request and stage_status='ACCEPT_REQUESTED';
    else
      require_ok(doom_retained_render_discard(p_session,p_generation,l_request),'render discard');
      l_pending:=0;update doom_render_stage set stage_status='DISCARDED',decided_at=systimestamp
        where request_id=l_request and stage_status='DISCARD_REQUESTED';
    end if;
    if sql%rowcount<>1 then raise_application_error(c_invalid,'render final decision fence');end if;
    commit;dbms_lob.freetemporary(l_response);
  exception when others then
    l_error:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    rollback;
    if l_pending=1 then begin l_result:=doom_retained_render_discard(
      p_session,p_generation,l_request);exception when others then null;end;end if;
    mark_failed(l_request,p_slot,p_generation,l_error);
    if dbms_lob.istemporary(l_response)=1 then dbms_lob.freetemporary(l_response);end if;
  end;

  procedure run_slot(p_worker_slot in number) is
    l_generation number;l_session varchar2(32);l_lineage varchar2(64);l_map_sha varchar2(64);
    l_tic number;l_seq number;l_snapshot blob;l_result varchar2(4000);l_stop number:=0;
    l_dequeue dbms_aq.dequeue_options_t;l_properties dbms_aq.message_properties_t;
    l_payload raw(32767);l_message_id raw(16);l_failure varchar2(4000);l_idle pls_integer:=0;
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    select generation,target_session,target_lineage,state_map_sha into
      l_generation,l_session,l_lineage,l_map_sha from doom_render_worker_control
      where worker_slot=p_worker_slot for update;
    if l_session is null then raise_application_error(c_invalid,'render target missing');end if;
    l_generation:=l_generation+1;
    update doom_render_worker_control set generation=l_generation,ready=0,stop_requested=0,
      worker_sid=sys_context('USERENV','SID'),heartbeat=systimestamp,last_error=null
      where worker_slot=p_worker_slot;commit;
    select current_tic,last_command_seq into l_tic,l_seq from game_sessions where session_token=l_session;
    dbms_lob.createtemporary(l_snapshot,true,dbms_lob.call);doom_renderer_snapshot_fill(l_session,l_snapshot);
    l_result:=doom_retained_render_force_load(l_session,l_generation,l_map_sha,l_tic,l_seq,l_snapshot);
    dbms_lob.freetemporary(l_snapshot);require_ok(l_result,'render worker recovery');
    update doom_render_worker_control set ready=1,heartbeat=systimestamp
      where worker_slot=p_worker_slot and generation=l_generation;commit;
    l_dequeue.wait:=0;l_dequeue.visibility:=dbms_aq.immediate;
    l_dequeue.navigation:=dbms_aq.first_message;
    l_dequeue.correlation:='SLOT_'||to_char(p_worker_slot,'FM00');
    loop
      begin
        dbms_aq.dequeue('DOOM_RENDER_TASK_Q',l_dequeue,l_properties,l_payload,l_message_id);
        l_idle:=0;process_task(p_worker_slot,l_generation,l_session,l_lineage,l_payload);
      exception when no_messages then rollback;l_idle:=l_idle+1;
        if mod(l_idle,20)=0 then update doom_render_worker_control set heartbeat=systimestamp
          where worker_slot=p_worker_slot and generation=l_generation;commit;end if;
        dbms_session.sleep(case when l_idle<40 then .005 else .025 end);
      end;
      if mod(l_idle,20)=0 then select stop_requested into l_stop from doom_render_worker_control
        where worker_slot=p_worker_slot;end if;exit when l_stop=1;
    end loop;
    update doom_render_worker_control set ready=0,stop_requested=0,worker_sid=null,
      target_session=null,target_lineage=null,state_map_sha=null,heartbeat=systimestamp
      where worker_slot=p_worker_slot;commit;
  exception when others then
    l_failure:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    rollback;update doom_render_worker_control set ready=0,worker_sid=null,
      target_session=null,target_lineage=null,state_map_sha=null,last_error=l_failure,
      heartbeat=systimestamp where worker_slot=p_worker_slot;commit;
  end;

  procedure start_worker(
    p_worker_slot in number,p_session in varchar2,p_lineage in varchar2,
    p_state_map_sha in varchar2
  ) is l_running number;
  begin
    if config_number('RENDER_OVERLAP_ENABLED')<>1 then return;end if;
    update doom_render_worker_control set target_session=p_session,target_lineage=p_lineage,
      state_map_sha=p_state_map_sha,ready=0,stop_requested=0,last_error=null
      where worker_slot=p_worker_slot and target_session is null;
    if sql%rowcount<>1 then raise_application_error(c_invalid,'render worker slot unavailable');end if;
    commit;select count(*) into l_running from user_scheduler_running_jobs
      where job_name='DOOM_RENDER_WORKER_'||to_char(p_worker_slot,'FM00');
    if l_running<>0 then raise_application_error(c_invalid,'render worker job already running');end if;
    dbms_scheduler.run_job('DOOM_RENDER_WORKER_'||to_char(p_worker_slot,'FM00'),false);
  exception when others then
    update doom_render_worker_control set target_session=null,target_lineage=null,state_map_sha=null
      where worker_slot=p_worker_slot and ready=0 and target_session=p_session;commit;raise;
  end;

  procedure request_stop(p_session in varchar2) is pragma autonomous_transaction;
  begin update doom_render_worker_control set stop_requested=1
    where target_session=p_session;commit;end;
end doom_render_worker;
/

begin
  for l_slot in 1..4 loop
    begin dbms_scheduler.drop_job('DOOM_RENDER_WORKER_'||to_char(l_slot,'FM00'),true);
    exception when others then if sqlcode<>-27475 then raise;end if;end;
    dbms_scheduler.create_job(
      job_name=>'DOOM_RENDER_WORKER_'||to_char(l_slot,'FM00'),job_type=>'PLSQL_BLOCK',
      job_action=>'begin doom_render_worker.run_slot('||to_char(l_slot)||'); end;',
      enabled=>false,auto_drop=>false);
  end loop;
end;
/
