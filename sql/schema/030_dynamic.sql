create table game_sessions (
  session_token varchar2(32) not null,
  game_mode varchar2(16) not null,
  skill number(1) not null,
  current_tic number(12) not null,
  rng_cursor number(3) not null,
  map_status varchar2(16) not null,
  paused number(1) not null,
  menu_state varchar2(32) not null,
  automap_state varchar2(16) not null,
  current_player_id number(10),
  save_lineage varchar2(64) not null,
  last_command_seq number(12) not null,
  expires_at timestamp with time zone not null,
  created_at timestamp with time zone not null,
  constraint game_sessions_pk primary key (session_token),
  constraint game_sessions_token_ck check (regexp_like(session_token, '^[0-9a-f]{32}$')),
  constraint game_sessions_mode_ck check (game_mode in ('MENU','GAME','AUTOMAP','INTERMISSION','DEAD')),
  constraint game_sessions_skill_ck check (skill between 1 and 5),
  constraint game_sessions_num_ck check (current_tic >= 0 and rng_cursor between 0 and 255 and last_command_seq >= 0),
  constraint game_sessions_bool_ck check (paused in (0,1)),
  constraint game_sessions_expiry_ck check (expires_at > created_at)
);

create table players (
  session_token varchar2(32) not null,
  player_id number(10) not null,
  x number not null, y number not null, z number not null,
  momentum_x number not null, momentum_y number not null, momentum_z number not null,
  angle number not null, view_height number not null, view_bob number not null,
  health number(10) not null, armor number(10) not null, armor_type number(1) not null,
  blue_key number(1) not null, yellow_key number(1) not null, red_key number(1) not null,
  ammo_bullets number(10) not null, ammo_shells number(10) not null,
  ammo_rockets number(10) not null, ammo_cells number(10) not null,
  weapon_mask number(10) not null, selected_weapon varchar2(32) not null,
  power_invulnerability number(10) not null, power_invisibility number(10) not null,
  power_ironfeet number(10) not null, power_lightamp number(10) not null,
  kill_count number(10) not null, item_count number(10) not null, secret_count number(10) not null,
  alive number(1) not null,
  constraint players_pk primary key (session_token, player_id),
  constraint players_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint players_weapon_fk foreign key (selected_weapon) references doom_weapon_def (weapon_id),
  constraint players_id_ck check (player_id >= 0),
  constraint players_angle_ck check (angle >= 0 and angle < 360),
  constraint players_health_ck check (health >= 0 and armor >= 0 and armor_type between 0 and 2),
  constraint players_keys_ck check (blue_key in (0,1) and yellow_key in (0,1) and red_key in (0,1)),
  constraint players_ammo_ck check (ammo_bullets >= 0 and ammo_shells >= 0 and ammo_rockets >= 0 and ammo_cells >= 0),
  constraint players_power_ck check (power_invulnerability >= 0 and power_invisibility >= 0 and power_ironfeet >= 0 and power_lightamp >= 0),
  constraint players_count_ck check (kill_count >= 0 and item_count >= 0 and secret_count >= 0),
  constraint players_alive_ck check (alive in (0,1))
);

alter table game_sessions add constraint game_sessions_player_fk
  foreign key (session_token, current_player_id) references players (session_token, player_id)
  deferrable initially deferred;

create table mobjs (
  session_token varchar2(32) not null,
  mobj_id number(12) not null,
  thing_type number(10) not null,
  state_id varchar2(64) not null,
  state_tics number(10) not null,
  x number not null, y number not null, z number not null,
  momentum_x number not null, momentum_y number not null, momentum_z number not null,
  angle number not null, radius number not null, height number not null,
  health number(10) not null, flags number(12) not null,
  target_mobj_id number(12), tracer_mobj_id number(12),
  reaction_time number(10) not null, spawn_thing_id number(10),
  constraint mobjs_pk primary key (session_token, mobj_id),
  constraint mobjs_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint mobjs_type_fk foreign key (thing_type) references doom_thing_type_def (thing_type),
  constraint mobjs_state_fk foreign key (state_id) references doom_state_def (state_id),
  constraint mobjs_target_fk foreign key (session_token, target_mobj_id) references mobjs (session_token, mobj_id) deferrable initially deferred,
  constraint mobjs_tracer_fk foreign key (session_token, tracer_mobj_id) references mobjs (session_token, mobj_id) deferrable initially deferred,
  constraint mobjs_spawn_fk foreign key (spawn_thing_id) references doom_map_thing (thing_id),
  constraint mobjs_num_ck check (mobj_id >= 0 and state_tics >= -1 and angle >= 0 and angle < 360 and radius >= 0 and height >= 0 and health >= 0 and flags >= 0 and reaction_time >= 0)
);

