whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off heading off timing off

declare
  l_session varchar2(32);l_lineage varchar2(64);l_payload blob;
  l_oracle blob;l_actual blob;l_locator blob;l_row_blob blob;
  l_oracle_sha varchar2(64);l_actual_sha varchar2(64);l_row_sha varchar2(64);
  l_command_sha varchar2(64);l_previous_sha varchar2(64);l_expected_sha varchar2(64);
  l_result_tic number;l_result_seq number;l_tic number;l_seq number;l_count number;
  l_head_existed number;l_before_cs number;l_oracle_cs number;l_extracted_cs number;
  l_command raw(24):=hextoraw('444D53430201000000000000000000010101FF0100000000');
  l_bad_command raw(24):=hextoraw('444D53430201000000000000000000010101FF0100000001');
  l_action_command raw(24):=hextoraw('444D53430301000000000000000000010101FF0100000200');
  l_bad_action raw(24):=hextoraw('444D53430301000000000000000000010101FF0100000201');
  l_command_doc clob:=to_clob(
    '{"v":1,"commands":[{"turn":1,"forward":1,"strafe":-1,"run":1,'||
    '"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE",'||
    '"cheat":"","seq":1}]}');
  c_zero_sha constant varchar2(64):=rpad('0',64,'0');

  procedure assert_(p_ok boolean,p_message varchar2) is
  begin if not p_ok then raise_application_error(-20000,p_message);end if;end;
  function oracle_state_document(p_session varchar2,p_legacy number) return blob is
    l_document blob;
  begin
    select json_object(
      'schema' value 1,
      'skill' value s.skill,
      'current_player_id' value s.current_player_id,
      'tic' value s.current_tic,
      'rng_cursor' value s.rng_cursor,
      'game_mode' value s.game_mode,
      'map_status' value s.map_status,
      'paused' value s.paused,
      'menu_state' value s.menu_state,
      'automap_state' value s.automap_state,
      'last_command_seq' value case when p_legacy=0 then null else s.last_command_seq end,
      'save_lineage' value case when p_legacy=0 then null else s.save_lineage end,
      'player' value (
        select json_object(
          'player_id' value p.player_id, 'x' value p.x, 'y' value p.y,
          'z' value p.z, 'momentum_x' value p.momentum_x,
          'momentum_y' value p.momentum_y, 'momentum_z' value p.momentum_z,
          'angle' value p.angle, 'view_height' value p.view_height,
          'view_bob' value p.view_bob, 'health' value p.health,
          'armor' value p.armor, 'armor_type' value p.armor_type,
          'blue_key' value p.blue_key, 'yellow_key' value p.yellow_key,
          'red_key' value p.red_key, 'ammo_bullets' value p.ammo_bullets,
          'ammo_shells' value p.ammo_shells, 'ammo_rockets' value p.ammo_rockets,
          'ammo_cells' value p.ammo_cells, 'weapon_mask' value p.weapon_mask,
          'selected_weapon' value p.selected_weapon,
          'pending_weapon' value p.pending_weapon,
          'weapon_state' value p.weapon_state,
          'weapon_state_tics' value p.weapon_state_tics,
          'flash_state' value p.flash_state,
          'flash_state_tics' value p.flash_state_tics,
          'refire' value p.refire, 'backpack' value p.backpack,
          'power_berserk' value p.power_berserk,
          'power_invulnerability' value p.power_invulnerability,
          'power_invisibility' value p.power_invisibility,
          'power_ironfeet' value p.power_ironfeet,
          'power_lightamp' value p.power_lightamp,
          'kill_count' value p.kill_count, 'item_count' value p.item_count,
          'secret_count' value p.secret_count, 'alive' value p.alive,
          'noclip' value p.noclip
          returning varchar2(4000))
        from players p
        where p.session_token=s.session_token and p.player_id=s.current_player_id
      ) format json,
      'mobjs' value coalesce((
        select json_arrayagg(json_object(
          'mobj_id' value mobj_id, 'thing_type' value thing_type,
          'state_id' value state_id, 'state_tics' value state_tics,
          'x' value x, 'y' value y, 'z' value z,
          'momentum_x' value momentum_x, 'momentum_y' value momentum_y,
          'momentum_z' value momentum_z, 'angle' value angle,
          'radius' value radius, 'height' value height, 'health' value health,
          'flags' value flags, 'target_mobj_id' value target_mobj_id,
          'tracer_mobj_id' value tracer_mobj_id, 'reaction_time' value reaction_time,
          'spawn_thing_id' value spawn_thing_id,
          'owner_mobj_id' value owner_mobj_id,
          'projectile_kind' value projectile_kind,
          'exploded' value exploded,
          'sector_id' value sector_id,
          'move_direction' value move_direction,
          'awake' value awake,
          'attack_cooldown' value attack_cooldown,
          'monster_health_seen' value monster_health_seen,
          'death_processed' value death_processed returning varchar2(4000))
          order by mobj_id returning clob)
        from mobjs where session_token=s.session_token), to_clob('[]')) format json,
      'sectors' value coalesce((
        select json_arrayagg(json_object(
          'sector_id' value sector_id, 'floor_height' value floor_height,
          'ceiling_height' value ceiling_height, 'light_level' value light_level,
          'light_timer' value light_timer,
          'secret_found' value secret_found, 'damage_clock' value damage_clock
          returning varchar2(4000)) order by sector_id returning clob)
        from sector_state where session_token=s.session_token), to_clob('[]')) format json,
      'lines' value coalesce((
        select json_arrayagg(json_object(
          'linedef_id' value linedef_id, 'trigger_count' value trigger_count,
          'switch_on' value switch_on returning varchar2(4000))
          order by linedef_id returning clob)
        from line_state where session_token=s.session_token), to_clob('[]')) format json,
      'movers' value coalesce((
        select json_arrayagg(json_object(
          'mover_id' value mover_id, 'sector_id' value sector_id,
          'plane' value plane, 'direction' value direction, 'speed' value speed,
          'target_height' value target_height, 'wait_tics' value wait_tics,
          'timer_tics' value timer_tics, 'mover_kind' value mover_kind,
          'origin_height' value origin_height,
          'source_linedef_id' value source_linedef_id returning varchar2(4000))
          order by mover_id returning clob)
        from active_movers where session_token=s.session_token), to_clob('[]')) format json,
      'switches' value coalesce((
        select json_arrayagg(json_object(
          'linedef_id' value linedef_id, 'timer_tics' value timer_tics,
          'restore_texture' value restore_texture returning varchar2(4000))
          order by linedef_id returning clob)
        from active_switches where session_token=s.session_token), to_clob('[]')) format json,
      'ordering_version' value 'APPENDIX-F-1'
      absent on null returning blob)
      into l_document
      from game_sessions s where s.session_token=p_session;
    if p_legacy=1 then
      -- Preserve the reviewed pre-history transport digest for legacy short
      -- lineages.  SHA-256 lineages retain the complete combat state closure.
      select json_transform(l_document,
        remove '$.player.noclip',
        remove '$.player.pending_weapon',
        remove '$.player.weapon_state',
        remove '$.player.weapon_state_tics',
        remove '$.player.flash_state',
        remove '$.player.flash_state_tics',
        remove '$.player.refire',
        remove '$.player.backpack',
        remove '$.player.power_berserk',
        remove '$.mobjs[*].owner_mobj_id',
        remove '$.mobjs[*].projectile_kind',
        remove '$.mobjs[*].exploded',
        remove '$.mobjs[*].sector_id',
        remove '$.mobjs[*].move_direction',
        remove '$.mobjs[*].awake',
        remove '$.mobjs[*].attack_cooldown',
        remove '$.mobjs[*].monster_health_seen',
        remove '$.mobjs[*].death_processed' returning blob)
        into l_document from dual;
    end if;
    return l_document;
  end;

