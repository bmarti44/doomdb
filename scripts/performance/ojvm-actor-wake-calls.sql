whenever sqlerror exit failure rollback

create or replace function doom_actor_wake_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_snapshot in clob)
return varchar2 as language java name
  'DoomActorWakeBench.load(java.lang.String,java.lang.String,long,java.sql.Clob) return java.lang.String';
/
create or replace function doom_actor_wake_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_player_x in number,p_player_y in number,p_sound in number,
  p_player_target in number,p_first_event_ordinal in number)
return raw as language java name
  'DoomActorWakeBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,oracle.sql.NUMBER,oracle.sql.NUMBER,int,int,int) return byte[]';
/
create or replace function doom_actor_wake_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomActorWakeBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_actor_wake_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomActorWakeBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_actor_wake_last_error return varchar2 as
language java name 'DoomActorWakeBench.lastError() return java.lang.String';
/