create table sector_state (
  session_token varchar2(32) not null,
  sector_id number(10) not null,
  floor_height number not null,
  ceiling_height number not null,
  light_level number(3) not null,
  light_timer number(10),
  secret_found number(1) not null,
  damage_clock number(10) not null,
  constraint sector_state_pk primary key (session_token, sector_id),
  constraint sector_state_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint sector_state_sector_fk foreign key (sector_id) references doom_map_sector (sector_id),
  constraint sector_state_height_ck check (ceiling_height >= floor_height),
  constraint sector_state_light_ck check (light_level between 0 and 255),
  constraint sector_state_num_ck check (
    secret_found in (0,1) and damage_clock >= 0 and
    (light_timer is null or light_timer >= 0))
);

create table line_state (
  session_token varchar2(32) not null,
  linedef_id number(10) not null,
  trigger_count number(10) not null,
  switch_on number(1) not null,
  constraint line_state_pk primary key (session_token, linedef_id),
  constraint line_state_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint line_state_line_fk foreign key (linedef_id) references doom_map_linedef (linedef_id),
  constraint line_state_num_ck check (trigger_count >= 0 and switch_on in (0,1))
);

create table active_movers (
  session_token varchar2(32) not null,
  mover_id number(10) not null,
  sector_id number(10) not null,
  plane varchar2(8) not null,
  direction number(1) not null,
  speed number not null,
  target_height number not null,
  wait_tics number(10) not null,
  timer_tics number(10) not null,
  mover_kind varchar2(24) not null,
  origin_height number not null,
  source_linedef_id number(10) not null,
  constraint active_movers_pk primary key (session_token, mover_id),
  constraint active_movers_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint active_movers_sector_fk foreign key (sector_id) references doom_map_sector (sector_id),
  constraint active_movers_line_fk foreign key (source_linedef_id) references doom_map_linedef (linedef_id),
  constraint active_movers_plane_ck check (plane in ('FLOOR','CEILING')),
  constraint active_movers_direction_ck check (direction in (-1,0,1)),
  constraint active_movers_kind_ck check (mover_kind in ('DOOR_OPEN','DOOR_RAISE','FLOOR_LOWER','LIFT')),
  constraint active_movers_num_ck check (speed > 0 and wait_tics >= 0 and timer_tics >= 0)
);

create table active_switches (
  session_token varchar2(32) not null,
  linedef_id number(10) not null,
  timer_tics number(10) not null,
  restore_texture varchar2(32) not null,
  constraint active_switches_pk primary key (session_token, linedef_id),
  constraint active_switches_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint active_switches_line_fk foreign key (linedef_id) references doom_map_linedef (linedef_id),
  constraint active_switches_timer_ck check (timer_tics >= 0)
);

create table tic_commands (
  session_token varchar2(32) not null,
  command_seq number(12) not null,
  tic number(12) not null,
  command_ordinal number(1) not null,
  turn number(1) not null, forward_move number(1) not null, strafe number(1) not null,
  run number(1) not null, fire number(1) not null, use_action number(1) not null,
  weapon_slot number(1) not null, pause_toggle number(1) not null, automap_toggle number(1) not null,
  menu_action varchar2(32) not null,
  -- Oracle stores JSON's empty string as SQL NULL; canonical serialization
  -- restores it to "" at the transaction boundary.
  cheat_code varchar2(32),
  command_sha varchar2(64) not null,
  constraint tic_commands_pk primary key (session_token, command_seq),
  constraint tic_commands_tic_uq unique (session_token, tic, command_ordinal),
  constraint tic_commands_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint tic_commands_seq_ck check (command_seq > 0 and tic >= 0 and command_ordinal between 0 and 3),
  constraint tic_commands_axis_ck check (turn between -1 and 1 and forward_move between -1 and 1 and strafe between -1 and 1),
  constraint tic_commands_bool_ck check (run in (0,1) and fire in (0,1) and use_action in (0,1) and pause_toggle in (0,1) and automap_toggle in (0,1)),
  constraint tic_commands_weapon_ck check (weapon_slot between 0 and 9),
  constraint tic_commands_sha_ck check (regexp_like(command_sha, '^[0-9a-f]{64}$'))
);

