whenever sqlerror exit failure rollback

create or replace function doom_fresh_death_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_kill_count in number,p_snapshot in clob)
return varchar2 as language java name
  'DoomFreshDeathTickBench.load(java.lang.String,java.lang.String,long,int,java.sql.Clob) return java.lang.String';
/
create or replace function doom_fresh_death_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_request in varchar2,p_next_event_ordinal in number,p_next_mobj_id in number)
return raw as language java name
  'DoomFreshDeathTickBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,int,int) return byte[]';
/
create or replace function doom_fresh_death_accept(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomFreshDeathTickBench.accept(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_fresh_death_discard(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2)
return varchar2 as language java name
  'DoomFreshDeathTickBench.discard(java.lang.String,java.lang.String,long,java.lang.String) return java.lang.String';
/
create or replace function doom_fresh_death_last_error return varchar2 as
language java name 'DoomFreshDeathTickBench.lastError() return java.lang.String';
/
