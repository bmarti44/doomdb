whenever sqlerror exit failure rollback
set define off

create or replace package doom_match_worker authid definer as
  procedure start_ready(
    p_match in varchar2,p_wait_ms in number,p_match_state out varchar2);
  procedure recover_match(
    p_match in varchar2,p_wait_ms in number,p_match_state out varchar2);
  procedure submit_command(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_tic in number,p_command_seq in number,
    p_ticcmd_raw in raw,p_accepted out number);
  procedure submit_command_batch(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_first_tic in number,p_first_command_seq in number,
    p_ticcmd_raw in raw,p_accepted out number,
    p_first_input_seq in number default null,p_input_raw in raw default null);
  procedure poll_frame(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_tic in number,p_ready out number,
    p_payload out blob);
  procedure stop_match(p_match in varchar2,p_generation in number);
  procedure run_match(p_match in varchar2);
  procedure run_standby(p_match in varchar2);
  procedure run_warm_slot(p_slot in number,p_incarnation in varchar2);
  procedure start_warm_pool;
end doom_match_worker;
/

create or replace package body doom_match_worker as
  -- Transaction invariant: when one transaction touches both relations,
  -- acquire DOOM_MATCH before DOOM_MATCH_MEMBER.
  c_error constant pls_integer:=-20731;
  c_command_deadline_ms constant pls_integer:=2000;
  c_initial_command_deadline_ms constant pls_integer:=500;
  c_frame_retention_tics constant pls_integer:=128;
  -- Absolute 16-tic probes yield a 113..128 interval for every prior offset.
  -- This is the fixed-128 hard-bound policy; density no longer defers a save.
  c_checkpoint_min_tics constant pls_integer:=113;
  c_checkpoint_max_tics constant pls_integer:=128;
  c_checkpoint_probe_tics constant pls_integer:=16;
  c_checkpoint_low_awake constant pls_integer:=16;
  c_command_lead_tics constant pls_integer:=8;
  c_standby_poll_seconds constant number:=1;
  g_warm_promotion boolean:=false;

  -- This bounded worker advances complete two-player vectors and fills a
  -- missing peer with a durable neutral command after a fixed deadline.
  -- DMC1 checkpoints and ordered-ledger reconstruction are both durable.

  function utc_now return timestamp with time zone is
  begin return localtimestamp at time zone 'UTC';end;

  function status_field(p_status varchar2,p_name varchar2) return varchar2 is
    l_marker varchar2(128):='|'||p_name||'=';l_start pls_integer;l_end pls_integer;
  begin
    l_start:=instr(p_status,l_marker);
    if l_start=0 then raise_application_error(c_error,'worker status missing '||p_name);end if;
    l_start:=l_start+length(l_marker);l_end:=instr(p_status,'|',l_start);
    if l_end=0 then l_end:=length(p_status)+1;end if;
    return substr(p_status,l_start,l_end-l_start);
  end;

  function sha_raw(p_raw raw) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.hash(p_raw,dbms_crypto.hash_sh256)));
  end;

  function transition_state(
    p_previous varchar2,p_membership raw,p_commands raw
  ) return varchar2 is
    l_state varchar2(64);
  begin
    if not regexp_like(p_previous,'^[0-9a-f]{64}$') or
       p_membership is null or utl_raw.length(p_membership)<>1 or
       p_commands is null or utl_raw.length(p_commands)<>32 then
      raise_application_error(c_error,'transition state material');
    end if;
    select lower(standard_hash(
      'DMS2|'||p_previous||'|'||lower(rawtohex(p_membership))||'|'||
      lower(rawtohex(p_commands)),'SHA256')) into l_state from dual;
    return l_state;
  end;

  function elapsed_micros(
    p_started timestamp with time zone,p_finished timestamp with time zone
  ) return number is
    l_elapsed interval day to second:=p_finished-p_started;
  begin
    return round(extract(day from l_elapsed)*86400000000+
      extract(hour from l_elapsed)*3600000000+
      extract(minute from l_elapsed)*60000000+
      extract(second from l_elapsed)*1000000);
  end;

  procedure copy_blob(p_source blob,p_target out blob) is
  begin
    dbms_lob.createtemporary(p_target,true,dbms_lob.call);
    dbms_lob.copy(p_target,p_source,dbms_lob.getlength(p_source));
  end;

  procedure fail_control(p_match varchar2,p_error varchar2) is
    l_now timestamp with time zone:=(localtimestamp at time zone 'UTC');
  begin
    rollback;
    update doom_match_worker_control set worker_status='FAILED',
      request_status='FAILED',heartbeat=l_now,
      last_error=substr(p_error,1,2000)
      where match_id=p_match;
    -- Slot zero having LEFT is a terminal membership state, not a recoverable
    -- engine crash. Leaving its standby runnable consumed one of Oracle Free's
    -- two session slots and made the next match scheduler-thrash for minutes.
    if instr(p_error,'host membership is not active')>0 then
      update doom_match set match_state='FINISHED',finished_at=l_now,
        last_activity_at=l_now,expires_at=l_now
        where match_id=p_match and match_state='ACTIVE';
      update doom_match_standby_control set stop_requested=1,heartbeat=l_now
        where match_id=p_match and standby_status in('STARTING','READY');
    end if;
    commit;
  end;

  -- Production MLE lifecycle. The OJVM implementations retained below are
  -- named *_ojvm_oracle and are unreachable from RUN_MATCH.
  procedure publish_initial(
    p_match varchar2,p_generation number,p_warm boolean default false
  ) is
    l_skill number;l_episode number;l_map number;l_mode varchar2(16);
    l_epoch number;l_players number;l_serial number;l_state varchar2(64);
    l_now timestamp with time zone:=utc_now;
    l_vector raw(32):=hextoraw(rpad('00',64,'0'));
    l_command_sha varchar2(64);l_previous varchar2(64);l_event varchar2(64);
    l_origin_checkpoint blob;l_origin_checkpoint_sha varchar2(64);
    l_origin_checkpoint_bytes number;
  begin
    select skill,episode,map,game_mode,membership_epoch,max_players
      into l_skill,l_episode,l_map,l_mode,l_epoch,l_players
      from doom_match where match_id=p_match and match_state='LOBBY'
        and generation=0;
    if l_players<>2 then raise_application_error(c_error,'two-player worker required');end if;
    select count(*) into l_players from doom_match_member where match_id=p_match
      and member_state='READY' and membership_epoch=l_epoch;
    if l_players<>2 then raise_application_error(c_error,'membership is not ready');end if;
    if p_warm then
      doom_mle_match_runtime.prepare_origin_warm(2,
        case l_mode when 'DEATHMATCH' then 1 else 0 end,
        l_skill,l_episode,l_map,l_state);
    else
      doom_mle_match_runtime.initialize_game(2,
        case l_mode when 'DEATHMATCH' then 1 else 0 end,
        l_skill,l_episode,l_map,l_state);
    end if;
    -- Recovery must never depend on the first gameplay checkpoint surviving.
    -- Serialize the exact tic-zero origin before taking the match-row lock;
    -- the match is not ACTIVE until this DMC1 payload is durably inserted.
    dbms_application_info.set_action('MLE_ORIGIN_CHECKPOINT');
    doom_mle_match_runtime.save_checkpoint(
      l_origin_checkpoint,l_origin_checkpoint_sha,l_origin_checkpoint_bytes);
    -- Cold TeaVM initialization is intentionally outside the match-row
    -- transaction. Holding this row for roughly two minutes made every
    -- authorized MATCH_STATUS lease renewal wait behind it; overlapping
    -- browser polls could then consume the entire six-connection ORDS pool.
    -- Reacquire and revalidate the immutable launch identity before publishing
    -- tic zero, so admission remains fail-closed without pinning HTTP calls.
    select max_players into l_players from doom_match
      where match_id=p_match and match_state='LOBBY' and generation=0
        and membership_epoch=l_epoch and skill=l_skill and episode=l_episode
        and map=l_map and game_mode=l_mode for update;
    if l_players<>2 then raise_application_error(c_error,'two-player worker required');end if;
    select count(*) into l_players from doom_match_member where match_id=p_match
      and member_state='READY' and membership_epoch=l_epoch;
    if l_players<>2 then
      raise_application_error(c_error,'membership changed during initialization');
    end if;
    l_command_sha:=sha_raw(l_vector);
    select lower(standard_hash('MLE_ROOT|'||l_mode||'|'||l_skill||'|'||
      l_episode||'|'||l_map||'|PLAYERS=2|MEMBERSHIP=03','SHA256'))
      into l_previous from dual;
    select lower(standard_hash('[]','SHA256')) into l_event from dual;
    insert into doom_match_tic(match_id,tic,membership_epoch,generation,
      membership_bitmap,neutral_bitmap,command_vector,command_sha,
      previous_state_sha,state_sha,event_sha,deadline_at,committed_at)
    values(p_match,0,l_epoch,p_generation,hextoraw('03'),hextoraw('00'),
      l_vector,l_command_sha,l_previous,l_state,l_event,l_now,l_now);
    insert into doom_match_checkpoint(match_id,tic,membership_epoch,generation,
      membership_bitmap,command_sha,state_sha,checkpoint_sha,
      checkpoint_bytes,checkpoint_blob,created_at)
    values(p_match,0,l_epoch,p_generation,hextoraw('03'),l_command_sha,l_state,
      l_origin_checkpoint_sha,l_origin_checkpoint_bytes,l_origin_checkpoint,l_now);
    if dbms_lob.istemporary(l_origin_checkpoint)=1 then
      dbms_lob.freetemporary(l_origin_checkpoint);
    end if;
    update doom_match_member set member_state='ACTIVE',generation=p_generation,
      last_seen_at=l_now where match_id=p_match and membership_epoch=l_epoch;
    update doom_match set match_state='ACTIVE',generation=p_generation,
      current_tic=0,started_at=l_now,last_activity_at=l_now
      where match_id=p_match and membership_epoch=l_epoch and generation=0;
    if sql%rowcount<>1 then raise_application_error(c_error,'initial frontier fence');end if;
    -- Tic zero is durable, but the match is not admitted yet. RUN_MATCH keeps
    -- this retained authority session in STARTING until the generation-matched
    -- recovery context has initialized and verified the same origin state.
    select serial# into l_serial from v$session
      where sid=to_number(sys_context('USERENV','SID'))
        and audsid=to_number(sys_context('USERENV','SESSIONID'));
    update doom_match_worker_control set worker_status='STARTING',
      request_status='IDLE',worker_sid=sys_context('USERENV','SID'),
      worker_serial=l_serial,
      heartbeat=l_now,last_error=null where match_id=p_match
        and generation=p_generation and membership_epoch=l_epoch;
    if sql%rowcount<>1 then raise_application_error(c_error,'initial control fence');end if;
    commit;
  exception when others then
    if dbms_lob.istemporary(l_origin_checkpoint)=1 then
      dbms_lob.freetemporary(l_origin_checkpoint);
    end if;
    raise;
  end;

  procedure reconstruct_existing(
    p_match varchar2,p_generation number,p_warm number default 0
  ) is
    l_skill number;l_episode number;l_map number;l_deathmatch number;
    l_epoch number;l_old_generation number;l_tic number;l_checkpoint_tic number:=0;
    l_state varchar2(64);l_expected varchar2(64);l_ignored varchar2(64);
    l_checkpoint blob;
    l_count number;l_serial number;l_now timestamp with time zone:=utc_now;
    l_diagnostics number;
    l_recovery_started timestamp with time zone:=utc_now;
    l_restore_ended timestamp with time zone;
    l_replay_ended timestamp with time zone;
    l_publish_ended timestamp with time zone;
    l_restore_ms number;l_replay_ms number;l_publish_ms number;l_total_ms number;
  begin
    select route_diagnostics into l_diagnostics
      from doom_match_worker_control
      where match_id=p_match and generation=p_generation;
    select skill,episode,map,case game_mode when 'DEATHMATCH' then 1 else 0 end,
      membership_epoch,generation,current_tic
      into l_skill,l_episode,l_map,l_deathmatch,l_epoch,l_old_generation,l_tic
      from doom_match where match_id=p_match and match_state='ACTIVE' for update;
    if p_generation<>l_old_generation+1 then
      raise_application_error(c_error,'recovery generation fence');end if;
    begin
      select tic,checkpoint_blob,state_sha into l_checkpoint_tic,l_checkpoint,l_expected
        from (select tic,checkpoint_blob,state_sha from doom_match_checkpoint
          where match_id=p_match and tic<=l_tic order by tic desc) where rownum=1;
      if p_warm=1 then
        doom_mle_match_runtime.restore_checkpoint_warm(2,l_deathmatch,l_skill,
          l_episode,l_map,l_checkpoint_tic,l_checkpoint,l_state);
      else
        doom_mle_match_runtime.restore_checkpoint(2,l_deathmatch,l_skill,
          l_episode,l_map,l_checkpoint_tic,l_checkpoint,l_state);
      end if;
      -- checkpoint_sha authenticates the exact restored DMC1 bytes. Continue
      -- the lightweight live replay chain from its recorded frontier.
      l_state:=l_expected;
    exception when no_data_found then
      if p_warm=1 then
        raise_application_error(c_error,'warm recovery requires DMC1 checkpoint');
      end if;
      doom_mle_match_runtime.initialize_game(2,l_deathmatch,l_skill,
        l_episode,l_map,l_state);
      select state_sha into l_expected from doom_match_tic
        where match_id=p_match and tic=0;
      if l_state<>l_expected then
        raise_application_error(c_error,'MLE recovery root mismatch');end if;
    end;
    l_restore_ended:=utc_now;
    for step_ in (select tic,membership_bitmap,command_vector,state_sha
      from doom_match_tic where match_id=p_match
        and tic between l_checkpoint_tic+1 and l_tic order by tic) loop
      doom_mle_match_runtime.step_game(2,
        to_number(rawtohex(step_.membership_bitmap),'xx'),step_.tic,
        step_.command_vector,l_ignored);
      l_state:=transition_state(l_state,
        step_.membership_bitmap,step_.command_vector);
      if l_state<>step_.state_sha then
        raise_application_error(c_error,'MLE recovery state mismatch tic='||step_.tic);end if;
    end loop;
    l_replay_ended:=utc_now;
    update doom_match_tic set generation=p_generation
      where match_id=p_match and tic=l_tic and generation=l_old_generation;
    update doom_match_checkpoint set generation=p_generation
      where match_id=p_match and tic=l_checkpoint_tic and generation=l_old_generation;
    update doom_match_command set generation=p_generation
      where match_id=p_match and tic between l_tic+1 and l_tic+c_command_lead_tics
        and generation=l_old_generation;
    update doom_match_member set generation=p_generation
      where match_id=p_match and membership_epoch=l_epoch
        and member_state in('ACTIVE','DISCONNECTED','LEFT');
    update doom_match set generation=p_generation,last_activity_at=l_now
      where match_id=p_match and generation=l_old_generation
        and membership_epoch=l_epoch and current_tic=l_tic;
    if sql%rowcount<>1 then raise_application_error(c_error,'recovery publish fence');end if;
    select count(*) into l_count from doom_match_command where match_id=p_match
      and tic=l_tic+1 and generation=p_generation and membership_epoch=l_epoch;
    select serial# into l_serial from v$session
      where sid=to_number(sys_context('USERENV','SID'))
        and audsid=to_number(sys_context('USERENV','SESSIONID'));
    update doom_match_worker_control set worker_status='READY',
      request_status=case when l_count=2 then 'QUEUED' else 'IDLE' end,
      requested_tic=case when l_count=2 then l_tic+1 else null end,
      worker_sid=sys_context('USERENV','SID'),worker_serial=l_serial,
      heartbeat=l_now,last_error=null
      where match_id=p_match and generation=p_generation
        and membership_epoch=l_epoch and worker_status='STARTING';
    if sql%rowcount<>1 then raise_application_error(c_error,'recovery control fence');end if;
    commit;
    l_publish_ended:=utc_now;
    if l_diagnostics=1 then
      l_restore_ms:=elapsed_micros(l_recovery_started,l_restore_ended)/1000;
      l_replay_ms:=elapsed_micros(l_restore_ended,l_replay_ended)/1000;
      l_publish_ms:=elapsed_micros(l_replay_ended,l_publish_ended)/1000;
      l_total_ms:=elapsed_micros(l_recovery_started,l_publish_ended)/1000;
      update doom_match_worker_control set
        recovery_checkpoint_tic=l_checkpoint_tic,
        recovery_frontier_tic=l_tic,
        recovery_restore_ms=l_restore_ms,
        recovery_replay_ms=l_replay_ms,
        recovery_publish_ms=l_publish_ms,
        recovery_worker_total_ms=l_total_ms,
        recovery_measured_at=l_publish_ended
        where match_id=p_match and generation=p_generation;
      commit;
    end if;
  end;

  procedure record_slow_call(
    p_match varchar2,p_generation number,p_tic number,
    p_started timestamp with time zone,p_ended timestamp with time zone,
    p_elapsed_ms number,p_pre_mle_ms number default null,
    p_mle_ms number default null,p_post_mle_ms number default null,
    p_commit_ms number default null,p_checkpoint_save_ms number default null,
    p_checkpoint_publish_ms number default null
  ) is
    pragma autonomous_transaction;
  begin
    insert into doom_match_slow_call(match_id,tic,generation,worker_sid,
      started_at,ended_at,elapsed_ms,pre_mle_ms,mle_ms,post_mle_ms,
      commit_ms,checkpoint_save_ms,checkpoint_publish_ms,stage)
    values(p_match,p_tic,p_generation,sys_context('USERENV','SID'),
      p_started,p_ended,p_elapsed_ms,p_pre_mle_ms,p_mle_ms,p_post_mle_ms,
      p_commit_ms,p_checkpoint_save_ms,p_checkpoint_publish_ms,
      'PROCESS_STEP_COMMIT');
    commit;
  end;

  procedure checkpoint_busy(
    p_match varchar2,p_generation number,p_busy number
  ) is
    pragma autonomous_transaction;
  begin
    update doom_match_worker_control set
      busy_until=case when p_busy=1 then
        (localtimestamp at time zone 'UTC')+
          numtodsinterval(60,'SECOND') else null end,
      heartbeat=case when p_busy=1 then
        localtimestamp at time zone 'UTC' else heartbeat end
      where match_id=p_match and generation=p_generation
        and worker_sid=to_number(sys_context('USERENV','SID'));
    if sql%rowcount<>1 then
      raise_application_error(c_error,'checkpoint busy lease fence');
    end if;
    commit;
  end;

  procedure process_step(
    p_match varchar2,p_generation number,p_epoch number,p_tic number,
    p_paced number default 0,p_diagnostics number default 0,
    p_checkpoint_test_hook number default 0
  ) is
    l_previous varchar2(64);l_vector_hex varchar2(64);l_state varchar2(64);
    l_command_sha varchar2(64);l_previous_chain varchar2(64);l_event varchar2(64);
    l_count number;l_neutral number;l_membership number;l_next_count number;
    l_now timestamp with time zone:=utc_now;l_deadline timestamp with time zone;
    l_eligible timestamp with time zone;l_input raw(8);l_payload raw(32767);
    l_checkpoint blob;l_checkpoint_sha varchar2(64);l_checkpoint_bytes number;
    l_step_started timestamp with time zone:=utc_now;
    l_step_ended timestamp with time zone;l_step_elapsed_ms number;
    l_pre_mle_ended timestamp with time zone;
    l_mle_ended timestamp with time zone;
    l_precommit_ended timestamp with time zone;
    l_checkpoint_diagnostic number:=0;
    l_checkpoint_due number:=0;
    l_last_checkpoint_tic number:=0;
    l_awake_monsters number;
    l_memory_status varchar2(32767);
    l_checkpoint_save_started timestamp with time zone;
    l_checkpoint_save_ended timestamp with time zone;
    l_checkpoint_publish_ended timestamp with time zone;
  begin
    select state_sha into l_previous from doom_match_tic
      where match_id=p_match and tic=p_tic-1 and generation=p_generation;
    select count(*),lower(listagg(rawtohex(ticcmd_raw),'') within group(order by player_slot)),
      coalesce(sum(case when command_source like 'NEUTRAL_%'
        then power(2,player_slot) else 0 end),0),min(submitted_at)
      into l_count,l_vector_hex,l_neutral,l_deadline from doom_match_command
      where match_id=p_match and tic=p_tic and membership_epoch=p_epoch
        and generation=p_generation and player_slot in(0,1);
    if l_count<>2 or length(l_vector_hex)<>32 then
      raise_application_error(c_error,'complete two-player vector required');end if;
    select coalesce(sum(case when member_state<>'LEFT' or leave_tic is null
      or leave_tic>p_tic then power(2,player_slot) else 0 end),0)
      into l_membership from doom_match_member where match_id=p_match
        and player_slot in(0,1) and membership_epoch=p_epoch
        and generation=p_generation;
    if bitand(l_membership,1)<>1 then
      raise_application_error(c_error,'host membership is not active');end if;
    select committed_at into l_eligible from doom_match_tic
      where match_id=p_match and tic=p_tic-1;
    l_deadline:=greatest(l_deadline,l_eligible)+numtodsinterval(
      case when p_tic=1 then c_initial_command_deadline_ms
           else c_command_deadline_ms end/1000,'SECOND');
    if l_deadline>l_now then l_deadline:=l_now;end if;
    if p_paced=0 then for l_slot in 0..1 loop
      begin
        select ticcmd_raw into l_input from (select ticcmd_raw
          from doom_match_input_event where match_id=p_match
            and player_slot=l_slot and membership_epoch=p_epoch
            and effective_tic<=p_tic order by input_seq desc) where rownum=1;
        l_vector_hex:=substr(l_vector_hex,1,l_slot*16)||rawtohex(l_input)||
          substr(l_vector_hex,l_slot*16+17);
      exception when no_data_found then null;end;
    end loop;end if;
    l_vector_hex:=lower(l_vector_hex||rpad('00',32,'0'));
    l_pre_mle_ended:=utc_now;
    dbms_application_info.set_action('MLE_STEP');
    doom_mle_match_runtime.step_game(2,l_membership,p_tic,
      hextoraw(l_vector_hex),l_state);
    l_mle_ended:=utc_now;
    l_state:=transition_state(l_previous,
      hextoraw(lpad(to_char(l_membership,'fmxx'),2,'0')),
      hextoraw(l_vector_hex));
    l_command_sha:=sha_raw(hextoraw(l_vector_hex));
    select lower(standard_hash('[]','SHA256')) into l_event from dual;
    insert into doom_match_tic(match_id,tic,membership_epoch,generation,
      membership_bitmap,neutral_bitmap,command_vector,command_sha,
      previous_state_sha,state_sha,event_sha,deadline_at,committed_at)
    values(p_match,p_tic,p_epoch,p_generation,
      hextoraw(lpad(to_char(l_membership,'fmxx'),2,'0')),
      hextoraw(lpad(to_char(l_neutral,'fmxx'),2,'0')),
      hextoraw(l_vector_hex),l_command_sha,l_previous,l_state,l_event,l_deadline,
      greatest(l_deadline,(localtimestamp at time zone 'UTC')));
    if p_tic=1 then
      select lower(standard_hash('DMD1_ROOT|'||p_match||'|'||p_epoch,'SHA256'))
        into l_previous_chain from dual;
    else
      select chain_sha into l_previous_chain from doom_match_transition
        where match_id=p_match and tic=p_tic-1;
    end if;
    l_payload:=doom_mle_authority_delta.encode(p_tic,p_generation,p_epoch,
      hextoraw(lpad(to_char(l_membership,'fmxx'),2,'0')),2,l_previous_chain,
      null,hextoraw(l_vector_hex),'[]',0);
    doom_mle_transition_transport.publish(p_match,l_payload);
    -- Test scaffold only: CHECKPOINT_TEST_HOOK may force a tic-64 checkpoint
    -- for liveness attribution. ROUTE_DIAGNOSTICS observes production cadence
    -- without changing it.
    if p_checkpoint_test_hook=1 and p_tic=64 then
      l_checkpoint_diagnostic:=1;
    end if;
    -- Diagnostic-only high-density serializer measurement. Mode 2 forces one
    -- checkpoint at tic 256 without changing the production cadence decision
    -- or its DEFER_HIGH/FORCED_MAX evidence.
    if p_checkpoint_test_hook=2 and p_tic=256 then
      l_checkpoint_diagnostic:=1;
    end if;
    if mod(p_tic,c_checkpoint_probe_tics)=0 then
      select coalesce(max(tic),0) into l_last_checkpoint_tic
        from doom_match_checkpoint where match_id=p_match
          and generation=p_generation;
      if p_tic-l_last_checkpoint_tic>=c_checkpoint_min_tics then
        -- This existing diagnostic export is sampled only during the bounded
        -- checkpoint opportunity window, never on every production tic.
        l_memory_status:=doom_teavm_sim_memory;
        l_awake_monsters:=to_number(status_field(
          l_memory_status,'awakeMonsters'));
        if p_tic-l_last_checkpoint_tic>=
            c_checkpoint_max_tics-c_checkpoint_probe_tics+1 then
          -- Probing on absolute 16-tic boundaries with this conservative
          -- threshold guarantees no interval can exceed 128 tics, even when a
          -- membership/recovery checkpoint was created off-boundary.
          l_checkpoint_due:=1;
        elsif l_awake_monsters<=c_checkpoint_low_awake then
          l_checkpoint_due:=1;
        end if;
        if p_diagnostics=1 then
          insert into doom_match_checkpoint_probe(
            match_id,tic,generation,previous_checkpoint_tic,
            checkpoint_distance,awake_monsters,checkpoint_decision)
          values(p_match,p_tic,p_generation,l_last_checkpoint_tic,
            p_tic-l_last_checkpoint_tic,l_awake_monsters,
            case
              when p_tic-l_last_checkpoint_tic>=
                c_checkpoint_max_tics-c_checkpoint_probe_tics+1
                then 'FORCED_MAX'
              when l_awake_monsters<=c_checkpoint_low_awake then 'LOW_AWAKE'
              else 'DEFER_HIGH'
            end);
        end if;
      end if;
    end if;
    if l_checkpoint_diagnostic=1 or l_checkpoint_due=1 then
      -- Checkpoint serialization is a long but healthy retained MLE call on
      -- Free. Expose that state so REST liveness checks distinguish it from
      -- a dead authority session instead of triggering a competing recovery.
      checkpoint_busy(p_match,p_generation,1);
      dbms_application_info.set_action('MLE_CHECKPOINT');
      l_checkpoint_save_started:=utc_now;
      begin
        doom_mle_match_runtime.save_checkpoint(
          l_checkpoint,l_checkpoint_sha,l_checkpoint_bytes);
      exception when others then
        dbms_application_info.set_action('MLE_STEP');
        checkpoint_busy(p_match,p_generation,0);
        raise;
      end;
      l_checkpoint_save_ended:=utc_now;
      dbms_application_info.set_action('MLE_STEP');
      checkpoint_busy(p_match,p_generation,0);
      insert into doom_match_checkpoint(match_id,tic,membership_epoch,generation,
        membership_bitmap,command_sha,state_sha,checkpoint_sha,
        checkpoint_bytes,checkpoint_blob,created_at)
      values(p_match,p_tic,p_epoch,p_generation,
        hextoraw(lpad(to_char(l_membership,'fmxx'),2,'0')),l_command_sha,
        l_state,l_checkpoint_sha,l_checkpoint_bytes,l_checkpoint,l_now);
      if dbms_lob.istemporary(l_checkpoint)=1 then dbms_lob.freetemporary(l_checkpoint);end if;
      delete from doom_match_checkpoint where match_id=p_match
        and tic<p_tic-c_checkpoint_max_tics;
      l_checkpoint_publish_ended:=utc_now;
    end if;
    update doom_match set current_tic=p_tic,last_activity_at=l_now
      where match_id=p_match and match_state='ACTIVE' and generation=p_generation
        and membership_epoch=p_epoch and current_tic=p_tic-1;
    if sql%rowcount<>1 then raise_application_error(c_error,'step frontier fence');end if;
    select count(*) into l_next_count from doom_match_command
      where match_id=p_match and tic=p_tic+1 and membership_epoch=p_epoch
        and generation=p_generation and player_slot in(0,1);
    update doom_match_worker_control set
      request_status=case when l_next_count=2 then 'QUEUED' else 'IDLE' end,
      requested_tic=case when l_next_count=2 then p_tic+1 else null end,
      heartbeat=l_now,last_error=null where match_id=p_match
        and generation=p_generation and membership_epoch=p_epoch
        and request_status='PROCESSING' and requested_tic=p_tic;
    if sql%rowcount<>1 then raise_application_error(c_error,'step control fence');end if;
    l_precommit_ended:=utc_now;
    dbms_application_info.set_action('COMMIT');commit;
    l_step_ended:=utc_now;
    l_step_elapsed_ms:=elapsed_micros(l_step_started,l_step_ended)/1000;
    if l_step_elapsed_ms>100 then
      record_slow_call(p_match,p_generation,p_tic,l_step_started,l_step_ended,
        l_step_elapsed_ms,
        elapsed_micros(l_step_started,l_pre_mle_ended)/1000,
        elapsed_micros(l_pre_mle_ended,l_mle_ended)/1000,
        elapsed_micros(l_mle_ended,l_precommit_ended)/1000,
        elapsed_micros(l_precommit_ended,l_step_ended)/1000,
        case when l_checkpoint_save_started is not null then
          elapsed_micros(l_checkpoint_save_started,l_checkpoint_save_ended)/1000 end,
        case when l_checkpoint_save_ended is not null then
          elapsed_micros(l_checkpoint_save_ended,l_checkpoint_publish_ended)/1000 end);
    end if;
    dbms_application_info.set_action(null);
  exception when others then
    if dbms_lob.istemporary(l_checkpoint)=1 then dbms_lob.freetemporary(l_checkpoint);end if;
    raise;
  end;

  $if $$doom_dev_ojvm $then
  procedure publish_initial_ojvm_oracle(p_match varchar2,p_generation number) is
    l_skill number;l_episode number;l_map number;l_mode varchar2(16);
    l_epoch number;l_players number;l_status varchar2(4000);l_now timestamp with time zone:=utc_now;
    l_b0 blob;l_b1 blob;l_state varchar2(64);l_frame0 varchar2(64);l_frame1 varchar2(64);
    l_response0 varchar2(64);l_response1 varchar2(64);l_bytes0 number;l_bytes1 number;
    l_actual0 number;l_actual1 number;
    l_vector raw(32):=hextoraw(rpad('00',64,'0'));l_command_sha varchar2(64);
    l_previous varchar2(64);l_event varchar2(64);
  begin
    select skill,episode,map,game_mode,membership_epoch,max_players
      into l_skill,l_episode,l_map,l_mode,l_epoch,l_players
      from doom_match where match_id=p_match and match_state='LOBBY'
        and generation=0 for update;
    if l_players<>2 then raise_application_error(c_error,'two-player worker required');end if;
    select count(*) into l_players from doom_match_member where match_id=p_match
      and member_state='READY' and membership_epoch=l_epoch;
    if l_players<>2 then raise_application_error(c_error,'membership is not ready');end if;

    insert into doom_match_frame(match_id,tic,player_slot,membership_epoch,
      generation,frame_sha,response_sha,response_bytes,response_blob,created_at)
    values(p_match,0,0,l_epoch,p_generation,rpad('0',64,'0'),rpad('0',64,'0'),
      1,empty_blob(),l_now) returning response_blob into l_b0;
    insert into doom_match_frame(match_id,tic,player_slot,membership_epoch,
      generation,frame_sha,response_sha,response_bytes,response_blob,created_at)
    values(p_match,0,1,l_epoch,p_generation,rpad('0',64,'0'),rpad('0',64,'0'),
      1,empty_blob(),l_now) returning response_blob into l_b1;
    l_status:=doom_mocha_multiplayer_new_game(2,
      case l_mode when 'DEATHMATCH' then 1 else 0 end,
      l_skill,l_episode,l_map,l_b0,l_b1,null,null);
    if substr(l_status,1,3)<>'ok|' then
      raise_application_error(c_error,substr(l_status,1,1800));
    end if;
    if to_number(status_field(l_status,'tic'))<>0 then
      raise_application_error(c_error,'initial tic is not zero');
    end if;
    l_state:=status_field(l_status,'stateSha256');
    l_frame0:=status_field(l_status,'pov0FrameSha');
    l_frame1:=status_field(l_status,'pov1FrameSha');
    l_response0:=status_field(l_status,'pov0ResponseSha');
    l_response1:=status_field(l_status,'pov1ResponseSha');
    l_bytes0:=to_number(status_field(l_status,'pov0Bytes'));
    l_bytes1:=to_number(status_field(l_status,'pov1Bytes'));
    -- OJVM mutates the persistent LOBs directly. Refresh their lengths from
    -- SQL because the PL/SQL locator metadata can remain stale after Java.
    select max(case player_slot when 0 then dbms_lob.getlength(response_blob) end),
           max(case player_slot when 1 then dbms_lob.getlength(response_blob) end)
      into l_actual0,l_actual1 from doom_match_frame
      where match_id=p_match and tic=0;
    if l_actual0<>l_bytes0 or l_actual1<>l_bytes1 then
      raise_application_error(c_error,'initial locator length mismatch');
    end if;
    update doom_match_frame set frame_sha=l_frame0,response_sha=l_response0,
      response_bytes=l_bytes0 where match_id=p_match and tic=0 and player_slot=0;
    update doom_match_frame set frame_sha=l_frame1,response_sha=l_response1,
      response_bytes=l_bytes1 where match_id=p_match and tic=0 and player_slot=1;
    l_command_sha:=sha_raw(l_vector);
    -- Match identifiers are transport metadata, not engine state. Identical
    -- engine configuration and membership must produce the same root.
    select lower(standard_hash('MULTI_ROOT|'||l_mode||'|'||l_skill||'|'||
      l_episode||'|'||l_map||'|PLAYERS=2|MEMBERSHIP=03','SHA256'))
      into l_previous from dual;
    select lower(standard_hash('[]','SHA256')) into l_event from dual;
    insert into doom_match_tic(match_id,tic,membership_epoch,generation,
      membership_bitmap,neutral_bitmap,command_vector,command_sha,
      previous_state_sha,state_sha,event_sha,deadline_at,committed_at)
    values(p_match,0,l_epoch,p_generation,hextoraw('03'),hextoraw('00'),
      l_vector,l_command_sha,l_previous,l_state,l_event,l_now,l_now);
    update doom_match_member set member_state='ACTIVE',generation=p_generation,
      last_seen_at=l_now where match_id=p_match and membership_epoch=l_epoch;
    update doom_match set match_state='ACTIVE',generation=p_generation,
      current_tic=0,started_at=l_now,last_activity_at=l_now
      where match_id=p_match and membership_epoch=l_epoch and generation=0;
    if sql%rowcount<>1 then raise_application_error(c_error,'initial frontier fence');end if;
    update doom_match_worker_control set worker_status='READY',
      request_status='IDLE',worker_sid=sys_context('USERENV','SID'),
      heartbeat=l_now,last_error=null where match_id=p_match
        and generation=p_generation and membership_epoch=l_epoch;
    if sql%rowcount<>1 then raise_application_error(c_error,'initial control fence');end if;
    commit;
  end;

  procedure reconstruct_existing_ojvm_oracle(p_match varchar2,p_generation number) is
    l_skill number;l_episode number;l_map number;l_deathmatch number;
    l_epoch number;l_old_generation number;l_tic number;l_status varchar2(4000);
    l_initial_state varchar2(64);l_expected_state varchar2(64);
    l_expected_frame0 varchar2(64);l_expected_frame1 varchar2(64);
    l_actual_frame0 varchar2(64);l_actual_frame1 varchar2(64);
    l_stream blob;l_b0 blob;l_b1 blob;l_now timestamp with time zone:=utc_now;
    l_count number;l_membership number;
  begin
    select skill,episode,map,case game_mode when 'DEATHMATCH' then 1 else 0 end,
      membership_epoch,generation,current_tic
      into l_skill,l_episode,l_map,l_deathmatch,l_epoch,l_old_generation,l_tic
      from doom_match where match_id=p_match and match_state='ACTIVE' for update;
    if p_generation<>l_old_generation+1 then
      raise_application_error(c_error,'recovery generation fence');
    end if;
    select state_sha into l_initial_state from doom_match_tic
      where match_id=p_match and tic=0;
    select state_sha into l_expected_state from doom_match_tic
      where match_id=p_match and tic=l_tic;
    select to_number(rawtohex(membership_bitmap),'xx') into l_membership
      from doom_match_tic where match_id=p_match and tic=l_tic;
    select frame_sha,response_blob into l_expected_frame0,l_b0
      from doom_match_frame where match_id=p_match and tic=l_tic and player_slot=0
      for update;
    if bitand(l_membership,2)=2 then
      select frame_sha,response_blob into l_expected_frame1,l_b1
        from doom_match_frame where match_id=p_match and tic=l_tic and player_slot=1
        for update;
    end if;
    dbms_lob.createtemporary(l_stream,true,dbms_lob.call);
    for vector_ in (select membership_bitmap,command_vector from doom_match_tic
      where match_id=p_match and tic between 1 and l_tic order by tic) loop
      dbms_lob.writeappend(l_stream,33,
        utl_raw.concat(vector_.membership_bitmap,vector_.command_vector));
    end loop;
    l_status:=doom_mocha_multiplayer_reconstruct(2,l_deathmatch,l_skill,
      l_episode,l_map,l_stream,l_initial_state,l_expected_state,
      l_b0,l_b1,null,null);
    if substr(l_status,1,3)<>'ok|' then
      raise_application_error(c_error,substr(l_status,1,1800));
    end if;
    l_actual_frame0:=status_field(l_status,'pov0FrameSha');
    if bitand(l_membership,2)=2 then
      l_actual_frame1:=status_field(l_status,'pov1FrameSha');
    end if;
    if l_actual_frame0<>l_expected_frame0 or
       (bitand(l_membership,2)=2 and l_actual_frame1<>l_expected_frame1) then
      raise_application_error(c_error,'recovery POV mismatch p0='||
        substr(l_expected_frame0,1,12)||'/'||substr(l_actual_frame0,1,12)||
        ' p1='||substr(l_expected_frame1,1,12)||'/'||substr(l_actual_frame1,1,12));
    end if;
    update doom_match_frame set generation=p_generation
      where match_id=p_match and tic=l_tic;
    update doom_match_tic set generation=p_generation
      where match_id=p_match and tic=l_tic and generation=l_old_generation;
    update doom_match_checkpoint set generation=p_generation
      where match_id=p_match and tic=l_tic and generation=l_old_generation;
    update doom_match_command set generation=p_generation
      where match_id=p_match
        and tic between l_tic+1 and l_tic+c_command_lead_tics
        and generation=l_old_generation;
    update doom_match_member set generation=p_generation
      where match_id=p_match and membership_epoch=l_epoch
        and member_state in('ACTIVE','DISCONNECTED','LEFT');
    update doom_match set generation=p_generation,last_activity_at=l_now
      where match_id=p_match and generation=l_old_generation
        and membership_epoch=l_epoch and current_tic=l_tic;
    if sql%rowcount<>1 then raise_application_error(c_error,'recovery publish fence');end if;
    select count(*) into l_count from doom_match_command where match_id=p_match
      and tic=l_tic+1 and generation=p_generation and membership_epoch=l_epoch;
    update doom_match_worker_control set worker_status='READY',
      request_status=case when l_count=2 then 'QUEUED' else 'IDLE' end,
      requested_tic=case when l_count=2 then l_tic+1 else null end,
      worker_sid=sys_context('USERENV','SID'),heartbeat=l_now,last_error=null
      where match_id=p_match and generation=p_generation
        and membership_epoch=l_epoch and worker_status='STARTING';
    if sql%rowcount<>1 then raise_application_error(c_error,'recovery control fence');end if;
    commit;
  end;

  procedure process_step_ojvm_oracle(
    p_match varchar2,p_generation number,p_epoch number,p_tic number,
    p_paced number default 0
  ) is
    l_previous varchar2(64);l_vector_hex varchar2(64);l_applied_hex varchar2(64);
    l_status varchar2(4000);l_route_status varchar2(4000);
    l_state varchar2(64);l_command_sha varchar2(64);
    l_frame0 varchar2(64);l_frame1 varchar2(64);l_response0 varchar2(64);l_response1 varchar2(64);
    l_bytes0 number;l_bytes1 number;l_actual0 number;l_actual1 number;
    l_count number;l_neutral number;l_membership number;l_route_diagnostics number;
    l_next_count number;
    l_now timestamp with time zone:=utc_now;
    l_deadline timestamp with time zone;
    l_eligible timestamp with time zone;
    l_b0 blob;l_b1 blob;l_checkpoint blob;l_event varchar2(64);
    l_checkpoint_status varchar2(4000);l_checkpoint_sha varchar2(64);
    l_checkpoint_bytes number;l_checkpoint_actual number;
    l_input raw(8);
    l_sql_started timestamp with time zone;l_java_started timestamp with time zone;
    l_java_done timestamp with time zone;
    l_frame_rows_started timestamp with time zone;l_frame_finalized timestamp with time zone;
    l_ledger_done timestamp with time zone;l_retirement_started timestamp with time zone;
    l_retirement_done timestamp with time zone;l_frontier_done timestamp with time zone;
    l_commit_started timestamp with time zone;l_commit_done timestamp with time zone;
    l_commit_micros number;
  begin
    select state_sha into l_previous from doom_match_tic
      where match_id=p_match and tic=p_tic-1 and generation=p_generation;
    select route_diagnostics into l_route_diagnostics
      from doom_match_worker_control where match_id=p_match
        and generation=p_generation and membership_epoch=p_epoch;
    if l_route_diagnostics=1 then l_sql_started:=utc_now;end if;
    select count(*),lower(listagg(rawtohex(ticcmd_raw),'') within group(order by player_slot)),
      coalesce(sum(case when command_source like 'NEUTRAL_%'
        then power(2,player_slot) else 0 end),0),min(submitted_at)
      into l_count,l_vector_hex,l_neutral,l_deadline from doom_match_command
      where match_id=p_match and tic=p_tic and membership_epoch=p_epoch
        and generation=p_generation and player_slot in(0,1);
    if l_count<>2 or length(l_vector_hex)<>32 then
      raise_application_error(c_error,'complete two-player vector required');
    end if;
    select coalesce(sum(case when member_state<>'LEFT' or leave_tic is null
      or leave_tic>p_tic then power(2,player_slot) else 0 end),0)
      into l_membership from doom_match_member where match_id=p_match
        and player_slot in(0,1) and membership_epoch=p_epoch
        and generation=p_generation;
    if bitand(l_membership,1)<>1 then
      raise_application_error(c_error,'host membership is not active');
    end if;
    select committed_at into l_eligible from doom_match_tic
      where match_id=p_match and tic=p_tic-1;
    l_deadline:=greatest(l_deadline,l_eligible)+numtodsinterval(
      case when p_tic=1 then c_initial_command_deadline_ms
           else c_command_deadline_ms end/1000,'SECOND');
    if l_deadline>l_now then l_deadline:=l_now;end if;
    -- Reservation rows stay immutable for transport retry. The latest
    -- committed two-tic input transition overlays each active slot before the
    -- exact applied vector is hashed and written to the replay ledger.
    if p_paced=0 then
      for l_slot in 0..1 loop
        begin
          select ticcmd_raw into l_input from (
            select ticcmd_raw from doom_match_input_event
              where match_id=p_match and player_slot=l_slot
                and membership_epoch=p_epoch and effective_tic<=p_tic
              order by input_seq desc
          ) where rownum=1;
          l_vector_hex:=substr(l_vector_hex,1,l_slot*16)||rawtohex(l_input)||
            substr(l_vector_hex,l_slot*16+17);
        exception when no_data_found then null;end;
      end loop;
    end if;
    l_vector_hex:=lower(l_vector_hex||rpad('00',32,'0'));
    if l_route_diagnostics=1 then
      l_frame_rows_started:=utc_now;dbms_application_info.set_action('FRAME_ROWS');
    end if;
    insert into doom_match_frame(match_id,tic,player_slot,membership_epoch,
      generation,frame_sha,response_sha,response_bytes,response_blob,created_at)
    values(p_match,p_tic,0,p_epoch,p_generation,rpad('0',64,'0'),
      rpad('0',64,'0'),1,empty_blob(),l_now) returning response_blob into l_b0;
    if bitand(l_membership,2)=2 then
      insert into doom_match_frame(match_id,tic,player_slot,membership_epoch,
        generation,frame_sha,response_sha,response_bytes,response_blob,created_at)
      values(p_match,p_tic,1,p_epoch,p_generation,rpad('0',64,'0'),
        rpad('0',64,'0'),1,empty_blob(),l_now) returning response_blob into l_b1;
    end if;
    if l_route_diagnostics=1 then
      l_java_started:=utc_now;dbms_application_info.set_action('OJVM_STEP');
    end if;
    l_status:=doom_mocha_multiplayer_step(
      2,l_membership,l_vector_hex,l_previous,l_b0,l_b1,null,null);
    if l_route_diagnostics=1 then l_java_done:=utc_now;end if;
    if substr(l_status,1,3)<>'ok|' then
      raise_application_error(c_error,substr(l_status,1,1800));
    end if;
    if to_number(status_field(l_status,'tic'))<>p_tic then
      raise_application_error(c_error,'worker tic mismatch');
    end if;
    l_state:=status_field(l_status,'stateSha256');
    l_route_status:=status_field(l_status,'routeDiag');
    l_applied_hex:=status_field(l_status,'commandVector');
    l_frame0:=status_field(l_status,'pov0FrameSha');
    if bitand(l_membership,2)=2 then
      l_frame1:=status_field(l_status,'pov1FrameSha');
    end if;
    l_response0:=status_field(l_status,'pov0ResponseSha');
    if bitand(l_membership,2)=2 then
      l_response1:=status_field(l_status,'pov1ResponseSha');
    end if;
    l_bytes0:=to_number(status_field(l_status,'pov0Bytes'));
    if bitand(l_membership,2)=2 then
      l_bytes1:=to_number(status_field(l_status,'pov1Bytes'));
    end if;
    select max(case player_slot when 0 then dbms_lob.getlength(response_blob) end),
           max(case player_slot when 1 then dbms_lob.getlength(response_blob) end)
      into l_actual0,l_actual1 from doom_match_frame
      where match_id=p_match and tic=p_tic;
    if l_actual0<>l_bytes0 or
       (bitand(l_membership,2)=2 and l_actual1<>l_bytes1) then
      raise_application_error(c_error,'step locator length mismatch');
    end if;
    update doom_match_frame set frame_sha=l_frame0,response_sha=l_response0,
      response_bytes=l_bytes0 where match_id=p_match and tic=p_tic and player_slot=0;
    if bitand(l_membership,2)=2 then
      update doom_match_frame set frame_sha=l_frame1,response_sha=l_response1,
        response_bytes=l_bytes1 where match_id=p_match and tic=p_tic and player_slot=1;
    end if;
    if l_route_diagnostics=1 then
      l_frame_finalized:=utc_now;dbms_application_info.set_action('LEDGER_CHECKPOINT');
    end if;
    l_command_sha:=sha_raw(hextoraw(l_applied_hex));
    select lower(standard_hash('[]','SHA256')) into l_event from dual;
    insert into doom_match_tic(match_id,tic,membership_epoch,generation,
      membership_bitmap,neutral_bitmap,command_vector,command_sha,
      previous_state_sha,state_sha,event_sha,deadline_at,committed_at)
    values(p_match,p_tic,p_epoch,p_generation,
      hextoraw(lpad(to_char(l_membership,'fmxx'),2,'0')),
      hextoraw(lpad(to_char(l_neutral,'fmxx'),2,'0')),
      hextoraw(l_applied_hex),l_command_sha,l_previous,l_state,l_event,l_deadline,
      greatest(l_deadline,(localtimestamp at time zone 'UTC')));
    if mod(p_tic,c_checkpoint_max_tics)=0 then
      insert into doom_match_checkpoint(match_id,tic,membership_epoch,generation,
        membership_bitmap,command_sha,state_sha,checkpoint_sha,
        checkpoint_bytes,checkpoint_blob,created_at)
      values(p_match,p_tic,p_epoch,p_generation,
        hextoraw(lpad(to_char(l_membership,'fmxx'),2,'0')),l_command_sha,
        l_state,rpad('0',64,'0'),1,empty_blob(),l_now)
      returning checkpoint_blob into l_checkpoint;
      l_checkpoint_status:=doom_mocha_save(l_checkpoint);
      if substr(l_checkpoint_status,1,3)<>'ok|' then
        raise_application_error(c_error,substr(l_checkpoint_status,1,1800));
      end if;
      l_checkpoint_sha:=status_field(l_checkpoint_status,'checkpointSha256');
      l_checkpoint_bytes:=to_number(status_field(l_checkpoint_status,'checkpointBytes'));
      select dbms_lob.getlength(checkpoint_blob) into l_checkpoint_actual
        from doom_match_checkpoint where match_id=p_match and tic=p_tic;
      if l_checkpoint_actual<>l_checkpoint_bytes then
        raise_application_error(c_error,'checkpoint locator length mismatch');
      end if;
      update doom_match_checkpoint set checkpoint_sha=l_checkpoint_sha,
        checkpoint_bytes=l_checkpoint_bytes where match_id=p_match and tic=p_tic;
      -- Two native checkpoints are sufficient for operational inspection. The
      -- compact per-tic vector ledger remains complete for exact replay.
      delete from doom_match_checkpoint where match_id=p_match
        and tic<p_tic-c_checkpoint_max_tics;
    end if;
    if l_route_diagnostics=1 then
      l_ledger_done:=utc_now;l_retirement_started:=l_ledger_done;
      dbms_application_info.set_action('FRAME_RETIRE');
    end if;
    -- Response BLOBs dominate storage (~128 KiB/tic for two POVs). Retain tic
    -- zero plus a bounded late-poll window; exact restart uses command vectors
    -- and the selected frontier frames, not historical response BLOBs.
    if p_tic>c_frame_retention_tics then
      delete from doom_match_frame where match_id=p_match
        and tic=p_tic-c_frame_retention_tics;
    end if;
    if l_route_diagnostics=1 then
      l_retirement_done:=utc_now;dbms_application_info.set_action('FRONTIER');
    end if;
    update doom_match set current_tic=p_tic,last_activity_at=l_now
      where match_id=p_match and match_state='ACTIVE' and generation=p_generation
        and membership_epoch=p_epoch and current_tic=p_tic-1;
    if sql%rowcount<>1 then raise_application_error(c_error,'step frontier fence');end if;
    select count(*) into l_next_count from doom_match_command
      where match_id=p_match and tic=p_tic+1 and membership_epoch=p_epoch
        and generation=p_generation and player_slot in(0,1);
    update doom_match_worker_control set
      request_status=case when l_next_count=2 then 'QUEUED' else 'IDLE' end,
      requested_tic=case when l_next_count=2 then p_tic+1 else null end,
      heartbeat=l_now,last_error=null,
      route_status_tic=case when l_route_diagnostics=1 then p_tic else route_status_tic end,
      route_status=case when l_route_diagnostics=1 then l_route_status else route_status end
      where match_id=p_match
        and generation=p_generation and membership_epoch=p_epoch
        and request_status='PROCESSING' and requested_tic=p_tic;
    if sql%rowcount<>1 then raise_application_error(c_error,'step control fence');end if;
    if l_route_diagnostics=1 then
      l_frontier_done:=utc_now;
      l_route_status:=l_route_status||'|sqlToJavaMicros='||
        elapsed_micros(l_sql_started,l_java_started)||'|frameRowsMicros='||
        elapsed_micros(l_frame_rows_started,l_java_started)||'|javaMicros='||
        elapsed_micros(l_java_started,l_java_done)||'|frameFinalizeMicros='||
        elapsed_micros(l_java_done,l_frame_finalized)||'|ledgerMicros='||
        elapsed_micros(l_frame_finalized,l_ledger_done)||'|retirementMicros='||
        elapsed_micros(l_retirement_started,l_retirement_done)||'|frontierMicros='||
        elapsed_micros(l_retirement_done,l_frontier_done)||'|sqlAfterJavaMicros='||
        elapsed_micros(l_java_done,l_frontier_done);
      insert into doom_match_route_trace(match_id,tic,route_status)
        values(p_match,p_tic,l_route_status);
      l_commit_started:=utc_now;dbms_application_info.set_action('COMMIT');
    end if;
    commit;
    if l_route_diagnostics=1 then
      l_commit_done:=utc_now;l_commit_micros:=elapsed_micros(l_commit_started,l_commit_done);
      update doom_match_route_trace set route_status=route_status||'|commitMicros='||
        l_commit_micros
        where match_id=p_match and tic=p_tic;
      commit;dbms_application_info.set_action(null);
    end if;
  end;

  $end

  procedure fill_deadline(
    p_match varchar2,p_generation number,p_epoch number
  ) is
    l_tic number;l_count number;l_slot number;l_seq number;l_sha varchar2(64);
    l_first timestamp with time zone;l_eligible timestamp with time zone;
    l_now timestamp with time zone:=utc_now;
    l_neutral raw(8):=hextoraw('0000000000000000');
    l_member_state varchar2(16);l_leave_tic number;l_source varchar2(16);
  begin
    select current_tic+1 into l_tic from doom_match where match_id=p_match
      and match_state='ACTIVE' and generation=p_generation
      and membership_epoch=p_epoch;
    select count(*),min(submitted_at) into l_count,l_first
      from doom_match_command where match_id=p_match and tic=l_tic
      and generation=p_generation and membership_epoch=p_epoch;
    if l_count<>1 then return;end if;
    select committed_at into l_eligible from doom_match_tic
      where match_id=p_match and tic=l_tic-1;
    select case when min(player_slot)=0 then 1 else 0 end into l_slot
      from doom_match_command where match_id=p_match and tic=l_tic
      and generation=p_generation and membership_epoch=p_epoch;
    select member_state,leave_tic into l_member_state,l_leave_tic
      from doom_match_member where match_id=p_match and player_slot=l_slot
      and generation=p_generation and membership_epoch=p_epoch;
    if l_member_state='LEFT' and l_leave_tic<=l_tic then
      l_source:='NEUTRAL_LEFT';
    elsif greatest(l_first,l_eligible)+numtodsinterval(case when l_tic=1
      then c_initial_command_deadline_ms else c_command_deadline_ms end/1000,
      'SECOND')<=l_now then
      l_source:='NEUTRAL_DEADLINE';
    else return;end if;
    -- Serialize with submit_command, then repeat every predicate under lock.
    select current_tic+1 into l_tic from doom_match where match_id=p_match
      and match_state='ACTIVE' and generation=p_generation
      and membership_epoch=p_epoch for update;
    select count(*),min(submitted_at) into l_count,l_first
      from doom_match_command where match_id=p_match and tic=l_tic
      and generation=p_generation and membership_epoch=p_epoch;
    if l_count<>1 then rollback;return;end if;
    select committed_at into l_eligible from doom_match_tic
      where match_id=p_match and tic=l_tic-1;
    select case when min(player_slot)=0 then 1 else 0 end into l_slot
      from doom_match_command where match_id=p_match and tic=l_tic
      and generation=p_generation and membership_epoch=p_epoch;
    select member_state,leave_tic into l_member_state,l_leave_tic
      from doom_match_member where match_id=p_match and player_slot=l_slot
      and generation=p_generation and membership_epoch=p_epoch;
    if l_member_state='LEFT' and l_leave_tic<=l_tic then
      l_source:='NEUTRAL_LEFT';
    elsif greatest(l_first,l_eligible)+numtodsinterval(case when l_tic=1
      then c_initial_command_deadline_ms else c_command_deadline_ms end/1000,
      'SECOND')<=l_now then
      l_source:='NEUTRAL_DEADLINE';
    else rollback;return;end if;
    select coalesce(max(command_seq),0)+1 into l_seq from doom_match_command
      where match_id=p_match and player_slot=l_slot;
    l_sha:=sha_raw(l_neutral);
    insert into doom_match_command(match_id,tic,player_slot,command_seq,
      membership_epoch,generation,command_source,ticcmd_raw,command_sha,
      submitted_at,accepted_at)
    values(p_match,l_tic,l_slot,l_seq,p_epoch,p_generation,
      l_source,l_neutral,l_sha,l_now,l_now);
    update doom_match_worker_control set request_status='QUEUED',
      requested_tic=l_tic,heartbeat=l_now where match_id=p_match
      and generation=p_generation and membership_epoch=p_epoch
      and worker_status='READY' and request_status='IDLE';
    if sql%rowcount<>1 then
      raise_application_error(c_error,'deadline worker is not ready');
    end if;
    commit;
  exception when no_data_found then rollback;
  end;

  procedure mark_disconnected(
    p_match varchar2,p_generation number,p_epoch number
  ) is
    l_now timestamp with time zone:=utc_now;
  begin
    update doom_match_member member_ set member_state='LEFT',
      leave_tic=(select current_tic+1 from doom_match
        where match_id=p_match and generation=p_generation
          and membership_epoch=p_epoch),last_seen_at=l_now
      where match_id=p_match and generation=p_generation
      and membership_epoch=p_epoch and member_state='DISCONNECTED'
      -- A generated-ORDS restart republishes the allowlist before serving and
      -- can exceed two minutes on the pinned local stack. Keep the slot
      -- recoverable across that bounded transport outage; explicit leave and
      -- match expiry remain immediate bounded cleanup paths.
      and disconnected_at<l_now-interval '180' second;
    update doom_match_member set member_state='DISCONNECTED',
      disconnected_at=l_now where match_id=p_match and generation=p_generation
      and membership_epoch=p_epoch and member_state='ACTIVE'
      and last_seen_at<l_now-interval '3' second;
    commit;
  end;

  -- PACED_INPUT linearizes at the match-row lock. Input committed before this
  -- lock is sampled for this exact tic; input accepted afterwards is assigned
  -- to a later frontier. The materialized command rows are the applied replay
  -- vector, so process_step must not perform the lockstep overlay again.
  procedure materialize_paced_vector(
    p_match varchar2,p_generation number,p_epoch number,p_tic out number
  ) is
    l_now timestamp with time zone:=utc_now;
    l_raw raw(8);l_neutral raw(8):=hextoraw('0000000000000000');
    l_source varchar2(24);l_state varchar2(16);l_leave number;
    l_seen timestamp with time zone;l_sha varchar2(64);l_count number;
  begin
    select current_tic+1 into p_tic from doom_match where match_id=p_match
      and match_state='ACTIVE' and generation=p_generation
      and membership_epoch=p_epoch for update;
    select count(*) into l_count from doom_match_command where match_id=p_match
      and tic=p_tic and generation=p_generation and membership_epoch=p_epoch;
    if l_count not in(0,2) then
      raise_application_error(c_error,'partial paced vector');end if;
    if l_count=0 then for l_slot in 0..1 loop
      select member_state,leave_tic,last_seen_at
        into l_state,l_leave,l_seen from doom_match_member
        where match_id=p_match and player_slot=l_slot
          and generation=p_generation and membership_epoch=p_epoch for update;
      if l_state='LEFT' and l_leave<=p_tic then
        l_raw:=l_neutral;l_source:='NEUTRAL_LEFT';
      elsif l_state='DISCONNECTED' or l_seen<l_now-interval '3' second then
        if l_state='ACTIVE' then
          update doom_match_member set member_state='DISCONNECTED',
            disconnected_at=l_now where match_id=p_match and player_slot=l_slot;
        end if;
        l_raw:=l_neutral;l_source:='NEUTRAL_DISCONNECTED';
      else
        begin
          select ticcmd_raw into l_raw from (
            select ticcmd_raw from doom_match_input_event
              where match_id=p_match and player_slot=l_slot
                and membership_epoch=p_epoch and effective_tic<=p_tic
              order by effective_tic desc,input_seq desc
          ) where rownum=1;
          l_source:='SAMPLED_INPUT';
        exception when no_data_found then
          l_raw:=l_neutral;l_source:='NEUTRAL_INITIAL';
        end;
      end if;
      l_sha:=sha_raw(l_raw);
      insert into doom_match_command(match_id,tic,player_slot,command_seq,
        membership_epoch,generation,command_source,ticcmd_raw,command_sha,
        submitted_at,accepted_at)
      values(p_match,p_tic,l_slot,p_tic,p_epoch,p_generation,l_source,l_raw,
        l_sha,l_now,l_now);
    end loop;end if;
    update doom_match_worker_control set request_status='PROCESSING',
      requested_tic=p_tic,heartbeat=l_now where match_id=p_match
      and generation=p_generation and membership_epoch=p_epoch
      and worker_status='READY' and request_status='IDLE';
    if sql%rowcount<>1 then
      raise_application_error(c_error,'paced worker is not ready');
    end if;
    -- The prepared vector is private and generation-fenced. Releasing the
    -- linearization lock before MLE work prevents authenticated input writers
    -- from convoying behind the authoritative transition transaction.
    commit;
  end;

  procedure run_match_core(p_match in varchar2,p_warm boolean);

  procedure arm_standby(p_match varchar2,p_generation number) is
    l_job varchar2(64):='DOOM_MS_'||upper(p_match)||'_G'||to_char(p_generation);
    l_count number;l_error varchar2(2000);l_pool number:=0;
  begin
    select count(*) into l_count from doom_match_standby_control
      where match_id=p_match and standby_status in('STARTING','READY','PROMOTING');
    if l_count<>0 then return;end if;
    doom_worker_lifecycle.claim_ready_slot(
      p_match,'STANDBY',l_pool,l_job);
    delete from doom_match_standby_control where match_id=p_match;
    insert into doom_match_standby_control(match_id,base_generation,job_name,
      standby_status,heartbeat,last_error)
    values(p_match,p_generation,l_job,
      case when l_pool=0 then 'FAILED' else 'STARTING' end,
      (localtimestamp at time zone 'UTC'),
      case when l_pool=0 then 'warm recovery slot unavailable' end);
    commit;
    return;
  exception when others then
    l_error:=sqlerrm;
    rollback;
    begin
      update doom_match_standby_control set standby_status='FAILED',
        heartbeat=(localtimestamp at time zone 'UTC'),last_error=substr(l_error,1,2000)
        where match_id=p_match and base_generation=p_generation;
      commit;
    exception when others then rollback;end;
  end;

  procedure run_standby_core(p_match in varchar2,p_warm boolean) is
    l_players number;l_deathmatch number;l_skill number;l_episode number;l_map number;
    l_generation number;l_promote number;l_stop number;l_state varchar2(64);
    l_expected varchar2(64);l_status varchar2(16);l_polls number:=0;
  begin
    select m.max_players,case m.game_mode when 'DEATHMATCH' then 1 else 0 end,
      m.skill,m.episode,m.map,s.base_generation
      into l_players,l_deathmatch,l_skill,l_episode,l_map,l_generation
      from doom_match m join doom_match_standby_control s on s.match_id=m.match_id
      where m.match_id=p_match and m.match_state='ACTIVE'
        and m.generation=s.base_generation and s.standby_status='STARTING';
    if p_warm then
      doom_mle_match_runtime.prepare_origin_warm(
        l_players,l_deathmatch,l_skill,l_episode,l_map,l_state);
    else
      doom_mle_match_runtime.initialize_game(
        l_players,l_deathmatch,l_skill,l_episode,l_map,l_state);
    end if;
    select state_sha into l_expected from doom_match_tic
      where match_id=p_match and tic=0;
    if l_state<>l_expected then
      raise_application_error(c_error,'standby origin state mismatch');end if;
    dbms_application_info.set_action('MLE_STANDBY_PASSIVE');
    update doom_match_standby_control set standby_status='READY',
      worker_sid=sys_context('USERENV','SID'),
      heartbeat=(localtimestamp at time zone 'UTC'),last_error=null
      where match_id=p_match and base_generation=l_generation
        and standby_status='STARTING';
    if sql%rowcount<>1 then raise_application_error(c_error,'standby ready fence');end if;
    commit;
    loop
      select standby_status,promote_generation,stop_requested
        into l_status,l_promote,l_stop from doom_match_standby_control
        where match_id=p_match and base_generation=l_generation;
      exit when l_stop=1;
      if l_status='PROMOTING' and l_promote=l_generation+1 then
        g_warm_promotion:=true;
        delete from doom_match_standby_control where match_id=p_match
          and base_generation=l_generation and standby_status='PROMOTING'
          and promote_generation=l_promote;
        if sql%rowcount<>1 then
          raise_application_error(c_error,'standby promotion fence');end if;
        commit;
        run_match_core(p_match,p_warm);
        return;
      end if;
      -- A READY standby owns a retained origin/checkpoint-capable context but
      -- performs no checkpoint restore or simulation work until promotion.
      -- Poll coarsely so Free's second runnable-session slot and effective CPU
      -- remain available to the authority during ordinary play.
      dbms_session.sleep(c_standby_poll_seconds);
      l_polls:=l_polls+1;
      update doom_match_standby_control set
        heartbeat=(localtimestamp at time zone 'UTC')
        where match_id=p_match and base_generation=l_generation
          and standby_status='READY';
      if mod(l_polls,5)=0 then commit;end if;
    end loop;
    if not p_warm then doom_mle_match_runtime.release;end if;
    update doom_match_standby_control set standby_status='STOPPED',
      worker_sid=null,heartbeat=(localtimestamp at time zone 'UTC')
      where match_id=p_match;
    commit;
  exception when others then
    declare l_message varchar2(2000):=sqlerrm;
    begin
      if not p_warm then
        begin doom_mle_match_runtime.release;exception when others then null;end;
      end if;
      update doom_match_standby_control set standby_status='FAILED',
        worker_sid=null,heartbeat=(localtimestamp at time zone 'UTC'),
        last_error=l_message
        where match_id=p_match;
      commit;
    exception when others then rollback;end;
  end;

  procedure run_match_core(p_match in varchar2,p_warm boolean) is
    l_generation number;l_epoch number;l_status varchar2(16);l_request varchar2(16);
    l_tic number;l_stop number;l_idle number:=0;
    l_match_state varchar2(16);l_worker_mode varchar2(16);
    l_route_diagnostics number;
    l_checkpoint_test_hook number;
    l_cpu_sample_cs number;
    l_cpu_sample_at timestamp with time zone;
    -- Pace from Oracle's monotonic hundredths clock. SYSTIMESTAMP is a ledger
    -- timestamp, not a cadence source: host/NTP backward corrections otherwise
    -- turn into a spurious positive sleep and freeze every retained match.
    l_boundary_ticks number;l_now_ticks number;l_delay_ticks number;
    procedure sample_authority_cpu(p_tic number) is
      l_now timestamp with time zone;
      l_now_cs number;
      l_wall_ms number;
      l_cpu_percent number;
    begin
      if mod(p_tic,35)<>0 then return;end if;
      l_now:=utc_now;
      l_now_cs:=dbms_utility.get_cpu_time;
      l_wall_ms:=elapsed_micros(l_cpu_sample_at,l_now)/1000;
      if l_wall_ms<=0 then return;end if;
      l_cpu_percent:=least(100,
        greatest(0,(l_now_cs-l_cpu_sample_cs)*10/l_wall_ms*100));
      update doom_match_worker_control set
        worker_cpu_cs=l_now_cs,cpu_sample_tic=p_tic,cpu_sample_at=l_now,
        cpu_window_ms=l_wall_ms,cpu_percent=round(l_cpu_percent,3)
        where match_id=p_match and generation=l_generation
          and membership_epoch=l_epoch and worker_status='READY';
      commit;
      l_cpu_sample_cs:=l_now_cs;
      l_cpu_sample_at:=l_now;
    end;
  begin
    select generation,membership_epoch,worker_mode,route_diagnostics,
      checkpoint_test_hook
      into l_generation,l_epoch,l_worker_mode,l_route_diagnostics,
        l_checkpoint_test_hook
      from doom_match_worker_control where match_id=p_match;
    select match_state into l_match_state from doom_match where match_id=p_match;
    if l_match_state='LOBBY' then
      publish_initial(p_match,l_generation,p_warm);
      arm_standby(p_match,l_generation);
      -- Tic zero is durable before admission. The generation-matched standby
      -- is armed immediately but warms in the background: Free's single
      -- effective PDB CPU must not put a second ~100 second cold start on the
      -- user-facing path for either solo or multiplayer.
      update doom_match_worker_control set worker_status='READY',
        heartbeat=(localtimestamp at time zone 'UTC'),last_error=null
        where match_id=p_match and generation=l_generation
          and worker_status='STARTING';
      if sql%rowcount<>1 then
        raise_application_error(c_error,'authority admission fence');
      end if;
      commit;
    elsif l_match_state='ACTIVE' then
      reconstruct_existing(p_match,l_generation,
        case when p_warm or g_warm_promotion then 1 else 0 end);
      g_warm_promotion:=false;
      arm_standby(p_match,l_generation);
    else raise_application_error(c_error,'match is not recoverable');end if;
    l_boundary_ticks:=dbms_utility.get_time;
    l_cpu_sample_cs:=dbms_utility.get_cpu_time;
    l_cpu_sample_at:=utc_now;
    loop
      select worker_status,request_status,requested_tic,stop_requested,
        route_diagnostics,checkpoint_test_hook
        into l_status,l_request,l_tic,l_stop,l_route_diagnostics,
          l_checkpoint_test_hook
        from doom_match_worker_control
        where match_id=p_match and generation=l_generation;
      exit when l_stop=1 or l_status<>'READY';
      if l_worker_mode='PACED_INPUT' and l_request='IDLE' then
        l_boundary_ticks:=l_boundary_ticks+100/35;
        l_now_ticks:=dbms_utility.get_time;
        l_delay_ticks:=l_boundary_ticks-l_now_ticks;
        if l_delay_ticks>0 then dbms_session.sleep(l_delay_ticks/100);
        elsif l_delay_ticks < -200/35 then
          l_boundary_ticks:=l_now_ticks;
        end if;
        materialize_paced_vector(p_match,l_generation,l_epoch,l_tic);
        process_step(p_match,l_generation,l_epoch,l_tic,1,l_route_diagnostics,
          l_checkpoint_test_hook);
        sample_authority_cpu(l_tic);
        l_idle:=l_idle+1;
        if mod(l_idle,35)=0 then
          mark_disconnected(p_match,l_generation,l_epoch);
          -- A rapid prior match can leave the second pool slot recycling for
          -- a fraction of a second. Heal that explicitly reported degraded
          -- window as soon as a warm slot is available.
          arm_standby(p_match,l_generation);
        end if;
      elsif l_request='QUEUED' then
        update doom_match_worker_control set request_status='PROCESSING',
          heartbeat=(localtimestamp at time zone 'UTC')
          where match_id=p_match and generation=l_generation
          and membership_epoch=l_epoch and request_status='QUEUED'
          and requested_tic=l_tic;
        if sql%rowcount=1 then commit;process_step(
          p_match,l_generation,l_epoch,l_tic,0,l_route_diagnostics,
          l_checkpoint_test_hook);
          sample_authority_cpu(l_tic);
        else rollback;end if;
        l_idle:=0;
      else
        fill_deadline(p_match,l_generation,l_epoch);
        dbms_session.sleep(.01);l_idle:=l_idle+1;
        if mod(l_idle,100)=0 then
          mark_disconnected(p_match,l_generation,l_epoch);
          update doom_match_worker_control set
            heartbeat=(localtimestamp at time zone 'UTC')
            where match_id=p_match and generation=l_generation;
          commit;
        end if;
      end if;
    end loop;
    if not p_warm then doom_mle_match_runtime.release;end if;
    update doom_match_worker_control set worker_status='STOPPED',
      heartbeat=(localtimestamp at time zone 'UTC')
      where match_id=p_match and generation=l_generation;
    commit;
  exception when others then
    declare l_error varchar2(2000):=sqlerrm;
    begin
      if not p_warm then
        begin doom_mle_match_runtime.release;exception when others then null;end;
      end if;
      fail_control(p_match,l_error);
    end;
  end;

  procedure run_match(p_match in varchar2) is
  begin
    run_match_core(p_match,false);
  end;

  procedure run_standby(p_match in varchar2) is
  begin
    run_standby_core(p_match,false);
  end;

  procedure run_warm_slot(p_slot in number,p_incarnation in varchar2) is
    l_status varchar2(16);l_match varchar2(32);l_role varchar2(16);
    l_stop number;l_state varchar2(64);l_polls number:=0;
    l_runtime_status varchar2(32767);
    l_sid number;l_serial number;l_assignment number:=0;
    l_spid varchar2(24);l_job_run varchar2(64);
    l_warm_checkpoint blob;l_warm_checkpoint_sha varchar2(64);
    l_warm_checkpoint_bytes number;
  begin
    if p_slot not in(1,2) or
       not regexp_like(p_incarnation,'^[0-9a-f]{32}$') then
      raise_application_error(c_error,'invalid warm slot incarnation');
    end if;
    l_sid:=to_number(sys_context('USERENV','SID'));
    select s.serial#,p.spid into l_serial,l_spid
      from v$session s join v$process p on p.addr=s.paddr
      where s.sid=l_sid
        and s.audsid=to_number(sys_context('USERENV','SESSIONID'));
    l_job_run:=p_incarnation||':'||
      nvl(sys_context('USERENV','FG_JOB_ID'),'0');
    update doom_mle_warm_launch set launch_status='RUNNING'
      where slot_id=p_slot and incarnation_token=p_incarnation
        and launch_status='REQUESTED';
    if sql%rowcount<>1 then
      raise_application_error(c_error,'stale warm launch incarnation');
    end if;
    update doom_mle_warm_slot set slot_status='WARMING',
      assigned_match=null,assigned_role=null,
      worker_sid=l_sid,worker_serial=l_serial,worker_spid=l_spid,
      worker_job_run=l_job_run,incarnation_token=p_incarnation,
      heartbeat=(localtimestamp at time zone 'UTC'),
      state_sha256=null,last_error=null,stop_requested=0
      where slot_id=p_slot and slot_status in('STOPPED','FAILED')
        and assigned_match is null;
    if sql%rowcount<>1 then raise_application_error(c_error,'warm slot missing');end if;
    commit;
    doom_mle_match_runtime.initialize_game(2,0,3,1,1,l_state);
    -- Prepay checkpoint serializer first-touch before advertising READY. The
    -- payload is deliberately discarded; assignment restores a banked origin.
    dbms_application_info.set_action('MLE_WARM_CHECKPOINT');
    doom_mle_match_runtime.save_checkpoint(
      l_warm_checkpoint,l_warm_checkpoint_sha,l_warm_checkpoint_bytes);
    if dbms_lob.istemporary(l_warm_checkpoint)=1 then
      dbms_lob.freetemporary(l_warm_checkpoint);
    end if;
    dbms_application_info.set_action('MLE_WARM_READY');
    update doom_mle_warm_slot set slot_status='READY',
      heartbeat=(localtimestamp at time zone 'UTC'),
      state_sha256=l_state where slot_id=p_slot and slot_status='WARMING'
        and incarnation_token=p_incarnation and worker_sid=l_sid
        and worker_serial=l_serial and worker_spid=l_spid
        and worker_job_run=l_job_run;
    if sql%rowcount<>1 then raise_application_error(c_error,'warm slot ready fence');end if;
    update doom_mle_warm_launch set launch_status='READY'
      where slot_id=p_slot and incarnation_token=p_incarnation
        and launch_status='RUNNING';
    commit;
    loop
      l_stop:=doom_worker_lifecycle.pending_stop(
        p_slot,p_incarnation,l_sid,l_serial,l_spid,l_job_run);
      exit when l_stop<>0;
      doom_worker_lifecycle.accept_assignment(
        p_slot,p_incarnation,l_sid,l_serial,l_spid,l_job_run,
        l_assignment,l_match,l_role);
      if l_assignment<>0 then
        update doom_mle_warm_slot set slot_status='RUNNING',
          assigned_match=l_match,assigned_role=l_role,
          heartbeat=(localtimestamp at time zone 'UTC'),last_error=null
          where slot_id=p_slot and slot_status='READY'
            and incarnation_token=p_incarnation and worker_sid=l_sid
            and worker_serial=l_serial and worker_spid=l_spid
            and worker_job_run=l_job_run;
        if sql%rowcount<>1 then
          raise_application_error(c_error,'warm slot assignment fence');
        end if;
        commit;
        if l_role='AUTHORITY' then
          run_match_core(l_match,true);
        elsif l_role='STANDBY' then
          run_standby_core(l_match,true);
        else
          raise_application_error(c_error,'warm slot role');
        end if;
        -- READY is a state invariant, not just a row label. Return the retained
        -- context to the default tic-zero origin before exposing it again. An
        -- assignment-level restore failure may have released the context, in
        -- which case rebuild it rather than publishing a false READY slot.
        l_runtime_status:=doom_teavm_sim_state;
        if l_runtime_status='state=uninitialized' then
          doom_mle_match_runtime.initialize_game(2,0,3,1,1,l_state);
        else
          doom_mle_match_runtime.prepare_origin_warm(2,0,3,1,1,l_state);
        end if;
        update doom_mle_warm_slot set slot_status='READY',
          assigned_match=null,assigned_role=null,
          heartbeat=(localtimestamp at time zone 'UTC'),
          state_sha256=l_state,last_error=null where slot_id=p_slot
            and slot_status='RUNNING' and assigned_match=l_match
            and assigned_role=l_role and incarnation_token=p_incarnation
            and worker_sid=l_sid and worker_serial=l_serial
            and worker_spid=l_spid and worker_job_run=l_job_run;
        if sql%rowcount<>1 then
          raise_application_error(c_error,'warm slot recycle fence');
        end if;
        doom_worker_lifecycle.finish_assignment(l_assignment,'FINISHED');
        commit;l_polls:=0;l_assignment:=0;
      else
        dbms_session.sleep(.2);l_polls:=l_polls+1;
        if mod(l_polls,5)=0 then
          update doom_mle_warm_slot set
            heartbeat=(localtimestamp at time zone 'UTC')
            where slot_id=p_slot and slot_status='READY'
              and incarnation_token=p_incarnation and worker_sid=l_sid
              and worker_serial=l_serial and worker_spid=l_spid
              and worker_job_run=l_job_run;
          commit;
        end if;
      end if;
    end loop;
    doom_mle_match_runtime.release;
    update doom_mle_warm_slot set slot_status='STOPPED',worker_sid=null,
      assigned_match=null,assigned_role=null,
      worker_serial=null,worker_spid=null,worker_job_run=null,
      incarnation_token=null,heartbeat=(localtimestamp at time zone 'UTC')
      where slot_id=p_slot and incarnation_token=p_incarnation
        and worker_sid=l_sid and worker_serial=l_serial
        and worker_spid=l_spid and worker_job_run=l_job_run;
    update doom_mle_warm_launch set launch_status='STOPPED'
      where slot_id=p_slot and incarnation_token=p_incarnation;
    doom_worker_lifecycle.honor_stop(l_stop,'run_warm_slot released context');
    commit;
  exception when others then
    declare l_error varchar2(2000):=sqlerrm;
    begin
      if dbms_lob.istemporary(l_warm_checkpoint)=1 then
        dbms_lob.freetemporary(l_warm_checkpoint);
      end if;
      begin doom_mle_match_runtime.release;exception when others then null;end;
      if l_assignment<>0 then
        begin doom_worker_lifecycle.finish_assignment(
          l_assignment,'FAILED',l_error);exception when others then null;end;
      end if;
      update doom_mle_warm_slot set slot_status='FAILED',worker_sid=null,
        worker_serial=null,worker_spid=null,worker_job_run=null,
        incarnation_token=null,assigned_match=null,assigned_role=null,
        heartbeat=(localtimestamp at time zone 'UTC'),
        last_error=l_error where slot_id=p_slot
          and incarnation_token=p_incarnation and worker_sid=l_sid
          and worker_serial=l_serial and worker_spid=l_spid
          and worker_job_run=l_job_run;
      update doom_mle_warm_launch set launch_status='FAILED'
        where slot_id=p_slot and incarnation_token=p_incarnation;
      commit;
    exception when others then rollback;end;
  end;

  procedure start_warm_pool is
    l_job varchar2(64);l_token varchar2(32);l_status varchar2(16);
    l_prewarm number;l_ready timestamp with time zone;
    l_current_token varchar2(32);l_sid number;l_serial number;
    l_spid varchar2(24);l_job_run varchar2(64);
  begin
    insert into doom_mle_prewarm_run(started_at,prewarm_status)
      values(localtimestamp at time zone 'UTC','STARTING')
      returning prewarm_id into l_prewarm;
    commit;
    -- Retire both prior incarnations before warming authority. Leaving an old
    -- standby alive during slot 1 initialization would consume half of Free's
    -- two-running-session envelope and defeat authority-first admission.
    for l_slot in 1..2 loop
      l_job:='DOOM_MLE_WARM_'||to_char(l_slot,'FM00');
      begin
        select incarnation_token,worker_sid,worker_serial,worker_spid,
          worker_job_run into l_current_token,l_sid,l_serial,l_spid,l_job_run
          from doom_mle_warm_slot where slot_id=l_slot;
        doom_worker_lifecycle.stop_job(
          l_job,true,'sequential deploy prewarm replacement',
          l_current_token,l_sid,l_serial,l_spid,l_job_run);
      exception when others then
        if sqlcode<>-27475 then raise;end if;
      end;
      begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    end loop;
    for l_slot in 1..2 loop
      l_job:='DOOM_MLE_WARM_'||to_char(l_slot,'FM00');
      doom_worker_lifecycle.prepare_launch(l_slot,l_job,l_token);
      dbms_scheduler.create_job(job_name=>l_job,job_type=>'STORED_PROCEDURE',
        job_action=>'DOOM_MATCH_WORKER.RUN_WARM_SLOT',
        number_of_arguments=>2,enabled=>false,auto_drop=>false);
      dbms_scheduler.set_job_argument_value(l_job,1,to_char(l_slot));
      dbms_scheduler.set_job_argument_value(l_job,2,l_token);
      dbms_scheduler.set_attribute(l_job,'restartable',true);
      dbms_scheduler.enable(l_job);
      l_status:=null;
      for poll_ in 1..3000 loop
        select launch_status into l_status from doom_mle_warm_launch
          where slot_id=l_slot and incarnation_token=l_token;
        exit when l_status in('READY','FAILED');
        dbms_session.sleep(.1);
      end loop;
      if l_status<>'READY' then
        raise_application_error(c_error,'sequential warm slot failed: '||l_slot);
      end if;
      l_ready:=utc_now;
      if l_slot=1 then
        update doom_mle_prewarm_run set authority_ready_at=l_ready,
          prewarm_status='AUTHORITY_READY' where prewarm_id=l_prewarm;
      else
        update doom_mle_prewarm_run set standby_ready_at=l_ready,
          completed_at=l_ready,prewarm_status='READY'
          where prewarm_id=l_prewarm;
      end if;
      commit;
    end loop;
  exception when others then
    declare l_error varchar2(2000):=sqlerrm;
    begin
      update doom_mle_prewarm_run set
        completed_at=(localtimestamp at time zone 'UTC'),
        prewarm_status='FAILED',failure_detail=l_error
        where prewarm_id=l_prewarm;
      commit;
    exception when others then rollback;end;
    raise;
  end;

  procedure recover_match(
    p_match in varchar2,p_wait_ms in number,p_match_state out varchar2
  ) is
    l_state varchar2(16);l_epoch number;l_generation number;l_new number;
    l_job varchar2(64);l_standby_job varchar2(64);l_wait number;l_warm number:=0;
    l_pool number:=0;
    l_error varchar2(2000);l_now timestamp with time zone:=utc_now;
  begin
    p_match_state:=null;l_wait:=least(greatest(coalesce(p_wait_ms,30000),0),180000);
    select m.match_state,m.membership_epoch,m.generation,c.job_name
      into l_state,l_epoch,l_generation,l_job from doom_match m
      join doom_match_worker_control c on c.match_id=m.match_id
      where m.match_id=p_match for update of m.generation;
    if l_state<>'ACTIVE' or l_generation<1 then
      raise_application_error(c_error,'match is not recoverable');
    end if;
    l_new:=l_generation+1;commit;
    begin doom_worker_lifecycle.stop_job(
      l_job,true,'match recovery replaces prior authority');
    exception when others then null;end;
    begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    begin
      -- RECOVERY_TIER_1: prefer the READY retained context already bound to
      -- this exact match generation.
      select s.job_name into l_standby_job from doom_match_standby_control s
        where s.match_id=p_match and s.base_generation=l_generation
          and s.standby_status='READY' and s.stop_requested=0
          and exists(select 1 from doom_match_checkpoint cp
            where cp.match_id=p_match and cp.tic<=
              (select current_tic from doom_match where match_id=p_match))
          and exists(
            select 1 from doom_mle_warm_slot ws join v$session vs
              on vs.sid=ws.worker_sid and vs.serial#=ws.worker_serial
              and vs.username=sys_context('USERENV','CURRENT_SCHEMA')
            where ws.job_name=s.job_name and ws.slot_status='RUNNING'
              and ws.assigned_match=p_match and ws.assigned_role='STANDBY');
      l_warm:=1;
    exception when no_data_found then l_warm:=0;end;
    if l_warm=1 then
      l_job:=l_standby_job;
    else
      -- RECOVERY_TIER_2: claim any live READY unbound retained context. Its
      -- assignment restores the nearest DMC1 checkpoint and replays the
      -- confirmed ledger; it is not a fresh initialization.
      doom_worker_lifecycle.claim_ready_slot(
        p_match,'AUTHORITY',l_pool,l_job);
      if l_pool<>0 then
        l_warm:=2;
      else
        -- RECOVERY_TIER_3: only a genuinely empty retained pool may fall back
        -- to the cold Scheduler path.
        l_warm:=0;l_job:='DOOM_MATCH_'||upper(p_match);
      end if;
    end if;
    update doom_match_worker_control set generation=l_new,
      membership_epoch=l_epoch,worker_status='STARTING',request_status='IDLE',
      requested_tic=null,worker_sid=null,heartbeat=l_now,last_error=null,
      stop_requested=0,job_name=l_job
      where match_id=p_match and generation=l_generation;
    if sql%rowcount<>1 then raise_application_error(c_error,'recovery claim fence');end if;
    if l_warm=1 then
      update doom_match_standby_control set standby_status='PROMOTING',
        promote_generation=l_new,heartbeat=l_now where match_id=p_match
        and base_generation=l_generation and standby_status='READY';
      if sql%rowcount<>1 then
        raise_application_error(c_error,'standby promotion claim fence');end if;
      commit;
    elsif l_warm=2 then
      -- The lifecycle assignment and generation/control-row claim commit
      -- atomically; RUN_WARM_SLOT owns the READY->RUNNING transition.
      commit;
    else
      commit;
      dbms_scheduler.create_job(job_name=>l_job,job_type=>'STORED_PROCEDURE',
        job_action=>'DOOM_MATCH_WORKER.RUN_MATCH',number_of_arguments=>1,
        enabled=>false,auto_drop=>false);
      dbms_scheduler.set_job_argument_value(l_job,1,p_match);
      dbms_scheduler.enable(l_job);
    end if;
    for poll_ in 1..ceil(l_wait/20) loop
      select worker_status,last_error into l_state,l_error
        from doom_match_worker_control where match_id=p_match and generation=l_new;
      if l_state='READY' then p_match_state:='ACTIVE';return;
      elsif l_state='FAILED' then
        raise_application_error(c_error,'match recovery failed: '||l_error);
      end if;
      dbms_session.sleep(.02);
    end loop;
    p_match_state:='STARTING';
  exception when no_data_found then
    rollback;raise_application_error(c_error,'match unavailable');
  end;

  procedure start_ready(
    p_match in varchar2,p_wait_ms in number,p_match_state out varchar2
  ) is
    l_state varchar2(16);l_epoch number;l_generation number;l_count number;
    l_job varchar2(64):='DOOM_MATCH_'||upper(p_match);l_wait number;
    l_dummy number;l_worker_error varchar2(2000);l_worker_mode varchar2(16);
    l_worker_status varchar2(16);l_match_limit number;l_pool number:=0;
    l_heartbeat timestamp with time zone;
  begin
    p_match_state:=null;l_wait:=least(greatest(coalesce(p_wait_ms,30000),0),60000);
    select number_value into l_dummy from doom_config
      where config_key='MAX_ACTIVE_SESSIONS' for update;
    select number_value into l_match_limit from doom_config
      where config_key='MAX_ACTIVE_MATCHES';
    if l_match_limit is null or l_match_limit<>trunc(l_match_limit) or
       l_match_limit not between 1 and 32 then
      raise_application_error(c_error,'invalid match capacity');
    end if;
    select match_state,membership_epoch,generation into l_state,l_epoch,l_generation
      from doom_match where match_id=p_match for update;
    if l_state='ACTIVE' and l_generation>0 then
      select worker_status,last_error into l_worker_status,l_worker_error
        from doom_match_worker_control
        where match_id=p_match and generation=l_generation;
      if l_worker_status='READY' then
        p_match_state:='ACTIVE';
      elsif l_worker_status='FAILED' then
        raise_application_error(c_error,'match worker failed: '||l_worker_error);
      else
        p_match_state:='STARTING';
      end if;
      commit;
      return;
    end if;
    if l_state<>'LOBBY' or l_generation<>0 then
      raise_application_error(c_error,'match is not startable');
    end if;
    begin
      select heartbeat,job_name into l_heartbeat,l_job from doom_match_worker_control
        where match_id=p_match and worker_status='STARTING';
      select count(*) into l_count from user_scheduler_jobs where job_name=l_job;
      if l_count=1 or
         l_heartbeat>(localtimestamp at time zone 'UTC')-interval '1' second then
        p_match_state:='STARTING';commit;return;
      end if;
      -- Scheduler job creation follows the durable claim. If dispatch loses
      -- that job entirely, a later authorized status poll reclaims the stale
      -- STARTING row instead of leaving the ready lobby permanently wedged.
      delete from doom_match_worker_control where match_id=p_match
        and worker_status='STARTING' and heartbeat=l_heartbeat;
    exception when no_data_found then null;end;
    select count(*) into l_count from doom_match_member where match_id=p_match
      and member_state='READY' and membership_epoch=l_epoch;
    if l_count<>2 then raise_application_error(c_error,'membership is not ready');end if;
    select count(*) into l_count from doom_match
      where match_id<>p_match and match_state in('LOBBY','ACTIVE')
        and expires_at>(localtimestamp at time zone 'UTC');
    if l_count>=l_match_limit then
      raise_application_error(-20702,'match worker capacity reached');
    end if;
    delete from doom_match_worker_control where match_id=p_match
      and worker_status in('FAILED','STOPPED');
    select text_value into l_worker_mode from doom_config
      where config_key='MATCH_WORKER_MODE';
    if l_worker_mode not in('LOCKSTEP','PACED_INPUT') then
      raise_application_error(c_error,'invalid match worker mode');end if;
    doom_worker_lifecycle.claim_ready_slot(
      p_match,'AUTHORITY',l_pool,l_job);
    if l_pool=0 then
      -- Keep the ready lobby retryable; never create a third cold context that
      -- would scheduler-thrash under Free's two-running-session ceiling.
      p_match_state:='STARTING';commit;return;
    end if;
    insert into doom_match_worker_control(match_id,generation,membership_epoch,
      job_name,worker_mode,worker_status,request_status,heartbeat)
    values(p_match,1,l_epoch,l_job,l_worker_mode,'STARTING','IDLE',
      (localtimestamp at time zone 'UTC'));
    commit;
    for poll_ in 1..ceil(l_wait/20) loop
      begin
        select worker_status,last_error into l_state,l_worker_error
          from doom_match_worker_control
          where match_id=p_match;
        if l_state='READY' then p_match_state:='ACTIVE';return;
        elsif l_state='FAILED' then
          raise_application_error(c_error,'match worker failed: '||l_worker_error);
        end if;
      exception when no_data_found then
        raise_application_error(c_error,'match worker disappeared');
      end;
      dbms_session.sleep(.02);
    end loop;
    p_match_state:='STARTING';
  exception when others then
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_error,'match worker start failed');
  end;

  procedure submit_command(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_tic in number,p_command_seq in number,
    p_ticcmd_raw in raw,p_accepted out number
  ) is
    l_current number;l_state varchar2(16);l_count number;l_existing raw(8);
    l_existing_seq number;l_seq_frontier number;
    l_worker_status varchar2(16);
    l_now timestamp with time zone:=utc_now;l_sha varchar2(64);
  begin
    p_accepted:=0;
    if p_player_slot not between 0 and 1 or p_ticcmd_raw is null or
       utl_raw.length(p_ticcmd_raw)<>8 or p_tic is null or p_command_seq is null then
      raise_application_error(c_error,'invalid match command');
    end if;
    select match_state,current_tic into l_state,l_current from doom_match
      where match_id=p_match and membership_epoch=p_membership_epoch
        and generation=p_generation for update;
    select worker_status into l_worker_status from doom_match_worker_control
      where match_id=p_match and membership_epoch=p_membership_epoch
        and generation=p_generation;
    if l_worker_status<>'READY' then
      raise_application_error(c_error,'worker is not ready');
    end if;
    begin
      select ticcmd_raw,command_seq into l_existing,l_existing_seq
        from doom_match_command
        where match_id=p_match and tic=p_tic and player_slot=p_player_slot;
      if l_existing<>p_ticcmd_raw or l_existing_seq<>p_command_seq then
        raise_application_error(c_error,'duplicate mismatch');
      end if;
      p_accepted:=1;commit;return;
    exception when no_data_found then null;end;
    if l_state<>'ACTIVE' or p_tic not between l_current+1
        and l_current+c_command_lead_tics then
      raise_application_error(c_error,'command frontier mismatch');
    end if;
    select count(*) into l_count from doom_match_member where match_id=p_match
      and player_slot=p_player_slot and membership_epoch=p_membership_epoch
      and generation=p_generation and member_state in('ACTIVE','DISCONNECTED');
    if l_count<>1 then raise_application_error(c_error,'inactive match member');end if;
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null where match_id=p_match and player_slot=p_player_slot
      and membership_epoch=p_membership_epoch and generation=p_generation;
    select coalesce(max(command_seq),0) into l_seq_frontier
      from doom_match_command
      where match_id=p_match and player_slot=p_player_slot;
    if p_command_seq<>l_seq_frontier+1 then
      raise_application_error(c_error,'command sequence mismatch');
    end if;
    l_sha:=sha_raw(p_ticcmd_raw);
    insert into doom_match_command(match_id,tic,player_slot,command_seq,
      membership_epoch,generation,command_source,ticcmd_raw,command_sha,
      submitted_at,accepted_at)
    values(p_match,p_tic,p_player_slot,p_command_seq,p_membership_epoch,
      p_generation,'SUBMITTED',p_ticcmd_raw,l_sha,l_now,l_now);
    select count(*) into l_count from doom_match_command where match_id=p_match
      and tic=p_tic and membership_epoch=p_membership_epoch
      and generation=p_generation and player_slot in(0,1);
    if l_count=2 and p_tic=l_current+1 then
      update doom_match_worker_control set request_status='QUEUED',
        requested_tic=p_tic,heartbeat=l_now where match_id=p_match
        and generation=p_generation and membership_epoch=p_membership_epoch
        and worker_status='READY' and request_status='IDLE';
      if sql%rowcount=0 then
        select count(*) into l_count from doom_match_worker_control
          where match_id=p_match and generation=p_generation
            and membership_epoch=p_membership_epoch and worker_status='READY'
            and request_status in('QUEUED','PROCESSING');
        if l_count<>1 then raise_application_error(c_error,'worker is not ready');end if;
      end if;
    end if;
    p_accepted:=1;commit;
  exception when no_data_found then rollback;raise_application_error(c_error,'match unavailable');
  end;

  procedure submit_command_batch(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_first_tic in number,p_first_command_seq in number,
    p_ticcmd_raw in raw,p_accepted out number,
    p_first_input_seq in number default null,p_input_raw in raw default null
  ) is
    l_current number;l_state varchar2(16);l_member_count number;
    l_worker_status varchar2(16);
    l_existing raw(8);l_existing_seq number;l_existing_count number:=0;
    l_seq_frontier number;l_vector_count number;l_tic number;l_seq number;
    l_batch_count number;l_input_count number;l_input_frontier number;
    l_input_existing raw(8);l_input_effective number;l_input raw(8);
    l_raw raw(8);l_sha varchar2(64);l_now timestamp with time zone:=utc_now;
  begin
    p_accepted:=0;
    l_batch_count:=case when p_ticcmd_raw is null then 0
      else utl_raw.length(p_ticcmd_raw)/8 end;
    if p_player_slot not between 0 and 1 or p_ticcmd_raw is null or
       l_batch_count not in(2,4) or p_first_tic is null or
       p_first_command_seq is null then
      raise_application_error(c_error,'invalid match command batch');
    end if;
    select match_state,current_tic into l_state,l_current from doom_match
      where match_id=p_match and membership_epoch=p_membership_epoch
        and generation=p_generation for update;
    select worker_status into l_worker_status from doom_match_worker_control
      where match_id=p_match and membership_epoch=p_membership_epoch
        and generation=p_generation;
    if l_worker_status<>'READY' then
      raise_application_error(c_error,'worker is not ready');
    end if;
    for i in 0..l_batch_count-1 loop
      l_tic:=p_first_tic+i;l_seq:=p_first_command_seq+i;
      l_raw:=utl_raw.substr(p_ticcmd_raw,i*8+1,8);
      begin
        select ticcmd_raw,command_seq into l_existing,l_existing_seq
          from doom_match_command where match_id=p_match and tic=l_tic
            and player_slot=p_player_slot;
        if l_existing<>l_raw or l_existing_seq<>l_seq then
          raise_application_error(c_error,'duplicate mismatch');
        end if;
        l_existing_count:=l_existing_count+1;
      exception when no_data_found then null;end;
    end loop;
    if l_state<>'ACTIVE' then raise_application_error(c_error,'command frontier mismatch');end if;
    select count(*) into l_member_count from doom_match_member
      where match_id=p_match and player_slot=p_player_slot
        and membership_epoch=p_membership_epoch and generation=p_generation
        and member_state in('ACTIVE','DISCONNECTED');
    if l_member_count<>1 then raise_application_error(c_error,'inactive match member');end if;
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null where match_id=p_match and player_slot=p_player_slot
      and membership_epoch=p_membership_epoch and generation=p_generation;
    l_input_count:=case when p_input_raw is null then 0
      else utl_raw.length(p_input_raw)/8 end;
    if (p_first_input_seq is null and p_input_raw is not null) or
       (p_first_input_seq is not null and
        (l_input_count not between 1 and 4 or p_first_input_seq<1)) then
      raise_application_error(c_error,'invalid fused input revisions');end if;
    if l_input_count>0 then
      select coalesce(max(input_seq),0) into l_input_frontier
        from doom_match_input_event where match_id=p_match
          and player_slot=p_player_slot;
      for i in 0..l_input_count-1 loop
        l_input:=utl_raw.substr(p_input_raw,i*8+1,8);
        begin
          select ticcmd_raw,effective_tic into l_input_existing,l_input_effective
            from doom_match_input_event where match_id=p_match
              and player_slot=p_player_slot and input_seq=p_first_input_seq+i;
          if l_input_existing<>l_input then
            raise_application_error(c_error,'input revision mismatch');end if;
        exception when no_data_found then
          if p_first_input_seq+i<>l_input_frontier+1 then
            raise_application_error(c_error,'input revision sequence');end if;
          insert into doom_match_input_event(match_id,player_slot,input_seq,
            effective_tic,membership_epoch,generation,ticcmd_raw,command_sha,accepted_at)
          values(p_match,p_player_slot,p_first_input_seq+i,l_current+1,
            p_membership_epoch,p_generation,l_input,
            lower(rawtohex(dbms_crypto.hash(l_input,dbms_crypto.hash_sh256))),l_now);
          l_input_frontier:=l_input_frontier+1;
        end;
      end loop;
    end if;
    select coalesce(max(command_seq),0) into l_seq_frontier
      from doom_match_command where match_id=p_match and player_slot=p_player_slot;
    for i in 0..l_batch_count-1 loop
      l_tic:=p_first_tic+i;l_seq:=p_first_command_seq+i;
      l_raw:=utl_raw.substr(p_ticcmd_raw,i*8+1,8);
      select count(*) into l_existing_count from doom_match_command
        where match_id=p_match and tic=l_tic and player_slot=p_player_slot;
      if l_existing_count=0 then
        if l_tic not between l_current+1 and l_current+c_command_lead_tics then
          raise_application_error(c_error,'command frontier mismatch');
        end if;
        if l_seq<>l_seq_frontier+1 then
          raise_application_error(c_error,'command sequence mismatch');
        end if;
        l_sha:=sha_raw(l_raw);
        insert into doom_match_command(match_id,tic,player_slot,command_seq,
          membership_epoch,generation,command_source,ticcmd_raw,command_sha,
          submitted_at,accepted_at)
        values(p_match,l_tic,p_player_slot,l_seq,p_membership_epoch,p_generation,
          'SUBMITTED',l_raw,l_sha,l_now,l_now);
        l_seq_frontier:=l_seq;
      end if;
    end loop;
    select count(*) into l_vector_count from doom_match_command
      where match_id=p_match and tic=l_current+1
        and membership_epoch=p_membership_epoch and generation=p_generation
        and player_slot in(0,1);
    if l_vector_count=2 then
      update doom_match_worker_control set request_status='QUEUED',
        requested_tic=l_current+1,heartbeat=l_now where match_id=p_match
        and generation=p_generation and membership_epoch=p_membership_epoch
        and worker_status='READY' and request_status='IDLE';
      if sql%rowcount=0 then
        select count(*) into l_vector_count from doom_match_worker_control
          where match_id=p_match and generation=p_generation
            and membership_epoch=p_membership_epoch and worker_status='READY'
            and request_status in('QUEUED','PROCESSING');
        if l_vector_count<>1 then raise_application_error(c_error,'worker is not ready');end if;
      end if;
    end if;
    p_accepted:=l_batch_count;commit;
  exception when no_data_found then rollback;raise_application_error(c_error,'match unavailable');
  end;

  procedure poll_frame(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_tic in number,p_ready out number,p_payload out blob
  ) is
    l_blob blob;l_count number;
  begin
    p_ready:=0;p_payload:=null;
    select count(*) into l_count from doom_match where match_id=p_match
      and membership_epoch=p_membership_epoch and generation=p_generation;
    if l_count<>1 then raise_application_error(c_error,'match unavailable');end if;
    begin
      select response_blob into l_blob from doom_match_frame where match_id=p_match
        and tic=p_tic and player_slot=p_player_slot
        and membership_epoch=p_membership_epoch and generation=p_generation;
      copy_blob(l_blob,p_payload);p_ready:=1;
    exception when no_data_found then null;end;
  end;

  procedure stop_match(p_match in varchar2,p_generation in number) is
  begin
    update doom_match_worker_control set stop_requested=1,
      heartbeat=(localtimestamp at time zone 'UTC')
      where match_id=p_match and generation=p_generation;
    update doom_match_standby_control set stop_requested=1,
      heartbeat=(localtimestamp at time zone 'UTC')
      where match_id=p_match and base_generation=p_generation
        and standby_status in('STARTING','READY');
    commit;
  end;
end doom_match_worker;
/
