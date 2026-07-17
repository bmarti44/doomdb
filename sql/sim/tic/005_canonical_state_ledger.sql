-- Shared byte-locked state serialization and one-command history ledger.
-- SQL/JSON returns a new temporary BLOB locator; it cannot stream a SELECT
-- result into an existing SecureFile locator.  BUILD_INTO_LOCATOR therefore
-- keeps the one necessary LOB copy, but never updates the containing SQL row.
create or replace package doom_canonical_state authid definer as
  procedure build(
    p_session in varchar2,p_legacy in number,
    p_document out blob,p_state_sha out varchar2);
  procedure build_into_locator(
    p_session in varchar2,p_legacy in number,
    p_target in out nocopy blob,p_state_sha out varchar2);
end doom_canonical_state;
/

create or replace package body doom_canonical_state as
  procedure build(
    p_session in varchar2,p_legacy in number,
    p_document out blob,p_state_sha out varchar2
  ) is
  begin
    p_document:=null;p_state_sha:=null;
    if p_legacy is null or p_legacy not in(0,1) then
      raise_application_error(-20866,'invalid canonical state lineage mode');
    end if;
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
          'noclip' value p.noclip returning varchar2(4000))
        from players p where p.session_token=s.session_token
          and p.player_id=s.current_player_id) format json,
      'mobjs' value coalesce((select json_arrayagg(json_object(
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
          'projectile_kind' value projectile_kind, 'exploded' value exploded,
          'sector_id' value sector_id, 'move_direction' value move_direction,
          'awake' value awake, 'attack_cooldown' value attack_cooldown,
          'monster_health_seen' value monster_health_seen,
          'death_processed' value death_processed returning varchar2(4000))
          order by mobj_id returning clob) from mobjs
          where session_token=s.session_token),to_clob('[]')) format json,
      'sectors' value coalesce((select json_arrayagg(json_object(
          'sector_id' value sector_id, 'floor_height' value floor_height,
          'ceiling_height' value ceiling_height, 'light_level' value light_level,
          'light_timer' value light_timer, 'secret_found' value secret_found,
          'damage_clock' value damage_clock returning varchar2(4000))
          order by sector_id returning clob) from sector_state
          where session_token=s.session_token),to_clob('[]')) format json,
      'lines' value coalesce((select json_arrayagg(json_object(
          'linedef_id' value linedef_id, 'trigger_count' value trigger_count,
          'switch_on' value switch_on returning varchar2(4000))
          order by linedef_id returning clob) from line_state
          where session_token=s.session_token),to_clob('[]')) format json,
      'movers' value coalesce((select json_arrayagg(json_object(
          'mover_id' value mover_id, 'sector_id' value sector_id,
          'plane' value plane, 'direction' value direction, 'speed' value speed,
          'target_height' value target_height, 'wait_tics' value wait_tics,
          'timer_tics' value timer_tics, 'mover_kind' value mover_kind,
          'origin_height' value origin_height,
          'source_linedef_id' value source_linedef_id returning varchar2(4000))
          order by mover_id returning clob) from active_movers
          where session_token=s.session_token),to_clob('[]')) format json,
      'switches' value coalesce((select json_arrayagg(json_object(
          'linedef_id' value linedef_id, 'timer_tics' value timer_tics,
          'restore_texture' value restore_texture returning varchar2(4000))
          order by linedef_id returning clob) from active_switches
          where session_token=s.session_token),to_clob('[]')) format json,
      'ordering_version' value 'APPENDIX-F-1' absent on null returning blob)
      into p_document from game_sessions s where s.session_token=p_session;
    if p_legacy=1 then
      select json_transform(p_document,
        remove '$.player.noclip',remove '$.player.pending_weapon',
        remove '$.player.weapon_state',remove '$.player.weapon_state_tics',
        remove '$.player.flash_state',remove '$.player.flash_state_tics',
        remove '$.player.refire',remove '$.player.backpack',
        remove '$.player.power_berserk',remove '$.mobjs[*].owner_mobj_id',
        remove '$.mobjs[*].projectile_kind',remove '$.mobjs[*].exploded',
        remove '$.mobjs[*].sector_id',remove '$.mobjs[*].move_direction',
        remove '$.mobjs[*].awake',remove '$.mobjs[*].attack_cooldown',
        remove '$.mobjs[*].monster_health_seen',
        remove '$.mobjs[*].death_processed' returning blob)
        into p_document from dual;
    end if;
    p_state_sha:=lower(rawtohex(dbms_crypto.hash(
      p_document,dbms_crypto.hash_sh256)));
  exception when no_data_found then
    raise_application_error(-20865,'unknown canonical state session');
  end;

  procedure build_into_locator(
    p_session in varchar2,p_legacy in number,
    p_target in out nocopy blob,p_state_sha out varchar2
  ) is
    l_document blob;
  begin
    if p_target is null then
      raise_application_error(-20866,'canonical state target locator');
    end if;
    -- BUILD is the single hash point.  This trusted schema-internal path then
    -- performs only the unavoidable temporary-to-persistent locator copy.
    build(p_session,p_legacy,l_document,p_state_sha);
    dbms_lob.trim(p_target,0);
    dbms_lob.copy(p_target,l_document,dbms_lob.getlength(l_document),1,1);
  end;

