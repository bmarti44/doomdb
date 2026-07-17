whenever sqlerror exit failure rollback

create or replace function doom_unified_actor_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_state_map_sha in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.load(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
-- The three partial recovery functions below are diagnostic primitives. The
-- production worker must call DOOM_UNIFIED_RECOVER_SQL_RENDERER or
-- DOOM_UNIFIED_RECOVER_CHECKPOINT_RENDERER so neither retained half stays stale.
create or replace function doom_unified_actor_force_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_state_map_sha in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.forceLoad(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_actor_force_restore(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_state_map_sha in varchar2,
  p_checkpoint in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.forceRestore(java.lang.String,java.lang.String,long,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_actor_recovery_status(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.recoveryStatus(java.lang.String,java.lang.String,long) return java.lang.String';
/
create or replace function doom_unified_recover_sql_renderer(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_state_map_sha in varchar2,
  p_renderer_snapshot in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.recoverSqlAndRenderer(java.lang.String,java.lang.String,long,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_recover_checkpoint_renderer(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_state_map_sha in varchar2,
  p_checkpoint in blob,p_renderer_snapshot in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.recoverCheckpointAndRenderer(java.lang.String,java.lang.String,long,java.lang.String,java.sql.Blob,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_actor_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_mode in varchar2,p_tic in number,p_command_seq in number,p_rng in number,
  p_next_mobj in number,p_next_event in number)
return raw as language java name
  'DoomUnifiedActorStateBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,java.lang.String,long,long,int,int,int) return byte[]';
/
create or replace function doom_unified_command_tic_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_tic in number,p_command_seq in number,p_rng in number,p_next_mobj in number,
  p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandTic(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_command_pre_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_tic in number,p_command_seq in number,p_rng in number,p_next_mobj in number,
  p_next_event in number,p_command in raw)
return raw as language java name
  'DoomUnifiedActorStateBench.prepareCommandPreWorld(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,byte[]) return byte[]';
/
create or replace function doom_unified_command_post_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_projectile_pack in raw,p_retained_projectiles in number)
return raw as language java name
  'DoomUnifiedActorStateBench.finishCommandPostWorld(java.lang.String,java.lang.String,long,java.lang.String,byte[],int) return byte[]';
/
create or replace function doom_unified_actor_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_actor_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_render_pending(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_state_sha in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.renderPending(java.lang.String,java.lang.String,long,java.lang.String,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_render_pending_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_geometry_pack in raw,p_state_sha in varchar2,p_payload in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.renderPendingWorld(java.lang.String,java.lang.String,long,java.lang.String,byte[],java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_sync_pending_world(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_geometry_pack in raw)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.syncPendingWorld(java.lang.String,java.lang.String,long,java.lang.String,byte[]) return java.lang.String';
/
create or replace function doom_unified_refresh_state_template(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.refreshPendingStateTemplate(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_refresh_pending_state(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.refreshPendingStateTemplate(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_render_upserts return number as language java name
  'DoomUnifiedActorStateBench.lastRenderUpserts() return int';
/
create or replace function doom_unified_render_removes return number as language java name
  'DoomUnifiedActorStateBench.lastRenderRemoves() return int';
/
create or replace function doom_unified_actor_last_error return varchar2 as
language java name 'DoomUnifiedActorStateBench.lastError() return java.lang.String';
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
create or replace function doom_unified_actor_benchmark(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_mode in varchar2,
  p_tic in number,p_command_seq in number,p_rng in number,p_next_mobj in number,
  p_next_event in number,p_targets in clob,p_iterations in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.benchmark(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,java.sql.Clob,int) return java.lang.String';
/
create or replace function doom_unified_world_checkpoint(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_output in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.worldCheckpoint(java.lang.String,java.lang.String,long,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_world_restore(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_input in blob)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.worldRestore(java.lang.String,java.lang.String,long,java.sql.Blob) return java.lang.String';
/
create or replace function doom_unified_world_sql_parity(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.worldSqlParity(java.lang.String,java.lang.String,long) return java.lang.String';
/
create or replace function doom_unified_owner_sql_parity(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.ownerSqlParity(java.lang.String,java.lang.String,long) return java.lang.String';
/
create or replace function doom_unified_world_spawn_remove(
  p_session in varchar2,p_lineage in varchar2,p_generation in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.worldSpawnRemoveProbe(java.lang.String,java.lang.String,long) return java.lang.String';
/
create or replace function doom_unified_tic_accept_benchmark(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_iterations in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.benchmarkAcceptedTics(java.lang.String,java.lang.String,long,int) return java.lang.String';
/
create or replace function doom_unified_command_tic_benchmark(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_iterations in number,
  p_warmups in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.benchmarkAcceptedCommandTics(java.lang.String,java.lang.String,long,int,int) return java.lang.String';
/
