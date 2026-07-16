whenever sqlerror exit failure rollback

create or replace function doom_common_actor_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_snapshot in clob)
return varchar2 as language java name
  'DoomCommonActorTickBench.load(java.lang.String,java.lang.String,long,java.sql.Clob) return java.lang.String';
/
create or replace function doom_common_actor_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_player_made_sound in number,p_all_reject_hidden in number)
return raw as language java name
  'DoomCommonActorTickBench.prepareQuiet(java.lang.String,java.lang.String,long,java.lang.String,int,int) return byte[]';
/
create or replace function doom_common_actor_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomCommonActorTickBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_common_actor_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomCommonActorTickBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_common_actor_last_error return varchar2 as
language java name 'DoomCommonActorTickBench.lastError() return java.lang.String';
/