end doom_canonical_state;
/

create or replace package doom_command_ledger authid definer as
  procedure begin_command(
    p_session in varchar2,p_lineage in varchar2,p_seq in number,p_tic in number,
    p_turn in number,p_forward in number,p_strafe in number,p_run in number,
    p_fire in number,p_use in number,p_weapon in number,p_pause in number,
    p_automap in number,p_menu in varchar2,p_cheat in varchar2,
    p_command_sha out varchar2,p_state_blob out blob);
  procedure begin_dmsc_v2(
    p_session in varchar2,p_lineage in varchar2,p_expected_tic in number,
    p_expected_seq in number,p_command in raw,p_result_tic out number,
    p_result_seq out number,p_command_sha out varchar2,p_state_blob out blob);
  procedure begin_dmsc_v3(
    p_session in varchar2,p_lineage in varchar2,p_expected_tic in number,
    p_expected_seq in number,p_command in raw,p_result_tic out number,
    p_result_seq out number,p_command_sha out varchar2,p_state_blob out blob);
  procedure begin_dmsc_v4(
    p_session in varchar2,p_lineage in varchar2,p_expected_tic in number,
    p_expected_seq in number,p_command in raw,p_result_tic out number,
    p_result_seq out number,p_command_sha out varchar2,p_state_blob out blob);
  procedure finalize_command(
    p_session in varchar2,p_lineage in varchar2,p_seq in number,
    p_state_sha in varchar2,p_frame_sha in varchar2);
end doom_command_ledger;
/