begin
  doom_api.new_game(3,l_session,l_payload);
  select save_lineage,current_tic,last_command_seq into l_lineage,l_tic,l_seq
    from game_sessions where session_token=l_session;

  -- Both lineage modes are byte-locked against the pre-extraction SQL oracle.
  for mode_ in 0..1 loop
    l_oracle:=oracle_state_document(l_session,mode_);
    l_oracle_sha:=lower(rawtohex(dbms_crypto.hash(l_oracle,dbms_crypto.hash_sh256)));
    doom_canonical_state.build(l_session,mode_,l_actual,l_actual_sha);
    assert_(l_actual_sha=l_oracle_sha,'canonical SHA parity mode='||mode_);
    assert_(dbms_lob.compare(l_actual,l_oracle)=0,'canonical byte parity mode='||mode_);
  end loop;

  -- Record directly comparable generation+SHA timings; no DB execution is
  -- required during static review, but the acceptance emits evidence when run.
  l_before_cs:=dbms_utility.get_time;
  for i in 1..10 loop
    l_oracle:=oracle_state_document(l_session,0);
    l_oracle_sha:=lower(rawtohex(dbms_crypto.hash(l_oracle,dbms_crypto.hash_sh256)));
  end loop;
  l_oracle_cs:=dbms_utility.get_time-l_before_cs;
  l_before_cs:=dbms_utility.get_time;
  for i in 1..10 loop
    doom_canonical_state.build(l_session,0,l_actual,l_actual_sha);
  end loop;
  l_extracted_cs:=dbms_utility.get_time-l_before_cs;
  dbms_output.put_line('CANONICAL_STATE_TIMING old_cs='||l_oracle_cs||
    ' extracted_cs='||l_extracted_cs||' iterations=10');

  select count(*),coalesce(max(command_sha),c_zero_sha)
    into l_head_existed,l_previous_sha from history_heads
    where session_token=l_session and lineage=l_lineage;
  savepoint ledger_start;
  doom_command_ledger.begin_dmsc_v2(l_session,l_lineage,l_tic,l_seq,l_command,
    l_result_tic,l_result_seq,l_command_sha,l_locator);
  assert_(l_result_tic=l_tic+1 and l_result_seq=l_seq+1,'DMSC frontier outputs');
  select lower(rawtohex(dbms_crypto.hash(json_object(
      'seq' value l_result_seq,'lineage' value l_lineage,'tic' value l_result_tic,
      'ordinal' value 0,'turn' value 1,'forward' value 1,'strafe' value -1,
      'run' value 1,'fire' value 0,'use' value 0,'weapon' value 0,
      'pause' value 0,'automap' value 0,'menu' value 'NONE','cheat' value '',
      'previous_command_sha' value l_previous_sha returning clob),
      dbms_crypto.hash_sh256))) into l_expected_sha from dual;
  assert_(l_command_sha=l_expected_sha,'DMSC command-chain SHA');

  doom_canonical_state.build_into_locator(l_session,0,l_locator,l_actual_sha);
  doom_command_ledger.finalize_command(l_session,l_lineage,l_result_seq,
    l_actual_sha,l_actual_sha);
  l_oracle:=oracle_state_document(l_session,0);
  select state_blob,state_sha into l_row_blob,l_row_sha from tic_commands
    where session_token=l_session and command_seq=l_result_seq;
  assert_(l_row_sha=l_actual_sha,'filled locator finalized SHA');
  assert_(dbms_lob.compare(l_row_blob,l_oracle)=0,'filled locator canonical bytes');
  rollback to ledger_start;
  select count(*) into l_count from tic_commands
    where session_token=l_session and command_seq=l_result_seq;
  assert_(l_count=0,'ledger rollback removed command');
  select count(*) into l_count from history_heads
    where session_token=l_session and lineage=l_lineage
      and command_sha=l_previous_sha;
  assert_(l_count=l_head_existed,'ledger rollback restored history head');

  -- DMSC/v3 preserves the fixed 24-byte envelope while assigning the three
  -- formerly reserved action slots. Its command-chain document is still the
  -- canonical public command JSON, not a hash of the packed transport.
  savepoint action_ledger_start;
  doom_command_ledger.begin_dmsc_v3(l_session,l_lineage,l_tic,l_seq,
    l_action_command,l_result_tic,l_result_seq,l_command_sha,l_locator);
  select lower(rawtohex(dbms_crypto.hash(json_object(
      'seq' value l_result_seq,'lineage' value l_lineage,'tic' value l_result_tic,
      'ordinal' value 0,'turn' value 1,'forward' value 1,'strafe' value -1,
      'run' value 1,'fire' value 0,'use' value 0,'weapon' value 2,
      'pause' value 0,'automap' value 0,'menu' value 'NONE','cheat' value '',
      'previous_command_sha' value l_previous_sha returning clob),
      dbms_crypto.hash_sh256))) into l_expected_sha from dual;
  assert_(l_command_sha=l_expected_sha,'DMSC/v3 command-chain SHA');
  select count(*) into l_count from tic_commands where session_token=l_session
    and command_seq=l_result_seq and weapon_slot=2 and fire=0 and use_action=0;
  assert_(l_count=1,'DMSC/v3 action fields');
  rollback to action_ledger_start;

  -- Malformed packs and invalid frontiers must reject before any ledger write.
  begin
    doom_command_ledger.begin_dmsc_v2(l_session,l_lineage,l_tic,l_seq,l_bad_command,
      l_result_tic,l_result_seq,l_command_sha,l_locator);
    raise_application_error(-20000,'DMSC unsupported byte accepted');
  exception when others then
    if sqlcode<>-20867 then raise;end if;
  end;
  begin
    doom_command_ledger.begin_dmsc_v2(l_session,l_lineage,l_tic+0.5,l_seq,l_command,
      l_result_tic,l_result_seq,l_command_sha,l_locator);
    raise_application_error(-20000,'DMSC fractional frontier accepted');
  exception when others then
    if sqlcode<>-20867 then raise;end if;
  end;
  begin
    doom_command_ledger.begin_dmsc_v3(l_session,l_lineage,l_tic,l_seq,l_bad_action,
      l_result_tic,l_result_seq,l_command_sha,l_locator);
    raise_application_error(-20000,'DMSC/v3 reserved byte accepted');
  exception when others then
    if sqlcode<>-20867 then raise;end if;
  end;
  select count(*) into l_count from tic_commands where session_token=l_session;
  assert_(l_count=0,'rejected DMSC changed ledger');

  -- The production transaction path must retain exactly the old modern bytes.
  savepoint transaction_start;
  doom_tic_tx.apply_batch(l_session,l_command_doc,l_payload);
  select state_blob,state_sha into l_row_blob,l_row_sha from tic_commands
    where session_token=l_session and command_seq=1;
  l_oracle:=oracle_state_document(l_session,0);
  l_oracle_sha:=lower(rawtohex(dbms_crypto.hash(l_oracle,dbms_crypto.hash_sh256)));
  assert_(l_row_sha=l_oracle_sha,'tic transaction canonical SHA');
  assert_(dbms_lob.compare(l_row_blob,l_oracle)=0,'tic transaction canonical bytes');
  rollback to transaction_start;
  select current_tic,last_command_seq into l_result_tic,l_result_seq
    from game_sessions where session_token=l_session;
  assert_(l_result_tic=l_tic and l_result_seq=l_seq,'tic transaction rollback frontier');
  select count(*) into l_count from tic_commands where session_token=l_session;
  assert_(l_count=0,'tic transaction rollback ledger');

  dbms_output.put_line('CANONICAL_STATE_LEDGER_ACCEPTANCE_OK modern=1 legacy=1 rollback=1');
  rollback;
end;
/

exit
