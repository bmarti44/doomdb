whenever sqlerror exit failure rollback

create or replace function doom_unified_actor_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_state_map_sha in varchar2)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.load(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_unified_actor_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_mode in varchar2,p_tic in number,p_command_seq in number,p_rng in number,
  p_next_mobj in number,p_next_event in number)
return raw as language java name
  'DoomUnifiedActorStateBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,java.lang.String,long,long,int,int,int) return byte[]';
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
create or replace function doom_unified_actor_last_error return varchar2 as
language java name 'DoomUnifiedActorStateBench.lastError() return java.lang.String';
/
create or replace function doom_unified_actor_benchmark(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_mode in varchar2,
  p_tic in number,p_command_seq in number,p_rng in number,p_next_mobj in number,
  p_next_event in number,p_targets in clob,p_iterations in number)
return varchar2 as language java name
  'DoomUnifiedActorStateBench.benchmark(java.lang.String,java.lang.String,long,java.lang.String,long,long,int,int,int,java.sql.Clob,int) return java.lang.String';
/
