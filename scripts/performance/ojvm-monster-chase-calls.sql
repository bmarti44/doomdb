whenever sqlerror exit failure rollback

create or replace function doom_monster_chase_load(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,
  p_sector_snapshot in clob,p_actor_snapshot in clob)
return varchar2 as language java name
  'DoomMonsterChaseBench.load(java.lang.String,java.lang.String,long,java.sql.Clob,java.sql.Clob) return java.lang.String';
/
create or replace function doom_monster_chase_prepare(
  p_session in varchar2,p_lineage in varchar2,p_generation in number,p_request in varchar2,
  p_player_x in number,p_player_y in number)
return raw as language java name
  'DoomMonsterChaseBench.prepare(java.lang.String,java.lang.String,long,java.lang.String,oracle.sql.NUMBER,oracle.sql.NUMBER) return byte[]';
/
create or replace function doom_monster_chase_last_error return varchar2 as
language java name 'DoomMonsterChaseBench.lastError() return java.lang.String';
/