create table game_events (
  session_token varchar2(32) not null,
  tic number(12) not null,
  event_ordinal number(10) not null,
  event_type varchar2(32) not null,
  actor_mobj_id number(12),
  target_mobj_id number(12),
  number_value number,
  text_value varchar2(4000),
  constraint game_events_pk primary key (session_token, tic, event_ordinal),
  constraint game_events_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint game_events_tic_ck check (tic >= 0 and event_ordinal >= 0)
);

create table audio_events (
  session_token varchar2(32) not null,
  tic number(12) not null,
  event_ordinal number(10) not null,
  sound_id varchar2(32) not null,
  volume number(3) not null,
  separation number(3) not null,
  constraint audio_events_pk primary key (session_token, tic, event_ordinal),
  constraint audio_events_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint audio_events_sound_fk foreign key (sound_id) references doom_sound (sound_id),
  constraint audio_events_tic_ck check (tic >= 0 and event_ordinal >= 0),
  constraint audio_events_mix_ck check (volume between 0 and 255 and separation between 0 and 255)
);

create table step_responses (
  session_token varchar2(32) not null,
  first_seq number(12) not null,
  last_seq number(12) not null,
  command_sha varchar2(64) not null,
  first_tic number(12) not null,
  last_tic number(12) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  response_blob blob not null,
  constraint step_responses_pk primary key (session_token, first_seq, last_seq, command_sha),
  constraint step_responses_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint step_responses_range_ck check (first_seq > 0 and last_seq >= first_seq and first_tic >= 0 and last_tic >= first_tic),
  constraint step_responses_sha_ck check (regexp_like(command_sha, '^[0-9a-f]{64}$') and regexp_like(state_sha, '^[0-9a-f]{64}$') and regexp_like(frame_sha, '^[0-9a-f]{64}$'))
);

create table state_history (
  session_token varchar2(32) not null,
  tic number(12) not null,
  first_command_seq number(12) not null,
  last_command_seq number(12) not null,
  state_sha varchar2(64) not null,
  snapshot_blob blob not null,
  constraint state_history_pk primary key (session_token, tic),
  constraint state_history_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint state_history_range_ck check (tic >= 0 and first_command_seq >= 0 and last_command_seq >= first_command_seq),
  constraint state_history_sha_ck check (regexp_like(state_sha, '^[0-9a-f]{64}$'))
);

create table save_slots (
  session_token varchar2(32) not null,
  slot_number number(2) not null,
  saved_tic number(12) not null,
  lineage varchar2(64) not null,
  state_sha varchar2(64) not null,
  snapshot_blob blob not null,
  constraint save_slots_pk primary key (session_token, slot_number),
  constraint save_slots_session_fk foreign key (session_token) references game_sessions (session_token) on delete cascade,
  constraint save_slots_slot_ck check (slot_number between 0 and 99 and saved_tic >= 0),
  constraint save_slots_sha_ck check (regexp_like(state_sha, '^[0-9a-f]{64}$'))
);

create global temporary table frame_column (
  session_token varchar2(32) not null,
  column_no number(3) not null,
  constraint frame_column_pk primary key (session_token, column_no),
  constraint frame_column_no_ck check (column_no between 0 and 319)
) on commit delete rows;

-- One exact analytic R1 hit stream is shared by all R2 consumers during an API
-- frame. Direct renderer calls fall back to DOOM_R1_HIT_ROWS when this staging
-- relation is empty.
create global temporary table frame_r1_hit (
  session_token varchar2(32) not null,
  player_id number(10) not null,
  column_no number(3) not null,
  player_x number not null,player_y number not null,player_z number not null,
  angle_degrees number not null,angle_radians binary_double not null,
  direction_x binary_double not null,direction_y binary_double not null,
  plane_x binary_double not null,plane_y binary_double not null,
  cam_x number not null,ray_x binary_double not null,ray_y binary_double not null,
  linedef_id number(10) not null,seg_id number(10) not null,
  seg_direction number(1) not null,determinant binary_double not null,
  t_numerator number not null,u_numerator binary_double not null,
  facing_side number(1) not null,right_sidedef_id number(10),
  left_sidedef_id number(10),hit_t binary_double not null,
  hit_u binary_double not null,sidedef_id number(10),
  opposite_sidedef_id number(10),is_solid number(1) not null,
  hit_ordinal number not null,
  constraint frame_r1_hit_pk primary key
    (session_token,column_no,hit_ordinal),
  constraint frame_r1_hit_column_ck check(column_no between 0 and 319)
) on commit delete rows;

