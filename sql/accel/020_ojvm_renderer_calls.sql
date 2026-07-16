whenever sqlerror exit failure rollback

create or replace procedure doom_bsp_build_kernel_pack as
language java name 'DoomBspKernelBench.buildKernelPack()';
/

create or replace function doom_bsp_warm_kernel_pack(p_iterations in number)
return varchar2 as
language java name 'DoomBspKernelBench.warmKernelPack(int) return java.lang.String';
/

create or replace procedure doom_bsp_kernel_fill(p_payload in blob) as
language java name 'DoomBspKernelBench.renderTicZero(java.sql.Blob)';
/

create or replace function doom_bsp_render_session(
  p_session in varchar2,
  p_state_sha in varchar2,
  p_payload in blob
) return varchar2 as
language java name 'DoomBspKernelBench.renderSession(
  java.lang.String,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_bsp_render_snapshot(
  p_snapshot in blob,p_state_sha in varchar2,p_payload in blob
) return varchar2 as
language java name 'DoomBspKernelBench.renderSnapshot(
  java.sql.Blob,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_bsp_render_packed_session(
  p_session in varchar2,p_snapshot in blob,p_state_sha in varchar2,p_payload in blob
) return varchar2 as
language java name 'DoomBspKernelBench.renderPackedSession(
  java.lang.String,java.sql.Blob,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_bsp_compare_session(p_session in varchar2)
return varchar2 as
language java name 'DoomBspKernelBench.compareSessionOracle(
  java.lang.String) return java.lang.String';
/

create or replace function doom_bsp_compare_sql_payload(
  p_session in varchar2,
  p_sql_payload in blob
) return varchar2 as
language java name 'DoomBspKernelBench.compareSqlPayload(
  java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_bsp_compare_current_payload(p_sql_payload in blob)
return varchar2 as
language java name 'DoomBspKernelBench.compareCurrentSqlPayload(
  java.sql.Blob) return java.lang.String';
/

create or replace function doom_bsp_last_render_ns return number as
language java name 'DoomBspKernelBench.lastRenderNanos() return long';
/

create or replace function doom_bsp_last_codec_ns return number as
language java name 'DoomBspKernelBench.lastCodecNanos() return long';
/

create or replace function doom_bsp_last_blob_ns return number as
language java name 'DoomBspKernelBench.lastBlobNanos() return long';
/

create or replace function doom_bsp_last_bsp_ns return number as
language java name 'DoomBspKernelBench.lastBspNanos() return long';
/

create or replace function doom_bsp_last_solid_ns return number as
language java name 'DoomBspKernelBench.lastSolidNanos() return long';
/

create or replace function doom_bsp_last_portal_ns return number as
language java name 'DoomBspKernelBench.lastPortalNanos() return long';
/

create or replace function doom_bsp_last_plane_ns return number as
language java name 'DoomBspKernelBench.lastPlaneNanos() return long';
/

create or replace function doom_bsp_last_sprite_ns return number as
language java name 'DoomBspKernelBench.lastSpriteNanos() return long';
/

create or replace function doom_bsp_last_presentation_ns return number as
language java name 'DoomBspKernelBench.lastPresentationNanos() return long';
/

create or replace function doom_bsp_last_kernel_load_ns return number as
language java name 'DoomBspKernelBench.lastKernelLoadNanos() return long';
/

create or replace function doom_bsp_last_snapshot_ns return number as
language java name 'DoomBspKernelBench.lastSnapshotNanos() return long';
/

create or replace function doom_bsp_last_dynamic_failure return varchar2 as
language java name 'DoomBspKernelBench.lastDynamicFailure() return java.lang.String';
/

create or replace function doom_retained_render_load(
  p_session in varchar2,p_generation in number,p_snapshot in blob) return varchar2 as
language java name 'DoomRetainedRenderSceneBench.load(
  java.lang.String,long,java.sql.Blob) return java.lang.String';
/

create or replace function doom_retained_render_load_fenced(
  p_session in varchar2,p_generation in number,p_state_map_sha in varchar2,
  p_snapshot in blob) return varchar2 as
language java name 'DoomRetainedRenderSceneBench.loadFenced(
  java.lang.String,long,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_retained_render_update(
  p_session in varchar2,p_generation in number,p_delta in blob,
  p_state_sha in varchar2,p_payload in blob) return varchar2 as
language java name 'DoomRetainedRenderSceneBench.updateRender(
  java.lang.String,long,java.sql.Blob,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_retained_render_dtic(
  p_session in varchar2,p_generation in number,p_delta in blob,
  p_state_sha in varchar2,p_payload in blob) return varchar2 as
language java name 'DoomRetainedRenderSceneBench.updateTicRender(
  java.lang.String,long,java.sql.Blob,java.lang.String,java.sql.Blob) return java.lang.String';
/

create or replace function doom_retained_render_last_update_ns return number as
language java name 'DoomRetainedRenderSceneBench.lastUpdateNanos() return long';
/

create or replace function doom_retained_render_last_error return varchar2 as
language java name 'DoomRetainedRenderSceneBench.lastError() return java.lang.String';
/