create or replace package body doom_command_ledger as
  c_zero_sha constant varchar2(64):=rpad('0',64,'0');
  function byte_at(p_raw raw,p_position pls_integer) return pls_integer is
  begin return to_number(rawtohex(utl_raw.substr(p_raw,p_position,1)),'XX');end;
  function signed_byte(p_raw raw,p_position pls_integer) return pls_integer is
    l_value pls_integer:=byte_at(p_raw,p_position);
  begin return case when l_value>=128 then l_value-256 else l_value end;end;
  function u32(p_raw raw,p_position pls_integer) return number is
  begin return to_number(rawtohex(utl_raw.substr(p_raw,p_position,4)),'XXXXXXXX');end;
  function u64(p_raw raw,p_position pls_integer) return number is
  begin return u32(p_raw,p_position)*4294967296+u32(p_raw,p_position+4);end;

  procedure begin_command(
    p_session in varchar2,p_lineage in varchar2,p_seq in number,p_tic in number,
    p_turn in number,p_forward in number,p_strafe in number,p_run in number,
    p_fire in number,p_use in number,p_weapon in number,p_pause in number,
    p_automap in number,p_menu in varchar2,p_cheat in varchar2,
    p_command_sha out varchar2,p_state_blob out blob
  ) is
    l_db_lineage varchar2(64);l_previous varchar2(64);
  begin
    p_command_sha:=null;p_state_blob:=null;
    if p_session is null or p_lineage is null or
       p_seq is null or p_seq<>trunc(p_seq) or p_seq not between 1 and 999999999999 or
       p_tic is null or p_tic<>trunc(p_tic) or p_tic not between 0 and 999999999999 or
       p_turn is null or p_turn not between -1 and 1 or
       p_forward is null or p_forward not between -1 and 1 or
       p_strafe is null or p_strafe not between -1 and 1 or
       p_run is null or p_run not in(0,1) or p_fire is null or p_fire not in(0,1) or
       p_use is null or p_use not in(0,1) or
       p_weapon is null or p_weapon not between 0 and 9 or
       p_pause is null or p_pause not in(0,1) or
       p_automap is null or p_automap not in(0,1) or
       p_menu is null or length(p_menu)>32 or
       length(p_cheat)>32 then raise_application_error(-20867,'invalid command ledger input');end if;
    select save_lineage into l_db_lineage from game_sessions
      where session_token=p_session for update;
    if l_db_lineage<>p_lineage then raise_application_error(-20867,'command ledger lineage');end if;
    merge into history_heads d using(select p_session session_token,p_lineage lineage from dual) s
    on(d.session_token=s.session_token and d.lineage=s.lineage)
    when not matched then insert(session_token,lineage,command_sha,event_sha)
      values(s.session_token,s.lineage,c_zero_sha,c_zero_sha);
    select command_sha into l_previous from history_heads
      where session_token=p_session and lineage=p_lineage for update;
    select lower(rawtohex(dbms_crypto.hash(json_object(
      'seq' value p_seq,'lineage' value p_lineage,'tic' value p_tic,
      'ordinal' value 0,'turn' value p_turn,'forward' value p_forward,
      'strafe' value p_strafe,'run' value p_run,'fire' value p_fire,
      'use' value p_use,'weapon' value p_weapon,'pause' value p_pause,
      'automap' value p_automap,'menu' value p_menu,
      'cheat' value coalesce(p_cheat,''),
      'previous_command_sha' value l_previous returning clob),
      dbms_crypto.hash_sh256))) into p_command_sha from dual;
    insert into tic_commands(session_token,lineage,command_seq,tic,command_ordinal,
      turn,forward_move,strafe,run,fire,use_action,weapon_slot,pause_toggle,
      automap_toggle,menu_action,cheat_code,previous_command_sha,command_sha,
      state_sha,frame_sha,state_blob)
    values(p_session,p_lineage,p_seq,p_tic,0,p_turn,p_forward,p_strafe,p_run,
      p_fire,p_use,p_weapon,p_pause,p_automap,p_menu,p_cheat,l_previous,p_command_sha,
      c_zero_sha,c_zero_sha,empty_blob()) returning state_blob into p_state_blob;
    update history_heads set command_sha=p_command_sha
      where session_token=p_session and lineage=p_lineage;
  exception when no_data_found then
    raise_application_error(-20867,'unknown command ledger session');
  end;

  procedure begin_dmsc_v2(
    p_session in varchar2,p_lineage in varchar2,p_expected_tic in number,
    p_expected_seq in number,p_command in raw,p_result_tic out number,
    p_result_seq out number,p_command_sha out varchar2,p_state_blob out blob
  ) is
    l_turn number;l_forward number;l_strafe number;l_run number;
  begin
    p_result_tic:=null;p_result_seq:=null;p_command_sha:=null;p_state_blob:=null;
    if p_expected_tic is null or p_expected_tic<>trunc(p_expected_tic) or
       p_expected_tic not between 0 and 999999999998 or
       p_expected_seq is null or p_expected_seq<>trunc(p_expected_seq) or
       p_expected_seq not between 0 and 999999999998 then
      raise_application_error(-20867,'invalid DMSC/v2 frontier');
    end if;
    if p_command is null or utl_raw.length(p_command)<>24 or
       rawtohex(utl_raw.substr(p_command,1,4))<>'444D5343' or
       byte_at(p_command,5)<>2 or byte_at(p_command,6)<>1 or
       byte_at(p_command,7)<>0 or byte_at(p_command,8)<>0 then
      raise_application_error(-20867,'invalid DMSC/v2 header');
    end if;
    p_result_seq:=u64(p_command,9);p_result_tic:=p_expected_tic+1;
    if p_result_seq<>p_expected_seq+1 then raise_application_error(-20867,'DMSC/v2 sequence');end if;
    l_turn:=signed_byte(p_command,17);l_forward:=signed_byte(p_command,18);
    l_strafe:=signed_byte(p_command,19);l_run:=byte_at(p_command,20);
    if l_turn not between -1 and 1 or l_forward not between -1 and 1 or
       l_strafe not between -1 and 1 or l_run not in(0,1) then
      raise_application_error(-20867,'DMSC/v2 movement');end if;
    for i in 21..24 loop if byte_at(p_command,i)<>0 then
      raise_application_error(-20867,'DMSC/v2 unsupported action');end if;end loop;
    begin_command(p_session,p_lineage,p_result_seq,p_result_tic,l_turn,l_forward,
      l_strafe,l_run,0,0,0,0,0,'NONE',null,p_command_sha,p_state_blob);
  end;

  procedure begin_dmsc_v3(
    p_session in varchar2,p_lineage in varchar2,p_expected_tic in number,
    p_expected_seq in number,p_command in raw,p_result_tic out number,
    p_result_seq out number,p_command_sha out varchar2,p_state_blob out blob
  ) is
    l_turn number;l_forward number;l_strafe number;l_run number;
    l_fire number;l_use number;l_weapon number;
  begin
    p_result_tic:=null;p_result_seq:=null;p_command_sha:=null;p_state_blob:=null;
    if p_expected_tic is null or p_expected_tic<>trunc(p_expected_tic) or
       p_expected_tic not between 0 and 999999999998 or
       p_expected_seq is null or p_expected_seq<>trunc(p_expected_seq) or
       p_expected_seq not between 0 and 999999999998 then
      raise_application_error(-20867,'invalid DMSC/v3 frontier');
    end if;
    if p_command is null or utl_raw.length(p_command)<>24 or
       rawtohex(utl_raw.substr(p_command,1,4))<>'444D5343' or
       byte_at(p_command,5)<>3 or byte_at(p_command,6)<>1 or
       byte_at(p_command,7)<>0 or byte_at(p_command,8)<>0 or
       byte_at(p_command,24)<>0 then
      raise_application_error(-20867,'invalid DMSC/v3 header');
    end if;
    p_result_seq:=u64(p_command,9);p_result_tic:=p_expected_tic+1;
    if p_result_seq<>p_expected_seq+1 then raise_application_error(-20867,'DMSC/v3 sequence');end if;
    l_turn:=signed_byte(p_command,17);l_forward:=signed_byte(p_command,18);
    l_strafe:=signed_byte(p_command,19);l_run:=byte_at(p_command,20);
    l_fire:=byte_at(p_command,21);l_use:=byte_at(p_command,22);
    l_weapon:=byte_at(p_command,23);
    if l_turn not between -1 and 1 or l_forward not between -1 and 1 or
       l_strafe not between -1 and 1 or l_run not in(0,1) or
       l_fire not in(0,1) or l_use not in(0,1) or l_weapon not between 0 and 9 then
      raise_application_error(-20867,'DMSC/v3 command domain');end if;
    begin_command(p_session,p_lineage,p_result_seq,p_result_tic,l_turn,l_forward,
      l_strafe,l_run,l_fire,l_use,l_weapon,0,0,'NONE',null,
      p_command_sha,p_state_blob);
  end;

  procedure begin_dmsc_v4(
    p_session in varchar2,p_lineage in varchar2,p_expected_tic in number,
    p_expected_seq in number,p_command in raw,p_result_tic out number,
    p_result_seq out number,p_command_sha out varchar2,p_state_blob out blob
  ) is
    l_turn number;l_forward number;l_strafe number;l_run number;
    l_fire number;l_use number;l_weapon number;
  begin
    p_result_tic:=null;p_result_seq:=null;p_command_sha:=null;p_state_blob:=null;
    if p_expected_tic is null or p_expected_tic<>trunc(p_expected_tic) or
       p_expected_tic not between 0 and 999999999998 or
       p_expected_seq is null or p_expected_seq<>trunc(p_expected_seq) or
       p_expected_seq not between 0 and 999999999998 then
      raise_application_error(-20867,'invalid DMSC/v4 frontier');
    end if;
    if p_command is null or utl_raw.length(p_command)<>24 or
       rawtohex(utl_raw.substr(p_command,1,4))<>'444D5343' or
       byte_at(p_command,5)<>4 or byte_at(p_command,6)<>1 or
       byte_at(p_command,7)<>0 or byte_at(p_command,8)<>0 or
       byte_at(p_command,24)<>0 then
      raise_application_error(-20867,'invalid DMSC/v4 header');
    end if;
    p_result_seq:=u64(p_command,9);p_result_tic:=p_expected_tic+1;
    if p_result_seq<>p_expected_seq+1 then raise_application_error(-20867,'DMSC/v4 sequence');end if;
    l_turn:=signed_byte(p_command,17);l_forward:=signed_byte(p_command,18);
    l_strafe:=signed_byte(p_command,19);l_run:=byte_at(p_command,20);
    l_fire:=byte_at(p_command,21);l_use:=byte_at(p_command,22);
    l_weapon:=byte_at(p_command,23);
    if l_turn not between -1 and 1 or l_forward not between -1 and 1 or
       l_strafe not between -1 and 1 or l_run not in(0,1) or
       l_fire not in(0,1) or l_use not in(0,1) or l_weapon not between 0 and 9 then
      raise_application_error(-20867,'DMSC/v4 command domain');end if;
    begin_command(p_session,p_lineage,p_result_seq,p_result_tic,l_turn,l_forward,
      l_strafe,l_run,l_fire,l_use,l_weapon,0,0,'NONE',null,
      p_command_sha,p_state_blob);
  end;

  procedure finalize_command(
    p_session in varchar2,p_lineage in varchar2,p_seq in number,
    p_state_sha in varchar2,p_frame_sha in varchar2
  ) is
  begin
    if p_state_sha is null or p_frame_sha is null or
       not regexp_like(p_state_sha,'^[0-9a-f]{64}$') or
       not regexp_like(p_frame_sha,'^[0-9a-f]{64}$') then
      raise_application_error(-20867,'invalid finalized command SHA');end if;
    update tic_commands set state_sha=p_state_sha,frame_sha=p_frame_sha
      where session_token=p_session and lineage=p_lineage and command_seq=p_seq;
    if sql%rowcount<>1 then raise_application_error(-20867,'missing finalized command');end if;
  end;
end doom_command_ledger;
/
