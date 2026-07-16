whenever sqlerror exit failure rollback

create or replace function doom_retained_world_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_state_map_sha in varchar2,p_output in blob)
return varchar2 as language java name
  'DoomRetainedWorldStateBench.load(java.lang.String,java.lang.String,long,java.lang.String,java.sql.Blob) return java.lang.String';
/
create or replace function doom_retained_world_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_tic in number,p_seq in number,p_rng in number,p_next_mobj in number,
  p_next_event in number,p_output in blob)
return varchar2 as language java name
  'DoomRetainedWorldStateBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,java.sql.Blob) return java.lang.String';
/
create or replace function doom_retained_world_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomRetainedWorldStateBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_retained_world_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomRetainedWorldStateBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_retained_world_last_error return varchar2 as
language java name 'DoomRetainedWorldStateBench.lastError() return java.lang.String';
/
