whenever sqlerror exit failure rollback

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
