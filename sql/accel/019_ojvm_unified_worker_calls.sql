-- Stable retained-simulation call specs used by the default-off production
-- worker.  The deployment runner loads the matching Java classes atomically.
whenever sqlerror exit failure rollback

create or replace function doom_unified_recover_sql_renderer(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_state_map_sha in varchar2,p_renderer_snapshot in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.recoverSqlAndRenderer(java.lang.String,java.lang.String,long,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_actor_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_mode in varchar2,p_tic in number,
  p_command_seq in number,p_rng in number,p_next_mobj in number,
  p_next_event in number)
return raw as language java name
  'DoomUnifiedActorStateBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,java.lang.String,long,long,int,int,int) return byte[]';
/
create or replace function doom_unified_command_tic_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTic(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_command_projectiles_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_projectile_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicWithProjectiles(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[]) return byte[]';
/
create or replace function doom_unified_owner_projectiles_ready(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return number as language java name
  'DoomUnifiedActorStateBench.ownerProjectilesReady(java.lang.String,java.lang.String,long) return int';
/
create or replace function doom_unified_command_retained_projectiles(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicRetainedProjectiles(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_command_actions_projectiles(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_projectile_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicActionsWithProjectiles(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_actions_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicActions(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_command_actions_retained(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicActionsRetainedProjectiles(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_command_world_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicWorld(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_world_projectiles(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_projectile_pack in raw,p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicWorldProjectiles(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_world_retained(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicWorldRetained(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_actions_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicActionsWorld(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_actions_world_projectiles(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_projectile_pack in raw,p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicActionsWorldProjectiles(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_actions_world_retained(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw,
  p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTicActionsWorldRetained(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[],byte[]) return byte[]';
/
create or replace function doom_unified_command_pre_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_command_seq in number,
  p_rng in number,p_next_mobj in number,p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandPreWorld(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_pre_world_requires_advance(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return number as language java name
  'DoomUnifiedActorStateBench.preWorldRequiresAdvance(java.lang.String,java.lang.String,long,java.lang.String) return int';
/
create or replace function doom_unified_command_post_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_projectile_pack in raw,p_retained_projectiles in number)
return raw as language java name
  'DoomUnifiedActorStateBench.finishCommandPostWorld(java.lang.String,java.lang.String,long,java.lang.String,byte[],int) return byte[]';
/
create or replace function doom_unified_command_post_world_passive(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_projectile_pack in raw,p_world_pack in raw,
  p_retained_projectiles in number)
return raw as language java name
  'DoomUnifiedActorStateBench.finishCommandPostWorldPassive(java.lang.String,java.lang.String,long,java.lang.String,byte[],byte[],int) return byte[]';
/
create or replace function doom_unified_sync_pending_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_world_pack in raw)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.syncPendingWorld(java.lang.String,java.lang.String,long,java.lang.String,byte[]) return java.lang.String';
/
create or replace function doom_unified_refresh_pending_state(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.refreshPendingStateTemplate(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_actor_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_actor_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_owner_sql_parity(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.ownerSqlParity(java.lang.String,java.lang.String,long) return java.lang.String';
/
create or replace function doom_unified_actor_tic_ns return number as language java name
  'DoomUnifiedActorStateBench.lastActorTicNanos() return long';
/
create or replace function doom_unified_projectile_ns return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileNanos() return long';
/
create or replace function doom_unified_projectile_setup_ns return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileSetupNanos() return long';
/
create or replace function doom_unified_projectile_wall_ns return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileWallNanos() return long';
/
create or replace function doom_unified_projectile_target_ns return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileTargetNanos() return long';
/
create or replace function doom_unified_projectile_impact_ns return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileImpactNanos() return long';
/
create or replace function doom_unified_projectile_count return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileCount() return int';
/
create or replace function doom_unified_projectile_target_checks return number as language java name
  'DoomUnifiedActorStateBench.lastProjectileTargetChecks() return int';
/
create or replace function doom_unified_chase_ns return number as language java name
  'DoomUnifiedActorStateBench.lastChaseNanos() return long';
/
create or replace function doom_unified_actor_loop_ns return number as language java name
  'DoomUnifiedActorStateBench.lastActorLoopNanos() return long';
/
create or replace function doom_unified_delta_encode_ns return number as language java name
  'DoomUnifiedActorStateBench.lastDeltaEncodeNanos() return long';
/
create or replace function doom_unified_command_encode_ns return number as language java name
  'DoomUnifiedActorStateBench.lastCommandEncodeNanos() return long';
/
create or replace function doom_unified_state_fill(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.fillPendingState(java.lang.String,java.lang.String,long,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_state_total_ns return number as language java name
  'DoomUnifiedActorStateBench.lastStateTotalNanos() return long';
/
create or replace function doom_unified_state_encode_ns return number as language java name
  'DoomUnifiedActorStateBench.lastStateEncodeNanos() return long';
/
create or replace function doom_unified_state_blob_ns return number as language java name
  'DoomUnifiedActorStateBench.lastStateBlobNanos() return long';
/
create or replace function doom_unified_state_compare_ns return number as language java name
  'DoomUnifiedActorStateBench.lastStateCompareNanos() return long';
/
create or replace function doom_unified_state_object_encode_ns return number as language java name
  'DoomUnifiedActorStateBench.lastStateObjectEncodeNanos() return long';
/
create or replace function doom_unified_state_changed return number as language java name
  'DoomUnifiedActorStateBench.lastStateChanged() return int';
/
create or replace function doom_unified_state_reused return number as language java name
  'DoomUnifiedActorStateBench.lastStateReused() return int';
/
create or replace function doom_unified_state_removed return number as language java name
  'DoomUnifiedActorStateBench.lastStateRemoved() return int';
/
create or replace function doom_unified_history_fill(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_tic in number,p_frontier in number,
  p_command_sha in varchar2,p_event_sha in varchar2,p_state_sha in varchar2,
  p_frame_sha in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.fillPendingHistory(java.lang.String,java.lang.String,long,java.lang.String,long,long,java.lang.String,java.lang.String,java.lang.String,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_history_total_ns return number as language java name
  'DoomUnifiedActorStateBench.lastHistoryTotalNanos() return long';
/
create or replace function doom_unified_history_encode_ns return number as language java name
  'DoomUnifiedActorStateBench.lastHistoryEncodeNanos() return long';
/
create or replace function doom_unified_history_blob_ns return number as language java name
  'DoomUnifiedActorStateBench.lastHistoryBlobNanos() return long';
/
create or replace function doom_unified_render_pending(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_state_sha in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.renderPending(java.lang.String,java.lang.String,long,java.lang.String,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_render_pending_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_world_pack in raw,p_state_sha in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.renderPendingWorld(java.lang.String,java.lang.String,long,java.lang.String,byte[],java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_render_pack(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_world_pack in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.pendingRenderPack(java.lang.String,java.lang.String,long,java.lang.String,byte[]) return byte[]';
/
create or replace function doom_retained_render_pack(
  p_session in varchar2,p_generation in number,p_request in varchar2,
  p_render_pack in raw,p_state_sha in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomRetainedRenderSceneBench.stageOwnerPack(java.lang.String,long,java.lang.String,byte[],java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_retained_render_accept(
  p_session in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomRetainedRenderSceneBench.acceptOwnerTic(java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_retained_render_discard(
  p_session in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomRetainedRenderSceneBench.discardOwnerTic(java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_actor_recovery_status(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.recoveryStatus(java.lang.String,java.lang.String,long) return java.lang.String';
/
create or replace function doom_unified_actor_last_error return varchar2 as
language java name
  'DoomUnifiedActorStateBench.lastError() return java.lang.String';
/
create or replace function doom_retained_render_recovery_status(
  p_session in varchar2,p_generation in number) return varchar2 as
language java name
  'DoomRetainedRenderSceneBench.recoveryStatus(java.lang.String,long) return java.lang.String';
/
