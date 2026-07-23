declare
  procedure drop_object(p_ddl varchar2, p_missing_code number) is
  begin
    execute immediate p_ddl;
  exception
    when others then
      if sqlcode != p_missing_code then raise; end if;
  end;
begin
  begin dbms_scheduler.drop_job('DOOM_UNIFIED_WORKER_JOB',true); exception when others then null; end;
  begin dbms_scheduler.drop_job('DOOM_EXPIRED_SESSION_PURGE',true); exception when others then null; end;
  for l_slot in 1..4 loop
    begin
      dbms_scheduler.drop_job(
        'DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00'),true);
    exception when others then null;end;
    begin
      dbms_scheduler.drop_job(
        'DOOM_RENDER_WORKER_'||to_char(l_slot,'FM00'),true);
    exception when others then null;end;
  end loop;
  begin dbms_aqadm.stop_queue('DOOM_RENDER_TASK_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_RENDER_TASK_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_RENDER_TASK_QT',true); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_UNIFIED_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.stop_queue('DOOM_UNIFIED_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_UNIFIED_REQUEST_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue('DOOM_UNIFIED_RESPONSE_Q'); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_UNIFIED_REQUEST_QT',true); exception when others then null; end;
  begin dbms_aqadm.drop_queue_table('DOOM_UNIFIED_RESPONSE_QT',true); exception when others then null; end;
  drop_object('drop property graph doom_sector_graph', -42421);
  drop_object('drop package doom_worker_api', -4043);
  drop_object('drop package doom_mocha_bridge', -4043);
  drop_object('drop package doom_match_worker', -4043);
  drop_object('drop package doom_mle_authority_delta', -4043);
  drop_object('drop package doom_mle_transition_transport', -4043);
  drop_object('drop package doom_unified_worker', -4043);
  drop_object('drop package doom_session_cleanup', -4043);
  drop_object('drop package doom_render_worker', -4043);
  drop_object('drop package doom_unified_delta_apply', -4043);
  drop_object('drop function doom_unified_recover_sql_renderer', -4043);
  drop_object('drop function doom_unified_actor_prepare', -4043);
  drop_object('drop function doom_unified_command_tic_prepare', -4043);
  drop_object('drop function doom_unified_command_projectiles_prepare', -4043);
  drop_object('drop function doom_unified_command_retained_projectiles', -4043);
  drop_object('drop function doom_unified_command_post_world_passive', -4043);
  drop_object('drop function doom_unified_pre_world_requires_advance', -4043);
  drop_object('drop function doom_unified_owner_projectiles_ready', -4043);
  drop_object('drop function doom_unified_actor_accept', -4043);
  drop_object('drop function doom_unified_actor_discard', -4043);
  drop_object('drop function doom_unified_render_pending', -4043);
  drop_object('drop function doom_unified_actor_recovery_status', -4043);
  drop_object('drop function doom_unified_actor_last_error', -4043);
  drop_object('drop function doom_retained_render_recovery_status', -4043);
  drop_object('drop procedure doom_renderer_snapshot_fill', -4043);
  drop_object('drop procedure doom_renderer_delta_fill', -4043);
  drop_object('drop package doom_api', -4043);
  drop_object('drop function doom_r2_staged_masked_pixels', -4043);
  drop_object('drop function doom_r2_staged_masked_candidates', -4043);
  drop_object('drop function doom_r2_staged_pixels', -4043);
  drop_object('drop function doom_r2_staged_sector_intervals', -4043);
  drop_object('drop function doom_r2_staged_portal_hits', -4043);
  drop_object('drop function doom_r2_presentation', -4043);
  drop_object('drop function doom_r2_masked_pixels', -4043);
  drop_object('drop function doom_r2_masked_candidates', -4043);
  drop_object('drop function doom_r2_pixels', -4043);
  drop_object('drop function doom_r2_sector_intervals', -4043);
  drop_object('drop function doom_r2_portal_hits', -4043);
  drop_object('drop function doom_r1_nearest', -4043);
  drop_object('drop function doom_r1_hits', -4043);
  drop_object('drop function doom_r1_rays', -4043);
  drop_object('drop function doom_r1_staged_nearest', -4043);
  drop_object('drop function doom_r1_staged_hits', -4043);
  drop_object('drop function doom_r1_staged_rays', -4043);
    drop_object('drop function doom_player_move', -4043);
    drop_object('drop function doom_player_move_payload', -4043);
    drop_object('drop function doom_portal_transition_ok', -4043);
    drop_object('drop function doom_sweep_contact', -4043);
  drop_object('drop function doom_thin_portal_graze', -4043);
  drop_object('drop package doom_world_machines', -4043);
  drop_object('drop package doom_combat', -4043);
  drop_object('drop package doom_monsters', -4043);
  drop_object('drop package doom_audio', -4043);
  drop_object('drop package doom_tic_tx', -4043);
  drop_object('drop package doom_command_ledger', -4043);
  drop_object('drop package doom_canonical_state', -4043);
  drop_object('drop package doom_history', -4043);
  drop_object('drop package doom_retained_projectiles', -4043);
  drop_object('drop procedure doom_bsp_build_kernel_pack', -4043);
  drop_object('drop function doom_bsp_build_kernel_pack_java', -4043);
  drop_object('drop function doom_mocha_iwad_probe', -4043);
  drop_object('drop function doom_mocha_initialize', -4043);
  drop_object('drop function doom_mocha_canonical_state', -4043);
  drop_object('drop function doom_mocha_canonical_blob', -4043);
  drop_object('drop function doom_mocha_step_command_simulation', -4043);
  drop_object('drop function doom_mocha_multiplayer_sim_step', -4043);
  drop_object('drop function doom_mocha_multiplayer_sim_membership_step', -4043);
  drop_object('drop function doom_mocha_multiplayer_sim_init', -4043);
  drop_object('drop function doom_mocha_multiplayer_sim_init_skill', -4043);
  drop_object('drop function doom_mocha_step', -4043);
  drop_object('drop function doom_mocha_step_simulation', -4043);
  drop_object('drop function doom_mocha_step_frame', -4043);
  drop_object('drop function doom_mocha_step_controls_frame', -4043);
  drop_object('drop function doom_mocha_step_controls_payload', -4043);
  drop_object('drop function doom_mocha_current_payload', -4043);
  drop_object('drop function doom_mocha_payload_plain', -4043);
  drop_object('drop function doom_mocha_save', -4043);
  drop_object('drop function doom_mocha_load', -4043);
  drop_object('drop function doom_mocha_reconstruct', -4043);
  drop_object('drop function doom_mocha_frame', -4043);
  drop_object('drop function doom_mocha_new_game', -4043);
  drop_object('drop function doom_mocha_dispose', -4043);
  drop_object('drop function doom_mocha_benchmark', -4043);
  drop_object('drop function doom_mocha_probe', -4043);
  drop_object('drop function doom_mocha_multiplayer_probe', -4043);
  drop_object('drop function doom_mocha_multiplayer_benchmark', -4043);
  drop_object('drop function doom_mocha_multiplayer_new_game', -4043);
  drop_object('drop function doom_mocha_multiplayer_step', -4043);
  drop_object('drop function doom_mocha_multiplayer_reconstruct', -4043);
  drop_object('drop view doom_r2_masked_candidate_rows', -942);
  drop_object('drop view doom_api_presentation_rows', -942);
  drop_object('drop view doom_r2_staged_masked_candidate_rows', -942);
  drop_object('drop view doom_r2_world_sprite_catalog', -942);
  drop_object('drop view doom_r2_sprite_patch_metrics', -942);
  drop_object('drop view doom_r2_staged_pixel_rows', -942);
  drop_object('drop view doom_r2_pixel_rows', -942);
  drop_object('drop view doom_r2_animation_frames', -942);
  drop_object('drop view doom_r2_sector_interval_rows', -942);
  drop_object('drop view doom_r2_staged_sector_interval_rows', -942);
  drop_object('drop view doom_r2_portal_hit_rows', -942);
  drop_object('drop view doom_r2_staged_portal_hit_rows', -942);
  drop_object('drop view doom_r2_hit_geometry', -942);
  drop_object('drop view doom_r2_staged_hit_geometry', -942);
  drop_object('drop view doom_r1_render_hit_rows', -942);
  drop_object('drop view doom_r1_staged_segment_bound_rows', -942);
  drop_object('drop view doom_r1_staged_hit_rows', -942);
  drop_object('drop view doom_r1_staged_ray_rows', -942);
  drop_object('drop view doom_r1_hit_rows', -942);
  drop_object('drop view doom_r1_ray_rows', -942);
  drop_object('drop view doom_vertex', -942);
  drop_object('drop view doom_map_vertex', -942);
  drop_object('drop view doom_map_linedef', -942);

  for t in (
    select column_value table_name
      from table(sys.odcivarchar2list(
        'FRAME_RLE_RUN','FRAME_PIXEL','FRAME_MASKED_PIXEL','FRAME_WORLD_PIXEL',
        'FRAME_SPRITE','FRAME_WALL','FRAME_SECTOR_INTERVAL','FRAME_PORTAL_HIT',
        'FRAME_R1_HIT','FRAME_RENDER_SEG_BOUND','FRAME_COLUMN',
        'REPLAY_CURSORS','HISTORY_HEADS','SAVE_SLOTS','STATE_HISTORY','STEP_RESPONSES','AUDIO_EVENTS','GAME_EVENTS',
        'DOOM_MATCH_POLL_LEASE','DOOM_MATCH_POLL_CAPACITY','DOOM_MATCH_SLOW_CALL','DOOM_MATCH_TRANSITION','DOOM_MATCH_ROUTE_TRACE','DOOM_MATCH_STANDBY_CONTROL','DOOM_MATCH_WORKER_CONTROL','DOOM_MATCH_CHECKPOINT','DOOM_MATCH_FRAME','DOOM_MATCH_INPUT_EVENT','DOOM_MATCH_COMMAND','DOOM_MATCH_TIC','DOOM_MATCH_MEMBER','DOOM_MATCH',
        'DOOM_MOCHA_FRAME_LEDGER','DOOM_MOCHA_INITIAL_FRAME','DOOM_MOCHA_SAVE_SLOT','DOOM_MOCHA_FRAME_CACHE',
        'DOOM_ROUTE_TRACE','DOOM_MOCHA_COMMAND','DOOM_MOCHA_LINEAGE','DOOM_WORKER_AUDIT','DOOM_WORKER_RESULT','DOOM_WORKER_REQUEST','DOOM_WORKER_CONTROL',
        'TIC_COMMANDS','ACTIVE_SWITCHES','ACTIVE_MOVERS','LINE_STATE','SECTOR_STATE',
        'MOBJS','PLAYERS','GAME_SESSIONS','DOOM_BLOCK_LINE','DOOM_BLOCK_CELL',
        'DOOM_SECTOR_REJECT','DOOM_SECTOR_SOUND_REACH','DOOM_SECTOR_EDGE','DOOM_LOS_SEGMENT','DOOM_RNG_VALUE','DOOM_AUDIO_EVENT_DEF','DOOM_MONSTER_DEF','DOOM_PROJECTILE_DEF','DOOM_AMMO_DEF',
        'DOOM_PICKUP_DEF','DOOM_WEAPON_DEF','DOOM_THING_TYPE_DEF','DOOM_STATE_DEF',
        'DOOM_RENDER_RAY','DOOM_SCREEN_ROW','DOOM_SCREEN_COLUMN','DOOM_RENDER_PROFILE',
        'DOOM_SECTOR_SPECIAL_DEF','DOOM_LINEDEF_SPECIAL_DEF','DOOM_ENGINE_SOURCE',
        'DOOM_MUSIC','DOOM_SOUND','DOOM_SPRITE_ROTATION','DOOM_PATCH_PLACEMENT',
        'DOOM_RENDERER_ASSET_PACK','DOOM_SECTOR_RUNTIME_STATIC','DOOM_COLLISION_SEGMENT','DOOM_ASSET_BLOB','AT','DOOM_ASSET_SOURCE','DOOM_MAP_NODE',
        'DOOM_MAP_SSECTOR','DOOM_MAP_SEG','DOOM_MAP_LINEDEF','DOOM_MAP_SIDEDEF',
        'DOOM_MAP_THING','DOOM_MAP_SECTOR','DOOM_LINEDEF','DOOM_MAP_LINEDEF',
        'DOOM_VERTEX','DOOM_MAP_VERTEX','DOOM_BLOCKMAP_BYTE','DOOM_REJECT_BYTE','DOOM_COLORMAP_TEXEL',
        'DOOM_PALETTE_TEXEL','DOOM_ASSET','DOOM_ENGINE_ARTIFACT','DOOM_WAD_SOURCE','DOOM_CONFIG'))
  ) loop
    drop_object('drop table ' || t.table_name || ' cascade constraints purge', -942);
  end loop;

  delete from user_sdo_geom_metadata
   where table_name in ('DOOM_LINEDEF','FRAME_WALL','FRAME_SPRITE');
end;
/
