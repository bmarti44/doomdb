whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off

declare
  k_token constant varchar2(32) := '51515151515151515151515151515152';
  l_weapon varchar2(32);
  l_column number;
  l_hit_ordinal number;
  l_opposite_sector number;
  l_opening_bottom number;
  l_opening_top number;
  l_active number;
  l_closed number;
  l_termination number;

  procedure assert_true(p_value boolean, p_message varchar2) is
  begin
    if not p_value then
      raise_application_error(-20952, p_message);
    end if;
  end;
begin
  select min(weapon_id) into l_weapon from doom_weapon_def;
  insert into game_sessions(
    session_token, game_mode, skill, current_tic, rng_cursor, map_status,
    paused, menu_state, automap_state, current_player_id, save_lineage,
    last_command_seq, expires_at, created_at
  ) values (
    k_token, 'GAME', 3, 0, 0, 'ACTIVE', 0, 'NONE', 'OFF', null,
    'T51-DYNAMIC', 0, systimestamp + interval '1' hour, systimestamp
  );
  insert into players(
    session_token, player_id, x, y, z, momentum_x, momentum_y, momentum_z,
    angle, view_height, view_bob, health, armor, armor_type, blue_key,
    yellow_key, red_key, ammo_bullets, ammo_shells, ammo_rockets, ammo_cells,
    weapon_mask, selected_weapon, power_invulnerability, power_invisibility,
    power_ironfeet, power_lightamp, kill_count, item_count, secret_count, alive
  ) values (
    k_token, 0, -416, 256, 0, 0, 0, 0, 0, 41, 0, 100, 0, 0, 0, 0, 0,
    50, 0, 0, 0, 1, l_weapon, 0, 0, 0, 0, 0, 0, 0, 1
  );
  update game_sessions set current_player_id = 0 where session_token = k_token;

  insert into sector_state(
    session_token, sector_id, floor_height, ceiling_height, light_level,
    light_timer, secret_found, damage_clock
  )
  select k_token, sector_id, floor_height, ceiling_height, light_level,
         null, 0, 0
  from doom_map_sector;

  select column_no, hit_ordinal, opposite_sector_id,
         opening_bottom, opening_top
    into l_column, l_hit_ordinal, l_opposite_sector,
         l_opening_bottom, l_opening_top
    from table(doom_r2_portal_hits(k_token))
   where is_transition = 1
   order by column_no, hit_ordinal
   fetch first 1 row only;

  assert_true(l_opening_top > l_opening_bottom,
              'selected live portal does not have a positive opening');

  update sector_state
     set ceiling_height = floor_height
   where session_token = k_token
     and sector_id = l_opposite_sector;
  assert_true(sql%rowcount = 1, 'live opposite sector height was not updated');

  select is_active, is_closed, is_termination,
         opening_bottom, opening_top
    into l_active, l_closed, l_termination,
         l_opening_bottom, l_opening_top
    from table(doom_r2_portal_hits(k_token))
   where column_no = l_column
     and hit_ordinal = l_hit_ordinal;

  assert_true(l_active = 1, 'height-mutated portal is not active');
  assert_true(l_closed = 1 and l_termination = 1,
              'live zero-height opening did not become a solid termination');
  assert_true(l_opening_top <= l_opening_bottom,
              'live opening bounds did not follow sector state');

  rollback;
  dbms_output.put_line('PASS T5.1-DYNAMIC-SECTOR-HEIGHTS (5/5 assertions)');
end;
/
