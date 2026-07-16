-- Appendix F transaction boundary.  STEP_RESPONSES is intentionally consulted
-- before TIC_COMMANDS is changed: retries are transport cache hits, not tics.
create or replace package doom_tic_tx authid definer as
  procedure apply_batch(
    p_session  in  varchar2,
    p_commands in  clob,
    p_response out blob
  );
end doom_tic_tx;
/

create or replace package body doom_tic_tx as
  c_malformed constant pls_integer := -20861;
  c_conflict  constant pls_integer := -20862;
  c_old       constant pls_integer := -20863;
  c_gap       constant pls_integer := -20864;
  c_session   constant pls_integer := -20865;

  procedure fail(p_code pls_integer, p_message varchar2) is
  begin
    raise_application_error(p_code, p_message);
  end;

  function sha256(p_document clob) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.hash(p_document, dbms_crypto.hash_sh256)));
  end;

  function utf8_blob(p_document clob) return blob is
    l_blob blob;
    l_dest integer := 1;
    l_src integer := 1;
    l_context integer := 0;
    l_warning integer;
  begin
    dbms_lob.createtemporary(l_blob, true, dbms_lob.call);
    dbms_lob.converttoblob(l_blob, p_document, dbms_lob.lobmaxsize,
      l_dest, l_src, nls_charset_id('AL32UTF8'), l_context, l_warning);
    if l_warning <> 0 then fail(c_malformed, 'command document encoding'); end if;
    return l_blob;
  end;

  procedure apply_controls(
    p_session varchar2,p_tic number,p_pause_toggle number,p_menu_action varchar2,
    p_automap_toggle number,p_cheat_code varchar2,
    io_paused in out number,io_menu in out varchar2,
    io_automap in out varchar2,io_mode in out varchar2
  ) is
  begin
    if p_pause_toggle=1 then
      io_paused:=mod(io_paused+1,2);
      insert into game_events(session_token,tic,event_ordinal,event_type,text_value)
      select p_session,p_tic,coalesce(max(event_ordinal)+1,0),
        'CONTROL_PAUSE',to_char(io_paused,'TM9') from game_events
      where session_token=p_session and tic=p_tic;
    end if;
    if p_menu_action<>'NONE' then
      io_menu:=p_menu_action;
      insert into game_events(session_token,tic,event_ordinal,event_type,text_value)
      select p_session,p_tic,coalesce(max(event_ordinal)+1,0),
        'CONTROL_MENU',io_menu from game_events
      where session_token=p_session and tic=p_tic;
    end if;
    if p_automap_toggle=1 then
      io_automap:=case when io_automap='ON' then 'OFF' else 'ON' end;
      io_mode:=case when io_automap='ON' then 'AUTOMAP' else 'GAME' end;
      insert into game_events(session_token,tic,event_ordinal,event_type,text_value)
      select p_session,p_tic,coalesce(max(event_ordinal)+1,0),
        'CONTROL_AUTOMAP',io_automap from game_events
      where session_token=p_session and tic=p_tic;
    end if;
    if p_cheat_code is not null then
      insert into game_events(session_token,tic,event_ordinal,event_type,text_value)
      select p_session,p_tic,coalesce(max(event_ordinal)+1,0),
        'CONTROL_CHEAT',p_cheat_code from game_events
      where session_token=p_session and tic=p_tic;
    end if;
  end;

  function emitted_event_count(p_session varchar2,p_first_tic number,p_last_tic number)
    return number is l_count number;
  begin
    select count(*) into l_count from game_events where session_token=p_session
      and tic between p_first_tic and p_last_tic;
    return l_count;
  end;

  procedure apply_batch(
    p_session  in  varchar2,
    p_commands in  clob,
    p_response out blob
  ) is
    l_tic number;
    l_frontier number;
    l_paused number;
    l_menu varchar2(32);
    l_automap varchar2(16);
    l_initial_automap varchar2(16);
    l_mode varchar2(16);
    l_root json_object_t;
    l_array json_array_t;
    l_command json_object_t;
    l_keys json_key_list;
    l_count pls_integer;
    l_first number;
    l_last number;
    l_command_document clob;
    l_command_sha varchar2(64);
    l_cached_sha varchar2(64);
    l_cached blob;
    l_state_sha varchar2(64);
    l_payload clob;
    l_payload_blob blob;
    l_command_state_blob blob;
    l_input_blob blob;
    l_event_count number;
    l_bad number;
    l_previous_x number;
    l_previous_y number;
    l_angle number;
    l_delta_x number;
    l_delta_y number;
    l_move_player number;
    l_dest_x number;
    l_dest_y number;
    l_dest_z number;
    l_dest_view number;
    l_world_ready number;
    l_lineage varchar2(64);
    l_legacy number;
    l_history_interval number;
    l_row_command_sha varchar2(64);
    l_expected_keys constant varchar2(200) :=
      ',seq,turn,forward,strafe,run,fire,use,weapon,pause,automap,menu,cheat,';
  begin
    p_response := null;

    -- The lock is deliberately the first read of request content or mutable state.
    begin
      select current_tic,last_command_seq,paused,menu_state,automap_state,game_mode
        into l_tic,l_frontier,l_paused,l_menu,l_automap,l_mode
        from game_sessions where session_token=p_session for update;
    exception when no_data_found then
      fail(c_session, 'unknown or expired session');
    end;
    l_initial_automap := l_automap;
    select number_value into l_history_interval from doom_config
      where config_key='HISTORY_SNAPSHOT_INTERVAL';
    if l_history_interval<>trunc(l_history_interval) or l_history_interval<1 then
      fail(c_malformed,'invalid history checkpoint interval');
    end if;

    begin
      if p_commands is null then fail(c_malformed, 'missing command document'); end if;
      l_input_blob := utf8_blob(p_commands);
      if dbms_lob.getlength(l_input_blob) > 65536 then
        fail(c_malformed, 'command document exceeds 65536 bytes');
      end if;
      l_root := json_object_t.parse(p_commands);
      l_keys := l_root.get_keys;
      if l_keys.count <> 2 or not l_root.has('v') or not l_root.has('commands')
         or not l_root.get('v').is_number or l_root.get_number('v') <> 1
         or not l_root.get('commands').is_array then
        fail(c_malformed, 'invalid command envelope');
      end if;
      l_array := l_root.get_array('commands');
      l_count := l_array.get_size;
      if l_count < 1 or l_count > 4 then fail(c_malformed, 'batch size'); end if;
      for i in 0..l_count-1 loop
        if not l_array.get(i).is_object then fail(c_malformed, 'command object required'); end if;
        l_command := treat(l_array.get(i) as json_object_t);
        l_keys := l_command.get_keys;
        if l_keys.count <> 12 then fail(c_malformed, 'command key count'); end if;
        for j in 1..l_keys.count loop
          if instr(l_expected_keys, ','||l_keys(j)||',') = 0 then
            fail(c_malformed, 'unknown command key');
          end if;
        end loop;
        for j in 1..10 loop
          if not l_command.get(case j when 1 then 'seq' when 2 then 'turn'
            when 3 then 'forward' when 4 then 'strafe' when 5 then 'run'
            when 6 then 'fire' when 7 then 'use' when 8 then 'weapon'
            when 9 then 'pause' else 'automap' end).is_number then
            fail(c_malformed, 'numeric command field required');
          end if;
        end loop;
        if not l_command.get('menu').is_string or not l_command.get('cheat').is_string
           or length(l_command.get_string('menu')) > 32
           or length(l_command.get_string('cheat')) > 32 then
          fail(c_malformed, 'command string domain');
        end if;
      end loop;

      -- JSON_TABLE is the relational expansion boundary; all domain checks are
      -- performed before any state or append-only table is changed.
      select min(seq) keep (dense_rank first order by ord),
             max(seq) keep (dense_rank last order by ord),
             count(case when seq<>trunc(seq) or seq not between 1 and 999999999999
                          or turn<>trunc(turn) or turn not between -1 and 1
                          or forward_move<>trunc(forward_move) or forward_move not between -1 and 1
                          or strafe<>trunc(strafe) or strafe not between -1 and 1
                          or run<>trunc(run) or run not between 0 and 1
                          or fire<>trunc(fire) or fire not between 0 and 1
                          or use_action<>trunc(use_action) or use_action not between 0 and 1
                          or weapon<>trunc(weapon) or weapon not between 0 and 9
                          or pause_toggle<>trunc(pause_toggle) or pause_toggle not between 0 and 1
                          or automap_toggle<>trunc(automap_toggle) or automap_toggle not between 0 and 1
                        then 1 end)
        into l_first,l_last,l_bad
        from json_table(p_commands, '$.commands[*]' columns(
          ord for ordinality, seq number path '$.seq' error on error,
          turn number path '$.turn' error on error,
          forward_move number path '$.forward' error on error,
          strafe number path '$.strafe' error on error,
          run number path '$.run' error on error, fire number path '$.fire' error on error,
          use_action number path '$.use' error on error, weapon number path '$.weapon' error on error,
          pause_toggle number path '$.pause' error on error,
          automap_toggle number path '$.automap' error on error,
          menu_action varchar2(32) path '$.menu' error on error,
          cheat_code varchar2(32) path '$.cheat' error on error));
      if l_bad <> 0 then fail(c_malformed, 'command numeric domain'); end if;
      select count(*) into l_bad from (
        select seq,lag(seq) over(order by ord) prior_seq from json_table(
          p_commands, '$.commands[*]' columns(ord for ordinality, seq number path '$.seq'))
      ) where prior_seq is not null and seq<>prior_seq+1;
      if l_bad <> 0 then fail(c_malformed, 'nonconsecutive batch'); end if;

      select json_object('v' value 1, 'commands' value json_arrayagg(
        json_object('seq' value seq, 'turn' value turn,
          'forward' value forward_move, 'strafe' value strafe,
          'run' value run, 'fire' value fire, 'use' value use_action,
          'weapon' value weapon, 'pause' value pause_toggle,
          'automap' value automap_toggle, 'menu' value menu_action,
          'cheat' value cheat_json format json returning clob)
        order by ord returning clob) format json returning clob)
        into l_command_document
        from json_table(p_commands, '$.commands[*]' columns(
          ord for ordinality, seq number path '$.seq', turn number path '$.turn',
          forward_move number path '$.forward', strafe number path '$.strafe',
          run number path '$.run', fire number path '$.fire',
          use_action number path '$.use', weapon number path '$.weapon',
          pause_toggle number path '$.pause', automap_toggle number path '$.automap',
          menu_action varchar2(32) path '$.menu', cheat_code varchar2(32) path '$.cheat',
          cheat_json varchar2(4000) format json path '$.cheat'));
      l_command_sha := sha256(l_command_document);
    exception
      when others then
        if sqlcode between -20865 and -20861 then raise; end if;
        fail(c_malformed, 'malformed command document');
    end;

    -- Only the current accepted range is retryable.  A changed document for
    -- that range is a conflict; older ranges are deliberately not replayed.
    if l_first <= l_frontier then
      if l_last=l_frontier then
        begin
          select command_sha,response_blob into l_cached_sha,l_cached
            from step_responses
           where session_token=p_session and first_seq=l_first and last_seq=l_last;
          if l_cached_sha<>l_command_sha then fail(c_conflict, 'conflicting accepted range'); end if;
          dbms_lob.createtemporary(p_response, true, dbms_lob.call);
          dbms_lob.copy(p_response,l_cached,dbms_lob.getlength(l_cached));
          return;
        exception when no_data_found then null;
        end;
      end if;
      fail(c_old, 'old command range');
    end if;
    if l_first<>l_frontier+1 then fail(c_gap, 'command sequence gap'); end if;

    select save_lineage into l_lineage from game_sessions where session_token=p_session;
    l_legacy:=case when regexp_like(l_lineage,'^[0-9a-f]{64}$') then 0 else 1 end;
    select case when
      (select count(*) from sector_state where session_token=p_session)>0 and
      (select count(*) from line_state where session_token=p_session)>0
      then 1 else 0 end into l_world_ready from dual;

    -- Apply, hash, and capture each accepted command as one logical tic.  This
    -- keeps multi-command batches independent of request batching.
    for command_row in (
      select ord,seq,turn,forward_move,strafe,run,fire,use_action,weapon,
             pause_toggle,automap_toggle,menu_action,cheat_code
      from json_table(p_commands,'$.commands[*]' columns(
        ord for ordinality,seq number path '$.seq',turn number path '$.turn',
        forward_move number path '$.forward',strafe number path '$.strafe',
        run number path '$.run',fire number path '$.fire',
        use_action number path '$.use',weapon number path '$.weapon',
        pause_toggle number path '$.pause',automap_toggle number path '$.automap',
        menu_action varchar2(32) path '$.menu',cheat_code varchar2(32) path '$.cheat'))
      order by ord
    ) loop
      -- The validated command becomes visible before any gameplay subsystem
      -- advances this tic.  State/frame fields are finalized after simulation;
      -- every write remains inside the caller-owned locked transaction.
      doom_command_ledger.begin_command(p_session,l_lineage,command_row.seq,
        l_tic+command_row.ord,command_row.turn,command_row.forward_move,
        command_row.strafe,command_row.run,command_row.fire,
        command_row.use_action,command_row.weapon,command_row.pause_toggle,
        command_row.automap_toggle,command_row.menu_action,command_row.cheat_code,
        l_row_command_sha,l_command_state_blob);

      apply_controls(p_session,l_tic+command_row.ord,command_row.pause_toggle,
        command_row.menu_action,command_row.automap_toggle,command_row.cheat_code,
        l_paused,l_menu,l_automap,l_mode);

      if l_world_ready=1 then
        select p.x,p.y,mod(p.angle+command_row.turn*5.625+360,360)
          into l_previous_x,l_previous_y,l_angle
          from game_sessions g join players p
            on p.session_token=g.session_token and p.player_id=g.current_player_id
         where g.session_token=p_session;
        update players set angle=l_angle where session_token=p_session and player_id=(
          select current_player_id from game_sessions where session_token=p_session);
        l_delta_x := (command_row.forward_move*cos(l_angle*acos(-1)/180)
                      +command_row.strafe*sin(l_angle*acos(-1)/180))*8*(command_row.run+1);
        l_delta_y := (command_row.forward_move*sin(l_angle*acos(-1)/180)
                      -command_row.strafe*cos(l_angle*acos(-1)/180))*8*(command_row.run+1);
        if l_delta_x=0 and l_delta_y=0 then
          select player_id,x,y,z,view_height
            into l_move_player,l_dest_x,l_dest_y,l_dest_z,l_dest_view
            from players where session_token=p_session and player_id=(
              select current_player_id from game_sessions
                where session_token=p_session);
        else
          select player_id,dest_x,dest_y,dest_z,view_height
            into l_move_player,l_dest_x,l_dest_y,l_dest_z,l_dest_view
            from table(doom_player_move(p_session,l_delta_x,l_delta_y));
        end if;
        update players set x=l_dest_x,y=l_dest_y,z=l_dest_z,view_height=l_dest_view
          where session_token=p_session and player_id=l_move_player;
        doom_world_machines.advance(p_session,l_tic+command_row.ord,
          l_previous_x,l_previous_y,command_row.use_action);
        doom_combat.advance(p_session,l_tic+command_row.ord);
        doom_monsters.advance(p_session,l_tic+command_row.ord);
      end if;
      doom_audio.emit(p_session,l_tic+command_row.ord);

      update game_sessions set current_tic=l_tic+command_row.ord,
        last_command_seq=command_row.seq,paused=l_paused,menu_state=l_menu,
        automap_state=l_automap,game_mode=l_mode where session_token=p_session;
      doom_canonical_state.build_into_locator(p_session,l_legacy,
        l_command_state_blob,l_state_sha);
      doom_command_ledger.finalize_command(p_session,l_lineage,command_row.seq,
        l_state_sha,l_state_sha);
      -- Modern lineages only persist history documents at the configured
      -- checkpoint cadence.  Per-command hashes/BLOBs are already complete;
      -- avoid re-hashing the same 200+ KiB state in the history adapter on the
      -- three non-checkpoint tics.  Legacy batches retain their terminal call.
      if (l_legacy=0 and mod(l_tic+command_row.ord,l_history_interval)=0)
         or (l_legacy=1 and command_row.ord=l_count) then
        doom_capture_tic_blob(p_session,l_tic+command_row.ord,l_command_state_blob,
          l_state_sha,l_state_sha);
      end if;
    end loop;

    l_event_count:=emitted_event_count(p_session,l_tic+1,l_tic+l_count);

    -- DOOM_HISTORY.CAPTURE_TIC persists reviewed STATE_HISTORY checkpoints
    -- after authoritative tic effects and before response construction.

    if l_legacy=0 then
      select json_object('v' value 1,'tic' value l_tic+l_count,
          'logical_hz' value 35,'first_seq' value l_first,'last_seq' value l_last,
          'command_sha' value l_command_sha,'state_sha' value l_state_sha,
          'frame_sha' value l_state_sha,'event_count' value l_event_count returning clob)
        into l_payload from dual;
    else
      select json_object('v' value 1,'tic' value l_tic+l_count,
          'logical_hz' value 35,'first_seq' value l_first,'last_seq' value l_last,
          'command_sha' value l_command_sha,'state_sha' value l_state_sha,
          'event_count' value l_event_count returning clob)
        into l_payload from dual;
    end if;
    l_payload_blob := utf8_blob(l_payload);
    dbms_lob.createtemporary(p_response,true,dbms_lob.call);
    dbms_lob.copy(p_response,l_payload_blob,dbms_lob.getlength(l_payload_blob));

    -- P_RESPONSE is complete before the cache row exists; boundary control stays external.
    insert into step_responses(session_token,first_seq,last_seq,command_sha,
      first_tic,last_tic,state_sha,frame_sha,response_blob)
    values(p_session,l_first,l_last,l_command_sha,l_tic+1,l_tic+l_count,
      l_state_sha,l_state_sha,l_payload_blob);
  end apply_batch;
end doom_tic_tx;
/
