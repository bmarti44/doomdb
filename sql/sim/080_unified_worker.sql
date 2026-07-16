-- Production retained-worker coordinator.  The feature stays default-off
-- behind UNIFIED_WORKER_ENABLED; DOOM_API.STEP is intentionally unchanged.

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
  c_zero_sha constant varchar2(64):=rpad('0',64,'0');

  function config_number(p_key varchar2) return number is
    l_value number;
  begin
    select number_value into l_value from doom_config where config_key=p_key;
    return l_value;
  exception when no_data_found then
    raise_application_error(c_invalid,'missing worker configuration');
  end;

  function elapsed_us(p_started timestamp with time zone) return number is
    l_span interval day to second:=systimestamp-p_started;
  begin
    return round((extract(day from l_span)*86400+extract(hour from l_span)*3600+
      extract(minute from l_span)*60+extract(second from l_span))*1000000);
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

  function state_map_sha return varchar2 is
    l_text clob;l_document blob;l_sha varchar2(64);
    l_dest integer:=1;l_src integer:=1;l_context integer:=0;l_warning integer;
  begin
    select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,
      sprite_prefix,sprite_frame,rotations null on null returning varchar2)
      order by state_id returning clob) into l_text from doom_state_def;
    if l_text is null then
      raise_application_error(c_invalid,'empty unified state map');
    end if;
    dbms_lob.createtemporary(l_document,true,dbms_lob.call);
    dbms_lob.converttoblob(l_document,l_text,dbms_lob.lobmaxsize,l_dest,l_src,
      nls_charset_id('AL32UTF8'),l_context,l_warning);
    if l_warning<>0 then
      raise_application_error(c_invalid,'unified state-map encoding');
    end if;
    l_sha:=lower(rawtohex(dbms_crypto.hash(l_document,dbms_crypto.hash_sh256)));
    return l_sha;
  end;

  procedure require_ok(p_value varchar2,p_label varchar2) is
  begin
    if p_value is null or p_value not like 'OK%' then
      raise_application_error(c_invalid,p_label||': '||substr(p_value,1,3000));
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
    l_options.visibility:=dbms_aq.on_commit;
    l_properties.correlation:=p_request;
    l_payload:=utl_raw.cast_to_raw(p_request);
    dbms_aq.enqueue('DOOM_UNIFIED_RESPONSE_Q',l_options,l_properties,
      l_payload,l_message_id);
  end;

  procedure load_and_warm(
    p_session varchar2,p_lineage varchar2,p_generation number,p_map_sha varchar2
  ) is
    l_snapshot blob;l_payload blob;l_delta raw(32767);
    l_result varchar2(4000);l_frame_sha varchar2(4000);
    l_request varchar2(32);l_tic number;l_seq number;l_rng number;
    l_next_mobj number;
  begin
    dbms_lob.createtemporary(l_snapshot,true,dbms_lob.call);
    doom_renderer_snapshot_fill(p_session,l_snapshot);
    l_result:=doom_unified_recover_sql_renderer(
      p_session,p_lineage,p_generation,p_map_sha,l_snapshot);
    require_ok(l_result,'combined retained-owner recovery');

    select current_tic,last_command_seq,rng_cursor into l_tic,l_seq,l_rng
      from game_sessions where session_token=p_session;
    select coalesce(max(mobj_id),0)+1 into l_next_mobj from mobjs
      where session_token=p_session;
    l_request:=lower(rawtohex(sys_guid()));
    l_delta:=doom_unified_actor_prepare(p_session,p_lineage,p_generation,l_request,
      'TIC',l_tic,l_seq,l_rng,l_next_mobj,0);
    if l_delta is null or utl_raw.length(l_delta)<12 or
       rawtohex(utl_raw.substr(l_delta,1,6))<>'44554F500100' then
      raise_application_error(c_invalid,'unified warm prepare');
    end if;
    dbms_lob.createtemporary(l_payload,true,dbms_lob.call);
    l_frame_sha:=doom_unified_render_pending(p_session,p_lineage,p_generation,
      l_request,c_zero_sha,l_payload);
    if not regexp_like(l_frame_sha,'^[0-9a-f]{64}$') then
      raise_application_error(c_invalid,'unified warm render: '||
        substr(l_frame_sha,1,3000));
    end if;
    l_result:=doom_unified_actor_discard(
      p_session,p_lineage,p_generation,l_request);
    require_ok(l_result,'unified warm discard');
  exception when others then
    begin
      if l_request is not null then
        l_result:=doom_unified_actor_discard(
          p_session,p_lineage,p_generation,l_request);
      end if;
    exception when others then null;end;
    raise;
  end;

  procedure recover_after_commit(
    p_slot number,p_request varchar2,p_session varchar2,p_lineage varchar2,
    p_map_sha varchar2,io_generation in out number
  ) is
    l_next_generation number;
  begin
    select generation into l_next_generation from doom_worker_control
      where worker_slot=p_slot and target_session=p_session
        and target_lineage=p_lineage and state_map_sha=p_map_sha for update;
    if l_next_generation<>io_generation then
      raise_application_error(c_invalid,'post-commit recovery generation fence');
    end if;
    l_next_generation:=l_next_generation+1;
    update doom_worker_control set generation=l_next_generation,ready=0,
      heartbeat=systimestamp,last_error=null
      where worker_slot=p_slot and generation=io_generation;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'post-commit recovery control race');
    end if;
    commit;

    load_and_warm(p_session,p_lineage,l_next_generation,p_map_sha);
    update doom_worker_control set ready=1,heartbeat=systimestamp,last_error=null
      where worker_slot=p_slot and target_session=p_session
        and target_lineage=p_lineage and state_map_sha=p_map_sha
        and generation=l_next_generation and ready=0;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'post-commit recovery ready race');
    end if;
    update doom_worker_request set response_generation=l_next_generation
      where request_id=p_request and request_status='COMMITTED';
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'post-commit recovery request race');
    end if;
    commit;
    io_generation:=l_next_generation;
  end;

  procedure recover_after_rollback(
    p_slot number,p_request varchar2,p_session varchar2,p_lineage varchar2,
    p_map_sha varchar2,io_generation in out number
  ) is
    l_next_generation number;
  begin
    select generation into l_next_generation from doom_worker_control
      where worker_slot=p_slot and target_session=p_session
        and target_lineage=p_lineage and state_map_sha=p_map_sha for update;
    if l_next_generation<>io_generation then
      raise_application_error(c_invalid,'rollback recovery generation fence');
    end if;
    l_next_generation:=l_next_generation+1;
    update doom_worker_control set generation=l_next_generation,ready=0,
      heartbeat=systimestamp,last_error=null
      where worker_slot=p_slot and generation=io_generation;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'rollback recovery control race');
    end if;
    commit;
    load_and_warm(p_session,p_lineage,l_next_generation,p_map_sha);
    update doom_worker_control set ready=1,heartbeat=systimestamp,last_error=null
      where worker_slot=p_slot and target_session=p_session
        and target_lineage=p_lineage and state_map_sha=p_map_sha
        and generation=l_next_generation and ready=0;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'rollback recovery ready race');
    end if;
    update doom_worker_request set response_generation=l_next_generation
      where request_id=p_request and request_status='FAILED';
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'rollback recovery request race');
    end if;
    commit;
    io_generation:=l_next_generation;
  end;

  procedure process_request(
    p_slot number,p_request varchar2,p_worker_map_sha varchar2,
    p_worker_generation in out number
  ) is
    l_request_slot number;l_session varchar2(32);l_lineage varchar2(64);
    l_generation number;l_expected_tic number;l_expected_seq number;
    l_command_version number;l_command_count number;l_command_bytes number;
    l_command_sha varchar2(64);l_command raw(2000);l_status varchar2(16);
    l_target_session varchar2(32);l_target_lineage varchar2(64);
    l_control_generation number;l_ready number;l_map_sha varchar2(64);
    l_db_lineage varchar2(64);l_db_tic number;l_db_seq number;l_rng number;
    l_next_mobj number;l_result_tic number;l_result_seq number;
    l_ledger_sha varchar2(64);l_state_locator blob;
    l_delta_locator blob;l_response_locator blob;l_delta raw(32767);
    l_state_payload blob;l_render_payload blob;l_history_payload blob;
    l_committed_tic number;l_committed_seq number;l_delta_version number;
    l_delta_count number;l_delta_sha varchar2(64);l_state_sha varchar2(64);
    l_frame_sha varchar2(4000);l_response_sha varchar2(64);
    l_response_bytes number;l_result varchar2(4000);l_error varchar2(4000);
    l_prepared number:=0;l_committed number:=0;l_failpoint number;
    l_history_interval number;
    l_stage timestamp with time zone;l_prepare_us number;l_apply_us number;
    l_state_us number;l_render_us number;l_finalize_us number;
    l_render_call_us number;l_render_update_us number;l_render_kernel_us number;
    l_codec_us number;l_blob_us number;l_response_copy_us number;
    l_response_hash_us number;l_state_encode_us number;l_state_blob_us number;
    l_state_compare_us number;l_state_object_encode_us number;
    l_state_changed number;l_state_reused number;l_state_removed number;
    l_event_sha varchar2(64);l_snapshot_sha varchar2(4000);
    l_history_stage timestamp with time zone;l_finalize_stage timestamp with time zone;
    l_history_us number;
    l_history_encode_us number;l_history_blob_us number;l_history_persist_us number;
    l_commit_us number;
    procedure free_temp(p_lob in out nocopy blob) is
    begin
      if p_lob is not null and dbms_lob.istemporary(p_lob)=1 then
        dbms_lob.freetemporary(p_lob);
      end if;
      p_lob:=null;
    exception when others then p_lob:=null;
    end;
  begin
    begin
      select worker_slot,session_token,save_lineage,generation,expected_tic,
        expected_command_seq,command_version,command_count,command_bytes,
        command_sha,command_pack,request_status
        into l_request_slot,l_session,l_lineage,l_generation,l_expected_tic,
          l_expected_seq,l_command_version,l_command_count,l_command_bytes,
          l_command_sha,l_command,l_status
        from doom_worker_request where request_id=p_request for update;

      if l_request_slot<>p_slot then
        raise_application_error(c_invalid,'worker slot fence');
      end if;
      if l_status in('COMMITTED','ROLLED_BACK','FAILED') then
        respond(p_request);
        update doom_worker_control set heartbeat=systimestamp
          where worker_slot=p_slot;
        commit;
        audit_event(p_request,p_slot,l_generation,'TERMINAL_REPLAY',l_status);
        return;
      end if;
      if l_command_version<>2 or l_command_count<>1 or l_command_bytes<>24 or
         utl_raw.length(l_command)<>24 or
         lower(rawtohex(dbms_crypto.hash(l_command,dbms_crypto.hash_sh256)))<>
           l_command_sha then
        raise_application_error(c_invalid,'worker request envelope fence');
      end if;
      update doom_worker_request set request_status='PROCESSING',error_text=null
        where request_id=p_request and request_status in('QUEUED','PROCESSING');
      if sql%rowcount<>1 then
        raise_application_error(c_invalid,'worker request status race');
      end if;

      select target_session,target_lineage,state_map_sha,generation,ready
        into l_target_session,l_target_lineage,l_map_sha,l_control_generation,l_ready
        from doom_worker_control where worker_slot=p_slot for update;
      if l_ready<>1 or l_generation<>l_control_generation or
         p_worker_generation<>l_control_generation or
         l_session<>l_target_session or l_lineage<>l_target_lineage or
         l_map_sha is null or l_map_sha<>p_worker_map_sha then
        raise_application_error(c_invalid,'worker control fence');
      end if;
      select save_lineage,current_tic,last_command_seq,rng_cursor
        into l_db_lineage,l_db_tic,l_db_seq,l_rng from game_sessions
        where session_token=l_session for update;
      if l_db_lineage<>l_lineage or l_db_tic<>l_expected_tic or
         l_db_seq<>l_expected_seq then
        raise_application_error(c_invalid,'database frontier fence');
      end if;
      select coalesce(max(mobj_id),0)+1 into l_next_mobj from mobjs
        where session_token=l_session;

      l_stage:=systimestamp;
      doom_command_ledger.begin_dmsc_v2(l_session,l_lineage,l_expected_tic,
        l_expected_seq,l_command,l_result_tic,l_result_seq,l_ledger_sha,
        l_state_locator);
      insert into doom_worker_result(request_id,committed_tic,
        committed_command_seq,delta_version,delta_count,delta_bytes,delta_sha,
        state_sha,frame_sha,response_bytes,response_sha,delta_blob,response_blob)
      values(p_request,l_result_tic,l_result_seq,1,1,0,c_zero_sha,c_zero_sha,
        c_zero_sha,0,c_zero_sha,empty_blob(),empty_blob())
      returning delta_blob,response_blob into l_delta_locator,l_response_locator;

      l_delta:=doom_unified_command_tic_prepare(l_session,l_lineage,l_generation,
        p_request,l_expected_tic,l_expected_seq,l_rng,l_next_mobj,0,l_command);
      l_prepared:=1;
      l_prepare_us:=elapsed_us(l_stage);
      l_failpoint:=config_number('UNIFIED_WORKER_FAILPOINT');
      l_history_interval:=config_number('HISTORY_SNAPSHOT_INTERVAL');
      if l_history_interval<>trunc(l_history_interval) or l_history_interval<1 then
        raise_application_error(c_invalid,'invalid history checkpoint interval');
      end if;
      if l_failpoint in(1,4) then
        raise_application_error(c_invalid,'injected pre-apply worker failure');
      end if;
      l_stage:=systimestamp;
      doom_unified_delta_apply.apply_command_tic(l_session,l_lineage,
        l_expected_tic,l_expected_seq,l_command,l_delta,l_committed_tic,
        l_committed_seq,l_delta_version,l_delta_count,l_delta_sha);
      if l_committed_tic<>l_result_tic or l_committed_seq<>l_result_seq then
        raise_application_error(c_invalid,'ledger/apply frontier mismatch');
      end if;
      l_apply_us:=elapsed_us(l_stage);
      if l_failpoint=3 then
        raise_application_error(c_invalid,'injected post-apply worker failure');
      end if;

      l_stage:=systimestamp;
      dbms_application_info.set_action('DOOM_STATE_COPY');
      dbms_lob.trim(l_delta_locator,0);
      dbms_lob.writeappend(l_delta_locator,utl_raw.length(l_delta),l_delta);
      -- The retained owner already has every canonical field in primitive
      -- arrays. Reuse byte-exact JSON fragments for unchanged actors, write
      -- into a temporary locator, then perform one bounded SecureFile copy.
      -- This avoids both relational row walking and persistent JDBC writes.
      dbms_lob.createtemporary(l_state_payload,true,dbms_lob.call);
      l_state_sha:=doom_unified_state_fill(l_session,l_lineage,l_generation,
        p_request,l_state_payload);
      if not regexp_like(l_state_sha,'^[0-9a-f]{64}$') then
        raise_application_error(c_invalid,'retained state codec: '||
          substr(l_state_sha,1,3000));
      end if;
      dbms_lob.trim(l_state_locator,0);
      dbms_lob.copy(l_state_locator,l_state_payload,
        dbms_lob.getlength(l_state_payload),1,1);
      free_temp(l_state_payload);
      l_state_us:=elapsed_us(l_stage);
      l_state_encode_us:=round(doom_unified_state_encode_ns/1000);
      l_state_blob_us:=round(doom_unified_state_blob_ns/1000);
      l_state_compare_us:=round(doom_unified_state_compare_ns/1000);
      l_state_object_encode_us:=round(doom_unified_state_object_encode_ns/1000);
      l_state_changed:=doom_unified_state_changed;
      l_state_reused:=doom_unified_state_reused;
      l_state_removed:=doom_unified_state_removed;
      l_stage:=systimestamp;
      dbms_application_info.set_action('DOOM_RENDER');
      dbms_lob.createtemporary(l_render_payload,true,dbms_lob.call);
      l_frame_sha:=doom_unified_render_pending(l_session,l_lineage,l_generation,
        p_request,l_state_sha,l_render_payload);
      l_render_call_us:=elapsed_us(l_stage);
      if not regexp_like(l_frame_sha,'^[0-9a-f]{64}$') then
        raise_application_error(c_invalid,'direct pending renderer: '||
          substr(l_frame_sha,1,3000));
      end if;
      -- Keep server-side JDBC off the persistent SecureFile locator: its
      -- measured write tail dominates otherwise. Java fills a temporary BLOB;
      -- PL/SQL performs one bounded durable copy in the owning transaction.
      l_stage:=systimestamp;
      dbms_application_info.set_action('DOOM_RESPONSE_COPY');
      dbms_lob.trim(l_response_locator,0);
      dbms_lob.copy(l_response_locator,l_render_payload,
        dbms_lob.getlength(l_render_payload),1,1);
      free_temp(l_render_payload);
      l_response_copy_us:=elapsed_us(l_stage);
      l_response_bytes:=dbms_lob.getlength(l_response_locator);
      if l_response_bytes=0 then
        raise_application_error(c_invalid,'empty worker response');
      end if;
      l_stage:=systimestamp;
      l_response_sha:=lower(rawtohex(dbms_crypto.hash(
        l_response_locator,dbms_crypto.hash_sh256)));
      l_response_hash_us:=elapsed_us(l_stage);
      l_render_us:=l_render_call_us+l_response_copy_us+l_response_hash_us;
      l_render_update_us:=round(doom_retained_render_last_update_ns/1000);
      l_render_kernel_us:=round(doom_bsp_last_render_ns/1000);
      l_codec_us:=round(doom_bsp_last_codec_ns/1000);
      l_blob_us:=round(doom_bsp_last_blob_ns/1000);

      l_finalize_stage:=systimestamp;
      doom_command_ledger.finalize_command(l_session,l_lineage,l_result_seq,
        l_state_sha,l_frame_sha);
      if mod(l_result_tic,l_history_interval)=0 then
        dbms_application_info.set_action('DOOM_HISTORY');
        l_history_stage:=systimestamp;
        select event_sha into l_event_sha from history_heads
          where session_token=l_session and lineage=l_lineage;
        dbms_lob.createtemporary(l_history_payload,true,dbms_lob.call);
        l_snapshot_sha:=doom_unified_history_fill(l_session,l_lineage,l_generation,
          p_request,l_result_tic,l_result_seq,l_ledger_sha,l_event_sha,l_state_sha,
          l_frame_sha,l_history_payload);
        if not regexp_like(l_snapshot_sha,'^[0-9a-f]{64}$') then
          raise_application_error(c_invalid,'retained history codec: '||
            substr(l_snapshot_sha,1,3000));
        end if;
        l_history_encode_us:=round(doom_unified_history_encode_ns/1000);
        l_history_blob_us:=round(doom_unified_history_blob_ns/1000);
        l_stage:=systimestamp;
        doom_capture_retained_tic(l_session,l_lineage,l_result_tic,l_result_seq,
          l_ledger_sha,l_event_sha,l_state_sha,l_frame_sha,l_snapshot_sha,
          l_history_payload);
        free_temp(l_history_payload);
        l_history_persist_us:=elapsed_us(l_stage);
        l_history_us:=elapsed_us(l_history_stage);
      end if;
      l_finalize_us:=elapsed_us(l_finalize_stage);
      update doom_worker_result set committed_tic=l_committed_tic,
        committed_command_seq=l_committed_seq,delta_version=l_delta_version,
        delta_count=l_delta_count,delta_bytes=utl_raw.length(l_delta),
        delta_sha=l_delta_sha,state_sha=l_state_sha,frame_sha=l_frame_sha,
        response_bytes=l_response_bytes,response_sha=l_response_sha,
        prepare_us=l_prepare_us,apply_us=l_apply_us,state_us=l_state_us,
        state_encode_us=l_state_encode_us,state_blob_us=l_state_blob_us,
        state_compare_us=l_state_compare_us,
        state_object_encode_us=l_state_object_encode_us,
        state_changed=l_state_changed,state_reused=l_state_reused,
        state_removed=l_state_removed,render_us=l_render_us,
        render_call_us=l_render_call_us,render_update_us=l_render_update_us,
        render_kernel_us=l_render_kernel_us,codec_us=l_codec_us,
        blob_us=l_blob_us,response_copy_us=l_response_copy_us,
        response_hash_us=l_response_hash_us,history_us=l_history_us,
        history_encode_us=l_history_encode_us,history_blob_us=l_history_blob_us,
        history_persist_us=l_history_persist_us,finalize_us=l_finalize_us
        where request_id=p_request;
      if sql%rowcount<>1 then
        raise_application_error(c_invalid,'worker result finalize race');
      end if;
      update doom_worker_request set request_status='COMMITTED',
        response_generation=l_generation,error_text=null,completed_at=systimestamp
        where request_id=p_request and request_status='PROCESSING';
      if sql%rowcount<>1 then
        raise_application_error(c_invalid,'worker request finalize race');
      end if;
      update doom_worker_control set heartbeat=systimestamp
        where worker_slot=p_slot and generation=l_generation and ready=1;
      if sql%rowcount<>1 then
        raise_application_error(c_invalid,'worker heartbeat fence');
      end if;
      dbms_application_info.set_action('DOOM_DURABLE_COMMIT');
      l_stage:=systimestamp;
      commit write batch wait;
      l_commit_us:=elapsed_us(l_stage);
      l_committed:=1;
    exception when others then
      free_temp(l_state_payload);free_temp(l_render_payload);free_temp(l_history_payload);
      l_error:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
      if l_committed=0 then
        rollback;
        if l_prepared=1 and l_failpoint=4 then
          l_result:='ERR|injected discard failure';
        elsif l_prepared=1 then
          begin
            l_result:=doom_unified_actor_discard(
              l_session,l_lineage,l_generation,p_request);
          exception when others then l_result:='ERR|'||sqlerrm;end;
        end if;
        terminal_status(p_request,p_slot,l_generation,'FAILED',
          l_error||case when l_result is not null and l_result<>'OK'
            then ' discard='||substr(l_result,1,1000) end);
        audit_event(p_request,p_slot,l_generation,'PRECOMMIT_FAILED',l_error);
        if l_prepared=1 and (l_result is null or l_result<>'OK') then
          audit_event(p_request,p_slot,l_generation,'DISCARD_FAILED',l_result);
          recover_after_rollback(p_slot,p_request,l_session,l_lineage,l_map_sha,
            p_worker_generation);
          audit_event(p_request,p_slot,p_worker_generation,
            'ROLLBACK_RECOVERED',l_result);
        end if;
        return;
      end if;
      raise;
    end;

    begin
      if l_failpoint=2 then
        l_result:='ERR|injected post-commit accept failure';
      else
        l_result:=doom_unified_actor_accept(
          l_session,l_lineage,l_generation,p_request);
      end if;
      if l_result is null or l_result<>'OK' then
        raise_application_error(c_invalid,'post-commit accept: '||
          substr(l_result,1,3000));
      end if;
      -- DOOM_WORKER_RESULT and DOOM_WORKER_REQUEST already form the durable
      -- success ledger. Avoid a second autonomous commit/audit row on every
      -- tic; audit remains reserved for lifecycle, replay, and failure events.
    exception when others then
      l_error:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
      audit_event(p_request,p_slot,l_generation,'POSTCOMMIT_ACCEPT_FAILED',l_error);
      recover_after_commit(p_slot,p_request,l_session,l_lineage,l_map_sha,
        p_worker_generation);
      audit_event(p_request,p_slot,p_worker_generation,'POSTCOMMIT_RECOVERED',
        l_error);
    end;
    update doom_worker_result set commit_us=l_commit_us
      where request_id=p_request;
    -- The SQL/AQ dequeue transaction is already durable.  Correlate only after
    -- Java accept or combined reconstruction establishes the live generation.
    respond(p_request);
    commit;
    dbms_application_info.set_action(null);
  end;

  procedure run_slot(p_worker_slot in number) is
    l_dequeue dbms_aq.dequeue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_payload raw(32767);l_message_id raw(16);l_request varchar2(32);
    l_generation number;l_stop number:=0;l_target varchar2(32);
    l_lineage varchar2(64);l_control_map varchar2(64);l_map_sha varchar2(64);
    l_failure varchar2(4000);l_limit pls_integer;
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    require_enabled;l_limit:=pool_size;
    if p_worker_slot<1 or p_worker_slot>l_limit then
      raise_application_error(c_invalid,'worker slot is outside configured pool');
    end if;
    select generation,target_session,target_lineage,state_map_sha
      into l_generation,l_target,l_lineage,l_control_map
      from doom_worker_control where worker_slot=p_worker_slot for update;
    if l_target is null or l_lineage is null then
      raise_application_error(c_invalid,'worker target is not configured');
    end if;
    l_map_sha:=state_map_sha;
    if l_control_map<>l_map_sha then
      raise_application_error(c_invalid,'worker state-map fence');
    end if;
    l_generation:=l_generation+1;
    update doom_worker_control set generation=l_generation,ready=0,
      stop_requested=0,worker_sid=sys_context('USERENV','SID'),
      heartbeat=systimestamp,last_error=null where worker_slot=p_worker_slot;
    commit;

    load_and_warm(l_target,l_lineage,l_generation,l_map_sha);
    update doom_worker_control set ready=1,heartbeat=systimestamp
      where worker_slot=p_worker_slot and target_session=l_target
        and target_lineage=l_lineage and state_map_sha=l_map_sha
        and generation=l_generation and ready=0;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'worker ready fence');
    end if;
    commit;
    audit_event(null,p_worker_slot,l_generation,'WORKER_READY',
      l_target||'|'||l_map_sha);

    l_dequeue.wait:=1;l_dequeue.visibility:=dbms_aq.on_commit;
    l_dequeue.navigation:=dbms_aq.first_message;
    l_dequeue.correlation:='SLOT_'||to_char(p_worker_slot,'FM00');
    loop
      begin
        dbms_aq.dequeue('DOOM_UNIFIED_REQUEST_Q',l_dequeue,l_properties,
          l_payload,l_message_id);
        l_request:=utl_raw.cast_to_varchar2(l_payload);
        process_request(p_worker_slot,l_request,l_map_sha,l_generation);
        l_dequeue.navigation:=dbms_aq.first_message;
      exception when no_messages then
        rollback;
        update doom_worker_control set heartbeat=systimestamp
          where worker_slot=p_worker_slot and generation=l_generation;
        commit;
        l_dequeue.navigation:=dbms_aq.first_message;
      end;
      select stop_requested into l_stop from doom_worker_control
        where worker_slot=p_worker_slot;
      exit when l_stop=1;
    end loop;
    update doom_worker_control set ready=0,stop_requested=0,worker_sid=null,
      target_session=null,target_lineage=null,state_map_sha=null,
      heartbeat=systimestamp where worker_slot=p_worker_slot;
    commit;
    audit_event(null,p_worker_slot,l_generation,'WORKER_STOP',l_target);
  exception when others then
    l_failure:=substr(sqlerrm||' '||dbms_utility.format_error_backtrace,1,4000);
    begin
      rollback;
      update doom_worker_control set ready=0,stop_requested=0,worker_sid=null,
        target_session=null,target_lineage=null,state_map_sha=null,
        last_error=l_failure,heartbeat=systimestamp
        where worker_slot=p_worker_slot;
      commit;
      audit_event(null,p_worker_slot,l_generation,'WORKER_FATAL',l_failure);
    exception when others then null;end;
  end;

  procedure start_worker(p_session in varchar2) is
    l_lineage varchar2(64);l_map_sha varchar2(64);
    l_slot number;l_running number;l_limit pls_integer;
  begin
    require_enabled;l_limit:=pool_size;
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
      raise_application_error(c_invalid,'invalid worker session');
    end if;
    select save_lineage into l_lineage from game_sessions
      where session_token=p_session;
    l_map_sha:=state_map_sha;
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
      target_lineage=l_lineage,state_map_sha=l_map_sha,ready=0,
      stop_requested=0,last_error=null where worker_slot=l_slot;
    commit;
    begin
      dbms_scheduler.run_job(
        'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),false);
    exception when others then
      update doom_worker_control set target_session=null,target_lineage=null,
        state_map_sha=null where worker_slot=l_slot and ready=0
        and target_session=p_session;
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
    p_state_map_sha out varchar2,p_error out varchar2);

  procedure worker_status(
    p_session in varchar2,p_generation out number,p_ready out number,
    p_state_map_sha out varchar2,p_heartbeat out timestamp with time zone,
    p_error out varchar2);

  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_request in varchar2,p_expected_tic in number,p_expected_seq in number,
    p_command_version in number,p_command_count in number,p_command in raw,
    p_wait_seconds in number,
    p_status out varchar2,p_response_generation out number,
    p_committed_tic out number,p_committed_seq out number,
    p_delta_version out number,p_delta_count out number,
    p_delta_sha out varchar2,p_state_sha out varchar2,p_frame_sha out varchar2,
    p_response_bytes out number,p_response_sha out varchar2,
    p_delta out blob,p_payload out blob,p_error out varchar2);
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
       p_generation is null or p_generation<>trunc(p_generation) or p_generation<1 or
       p_expected_tic is null or p_expected_tic<>trunc(p_expected_tic) or
       p_expected_tic not between 0 and 999999999998 or
       p_expected_seq is null or p_expected_seq<>trunc(p_expected_seq) or
       p_expected_seq not between 0 and 999999999998 or
       p_command_version<>2 or p_command_count<>1 or p_command is null or
       utl_raw.length(p_command)<>24 or
       utl_raw.length(p_command)>least(2000,
         config_number('UNIFIED_WORKER_MAX_PACK_BYTES')) then
      raise_application_error(c_invalid,'invalid unified worker request');
    end if;
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
      l_options.visibility:=dbms_aq.on_commit;
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
    p_state_map_sha out varchar2,p_heartbeat out timestamp with time zone,
    p_error out varchar2
  ) is
  begin
    require_enabled;
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
      raise_application_error(c_invalid,'invalid worker session');
    end if;
    select generation,ready,state_map_sha,heartbeat,last_error
      into p_generation,p_ready,p_state_map_sha,p_heartbeat,p_error
      from doom_worker_control where target_session=p_session;
  exception when no_data_found then
    raise_application_error(c_invalid,'worker session is not active');
  end;

  procedure claim(
    p_session in varchar2,p_generation out number,p_ready out number,
    p_state_map_sha out varchar2,p_error out varchar2
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
        worker_status(p_session,p_generation,p_ready,p_state_map_sha,
          l_heartbeat,p_error);
        exit when p_ready=1 or p_error is not null;
      exception when others then
        if sqlcode<>c_invalid then raise;end if;
      end;
      if systimestamp>=l_deadline then
        p_generation:=null;p_ready:=0;p_state_map_sha:=null;
        p_error:='worker claim timeout';return;
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
    p_state_sha out varchar2,p_frame_sha out varchar2,
    p_response_bytes out number,p_response_sha out varchar2,
    p_delta out blob,p_payload out blob,p_error out varchar2
  ) is
    l_status varchar2(16);l_max_wait number;
    l_dequeue dbms_aq.dequeue_options_t;
    l_properties dbms_aq.message_properties_t;
    l_response raw(32767);l_message_id raw(16);
    no_messages exception;pragma exception_init(no_messages,-25228);
  begin
    p_committed_tic:=null;p_committed_seq:=null;p_delta_version:=null;
    p_delta_count:=null;p_delta_sha:=null;p_state_sha:=null;p_frame_sha:=null;
    p_response_bytes:=null;p_response_sha:=null;p_delta:=null;p_payload:=null;
    p_error:=null;
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
        delta_sha,state_sha,frame_sha,response_bytes,response_sha,
        delta_blob,response_blob
        into p_committed_tic,p_committed_seq,p_delta_version,p_delta_count,
          p_delta_sha,p_state_sha,p_frame_sha,p_response_bytes,p_response_sha,
          p_delta,p_payload
        from doom_worker_result where request_id=p_request;
    end if;
  end;
end doom_worker_api;
/

begin
  for l_slot in 1..4 loop
    begin
      dbms_scheduler.drop_job(
        'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),true);
    exception when others then
      if sqlcode<>-27475 then raise;end if;
    end;
    dbms_scheduler.create_job(
      job_name=>'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),
      job_type=>'PLSQL_BLOCK',
      job_action=>'begin doom_unified_worker.run_slot('||to_char(l_slot)||'); end;',
      enabled=>false,auto_drop=>false);
  end loop;
end;
/
