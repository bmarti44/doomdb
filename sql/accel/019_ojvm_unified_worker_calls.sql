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
