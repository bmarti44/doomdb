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
end doom_match_worker;
/

create or replace package body doom_match_worker as
  c_error constant pls_integer:=-20731;
  c_command_deadline_ms constant pls_integer:=2000;
  c_initial_command_deadline_ms constant pls_integer:=500;
  c_frame_retention_tics constant pls_integer:=128;
  c_checkpoint_tics constant pls_integer:=1024;
  c_command_lead_tics constant pls_integer:=8;

  -- This bounded T13.2 slice advances complete two-player vectors and fills a
  -- missing peer with a durable neutral command after a fixed deadline.
  -- Cadence checkpoints are durable; restart reconstruction remains deferred.

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
  begin
    rollback;
    update doom_match_worker_control set worker_status='FAILED',
      request_status='FAILED',heartbeat=(localtimestamp at time zone 'UTC'),
      last_error=substr(p_error,1,2000)
      where match_id=p_match;
    commit;
  end;

  procedure publish_initial(p_match varchar2,p_generation number) is
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

  procedure reconstruct_existing(p_match varchar2,p_generation number) is
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

  procedure process_step(
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
    if p_tic=32 or mod(p_tic,c_checkpoint_tics)=0 then
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
        and tic<p_tic-c_checkpoint_tics;
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
    -- linearization lock before OJVM/render work prevents authenticated input
    -- writers from convoying behind the full frame transaction. Public frame
    -- visibility still begins only with process_step's authoritative commit.
    commit;
  end;

  procedure run_match(p_match in varchar2) is
    l_generation number;l_epoch number;l_status varchar2(16);l_request varchar2(16);
    l_tic number;l_stop number;l_idle number:=0;l_dispose varchar2(4000);
    l_match_state varchar2(16);l_worker_mode varchar2(16);
    -- Pace from Oracle's monotonic hundredths clock. SYSTIMESTAMP is a ledger
    -- timestamp, not a cadence source: host/NTP backward corrections otherwise
    -- turn into a spurious positive sleep and freeze every retained match.
    l_boundary_ticks number;l_now_ticks number;l_delay_ticks number;
  begin
    select generation,membership_epoch,worker_mode
      into l_generation,l_epoch,l_worker_mode
      from doom_match_worker_control where match_id=p_match;
    select match_state into l_match_state from doom_match where match_id=p_match;
    if l_match_state='LOBBY' then publish_initial(p_match,l_generation);
    elsif l_match_state='ACTIVE' then reconstruct_existing(p_match,l_generation);
    else raise_application_error(c_error,'match is not recoverable');end if;
    l_dispose:=doom_mocha_multiplayer_keyframes(
      case l_worker_mode when 'PACED_INPUT' then 32 else 4 end);
    if substr(l_dispose,1,3)<>'ok|' then
      raise_application_error(c_error,substr(l_dispose,1,1800));
    end if;
    l_boundary_ticks:=dbms_utility.get_time;
    loop
      select worker_status,request_status,requested_tic,stop_requested
        into l_status,l_request,l_tic,l_stop from doom_match_worker_control
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
        process_step(p_match,l_generation,l_epoch,l_tic,1);
        l_idle:=l_idle+1;
        if mod(l_idle,35)=0 then mark_disconnected(p_match,l_generation,l_epoch);end if;
      elsif l_request='QUEUED' then
        update doom_match_worker_control set request_status='PROCESSING',
          heartbeat=(localtimestamp at time zone 'UTC')
          where match_id=p_match and generation=l_generation
          and membership_epoch=l_epoch and request_status='QUEUED'
          and requested_tic=l_tic;
        if sql%rowcount=1 then commit;process_step(p_match,l_generation,l_epoch,l_tic,0);
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
    l_dispose:=doom_mocha_dispose;
    update doom_match_worker_control set worker_status='STOPPED',
      heartbeat=(localtimestamp at time zone 'UTC')
      where match_id=p_match and generation=l_generation;
    commit;
  exception when others then
    declare l_error varchar2(2000):=sqlerrm;l_ignored varchar2(4000);
    begin
      begin l_ignored:=doom_mocha_dispose;exception when others then null;end;
      fail_control(p_match,l_error);
    end;
  end;

  procedure recover_match(
    p_match in varchar2,p_wait_ms in number,p_match_state out varchar2
  ) is
    l_state varchar2(16);l_epoch number;l_generation number;l_new number;
    l_job varchar2(64):='DOOM_MATCH_'||upper(p_match);l_wait number;
    l_error varchar2(2000);l_now timestamp with time zone:=utc_now;
  begin
    p_match_state:=null;l_wait:=least(greatest(coalesce(p_wait_ms,30000),0),180000);
    select match_state,membership_epoch,generation
      into l_state,l_epoch,l_generation from doom_match
      where match_id=p_match for update;
    if l_state<>'ACTIVE' or l_generation<1 then
      raise_application_error(c_error,'match is not recoverable');
    end if;
    l_new:=l_generation+1;commit;
    begin dbms_scheduler.stop_job(l_job,true);exception when others then null;end;
    begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    update doom_match_worker_control set generation=l_new,
      membership_epoch=l_epoch,worker_status='STARTING',request_status='IDLE',
      requested_tic=null,worker_sid=null,heartbeat=l_now,last_error=null,
      stop_requested=0 where match_id=p_match and generation=l_generation;
    if sql%rowcount<>1 then raise_application_error(c_error,'recovery claim fence');end if;
    commit;
    dbms_scheduler.create_job(job_name=>l_job,job_type=>'STORED_PROCEDURE',
      job_action=>'DOOM_MATCH_WORKER.RUN_MATCH',number_of_arguments=>1,
      enabled=>false,auto_drop=>false);
    dbms_scheduler.set_job_argument_value(l_job,1,p_match);
    dbms_scheduler.enable(l_job);
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
    l_heartbeat timestamp with time zone;
  begin
    p_match_state:=null;l_wait:=least(greatest(coalesce(p_wait_ms,30000),0),60000);
    select number_value into l_dummy from doom_config
      where config_key='MAX_ACTIVE_SESSIONS' for update;
    select match_state,membership_epoch,generation into l_state,l_epoch,l_generation
      from doom_match where match_id=p_match for update;
    if l_state='ACTIVE' and l_generation>0 then p_match_state:='ACTIVE';commit;return;end if;
    if l_state<>'LOBBY' or l_generation<>0 then
      raise_application_error(c_error,'match is not startable');
    end if;
    begin
      select heartbeat into l_heartbeat from doom_match_worker_control
        where match_id=p_match and worker_status='STARTING';
      select count(*) into l_count from user_scheduler_jobs where job_name=l_job;
      if l_count=1 or l_heartbeat>utc_now-interval '1' second then
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
    select count(*) into l_count from doom_match_worker_control
      where worker_status in('STARTING','READY');
    if l_count>=4 then raise_application_error(-20702,'match worker capacity reached');end if;
    delete from doom_match_worker_control where match_id=p_match
      and worker_status in('FAILED','STOPPED');
    select text_value into l_worker_mode from doom_config
      where config_key='MATCH_WORKER_MODE';
    if l_worker_mode not in('LOCKSTEP','PACED_INPUT') then
      raise_application_error(c_error,'invalid match worker mode');end if;
    begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    insert into doom_match_worker_control(match_id,generation,membership_epoch,
      job_name,worker_mode,worker_status,request_status,heartbeat)
    values(p_match,1,l_epoch,l_job,l_worker_mode,'STARTING','IDLE',
      (localtimestamp at time zone 'UTC'));
    commit;
    dbms_scheduler.create_job(job_name=>l_job,job_type=>'STORED_PROCEDURE',
      job_action=>'DOOM_MATCH_WORKER.RUN_MATCH',number_of_arguments=>1,
      enabled=>false,auto_drop=>false);
    dbms_scheduler.set_job_argument_value(l_job,1,p_match);
    dbms_scheduler.enable(l_job);
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
    commit;
  end;
end doom_match_worker;
/