create global temporary table frame_world_pixel (
  session_token varchar2(32) not null,column_no number(3) not null,
  row_no number(3) not null,palette_index number(3) not null,
  layer_ordinal number(3) not null,sector_interval_ordinal number,
  constraint frame_world_pixel_pk primary key(session_token,column_no,row_no)
) on commit delete rows;

create global temporary table frame_masked_pixel (
  session_token varchar2(32) not null,column_no number(3) not null,
  row_no number(3) not null,palette_index number(3) not null,
  source_kind varchar2(16) not null,source_id number not null,
  constraint frame_masked_pixel_pk primary key(session_token,column_no,row_no)
) on commit delete rows;

-- Stable shared cardinalities prevent Oracle cardinality feedback from replacing
-- the reviewed staging plans after their first execution. Actual row counts vary
-- by pose, but remain in these fixed bounded orders of magnitude.
begin
  dbms_stats.set_table_prefs(user,'FRAME_R1_HIT',
    'GLOBAL_TEMP_TABLE_STATS','SHARED');
  dbms_stats.set_table_stats(user,'FRAME_R1_HIT',numrows=>16000,
    numblks=>256,no_invalidate=>false);
  dbms_stats.set_table_prefs(user,'FRAME_WORLD_PIXEL',
    'GLOBAL_TEMP_TABLE_STATS','SHARED');
  dbms_stats.set_table_stats(user,'FRAME_WORLD_PIXEL',numrows=>64000,
    numblks=>512,no_invalidate=>false);
  dbms_stats.set_table_prefs(user,'FRAME_MASKED_PIXEL',
    'GLOBAL_TEMP_TABLE_STATS','SHARED');
  dbms_stats.set_table_stats(user,'FRAME_MASKED_PIXEL',numrows=>8000,
    numblks=>128,no_invalidate=>false);
  dbms_stats.set_table_prefs(user,'FRAME_COLUMN',
    'GLOBAL_TEMP_TABLE_STATS','SHARED');
  dbms_stats.set_table_stats(user,'FRAME_COLUMN',numrows=>320,
    numblks=>8,no_invalidate=>false);
end;
/

create global temporary table frame_wall (
  session_token varchar2(32) not null,
  column_no number(3) not null,
  depth number not null,
  linedef_id number(10) not null,
  y0 number(3) not null, y1 number(3) not null,
  asset_id number(10), texture_x number(10),
  constraint frame_wall_pk primary key (session_token, column_no, depth, linedef_id),
  constraint frame_wall_y_ck check (column_no between 0 and 319 and y0 between 0 and 199 and y1 between y0 and 199)
) on commit delete rows;

create global temporary table frame_sprite (
  session_token varchar2(32) not null,
  column_no number(3) not null,
  depth number not null,
  mobj_id number(12) not null,
  y0 number(3) not null, y1 number(3) not null,
  asset_id number(10) not null,
  constraint frame_sprite_pk primary key (session_token, column_no, depth, mobj_id),
  constraint frame_sprite_y_ck check (column_no between 0 and 319 and y0 between 0 and 199 and y1 between y0 and 199)
) on commit delete rows;

create global temporary table frame_pixel (
  session_token varchar2(32) not null,
  column_no number(3) not null,
  row_no number(3) not null,
  palette_index number(3) not null,
  layer_ordinal number(3) not null,
  constraint frame_pixel_pk primary key (session_token, column_no, row_no),
  constraint frame_pixel_coord_ck check (column_no between 0 and 319 and row_no between 0 and 199 and palette_index between 0 and 255 and layer_ordinal >= 0)
) on commit delete rows;

create global temporary table frame_rle_run (
  session_token varchar2(32) not null,
  column_no number(3) not null,
  y0 number(3) not null,
  run_length number(3) not null,
  palette_index number(3) not null,
  constraint frame_rle_run_pk primary key (session_token, column_no, y0),
  constraint frame_rle_run_ck check (column_no between 0 and 319 and y0 between 0 and 199 and run_length between 1 and 200 and y0 + run_length <= 200 and palette_index between 0 and 255)
) on commit delete rows;
