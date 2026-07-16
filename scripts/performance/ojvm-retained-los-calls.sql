whenever sqlerror exit failure rollback

create or replace function doom_retained_los_load(p_snapshot in clob) return varchar2 as
language java name 'DoomRetainedLosBench.load(java.sql.Clob) return java.lang.String';
/
create or replace function doom_retained_los_visible(
  p_x in number,p_y in number,p_source_sector in number,
  p_target_x in number,p_target_y in number,p_target_sector in number)
return number as language java name
  'DoomRetainedLosBench.visible(oracle.sql.NUMBER,oracle.sql.NUMBER,int,oracle.sql.NUMBER,oracle.sql.NUMBER,int) return int';
/
create or replace function doom_retained_los_last_error return varchar2 as
language java name 'DoomRetainedLosBench.lastError() return java.lang.String';
/
create or replace function doom_retained_los_actor_benchmark(
  p_actors in clob,p_target_x in number,p_target_y in number,
  p_target_sector in number,p_iterations in number)
return varchar2 as language java name
  'DoomRetainedLosBench.benchmarkActorBatch(java.sql.Clob,oracle.sql.NUMBER,oracle.sql.NUMBER,int,int) return java.lang.String';
/
