whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
 c number; v number; s varchar2(128);
 procedure fail(m varchar2) is begin raise_application_error(-20972,m);end;
 procedure ok(b boolean,m varchar2) is begin if not b then fail(m);end if;end;
begin
 select count(*) into c from user_objects where object_name='DOOM_MONSTERS' and object_type='PACKAGE' and status='VALID';ok(c=1,'valid DOOM_MONSTERS package absent');
 select count(*) into c from user_procedures where object_name='DOOM_MONSTERS' and procedure_name='ADVANCE';ok(c=1,'DOOM_MONSTERS.ADVANCE absent or overloaded');
 select count(*) into c from doom_monster_def where thing_type in(9,58,3001,3002,3004);ok(c=5,'reviewed five-type monster matrix absent');
 select count(distinct thing_type) into c from doom_monster_def;ok(c>=5,'monster definition keys collide');
 select count(*) into c from doom_monster_def where thing_type in(9,58,3001,3002,3004) and speed>0 and pain_chance between 0 and 255 and melee_range>0 and attack_kind in('MELEE','HITSCAN','PROJECTILE') and damage_base>0 and damage_dice>0;ok(c=5,'monster behavior definition incomplete');
 select count(*) into c from doom_monster_def where thing_type=9 and attack_kind='HITSCAN' and drop_thing_type=2001;ok(c=1,'sergeant attack/drop drift');
 select count(*) into c from doom_monster_def where thing_type=58 and attack_kind='MELEE' and drop_thing_type is null;ok(c=1,'spectre policy drift');
 select count(*) into c from doom_monster_def where thing_type=3001 and attack_kind='PROJECTILE' and projectile_thing_type is not null and drop_thing_type is null;ok(c=1,'imp projectile policy drift');
 select count(*) into c from doom_monster_def where thing_type=3002 and attack_kind='MELEE' and drop_thing_type is null;ok(c=1,'demon policy drift');
 select count(*) into c from doom_monster_def where thing_type=3004 and attack_kind='HITSCAN' and drop_thing_type=2007;ok(c=1,'zombieman attack/drop drift');
 select count(*) into c from doom_monster_def d where d.thing_type in(9,58,3001,3002,3004) and (not exists(select 1 from doom_state_def s where s.state_id=d.see_state_id) or not exists(select 1 from doom_state_def s where s.state_id=d.chase_state_id) or not exists(select 1 from doom_state_def s where s.state_id=d.pain_state_id) or not exists(select 1 from doom_state_def s where s.state_id=d.death_state_id));ok(c=0,'monster state foreign graph incomplete');
 select count(*) into c from doom_state_def s where s.next_state_id is not null and not exists(select 1 from doom_state_def n where n.state_id=s.next_state_id);ok(c=0,'dangling state next reference');
 select count(*) into c from user_tab_columns where table_name='MOBJS' and column_name in('SECTOR_ID','MOVE_DIRECTION','AWAKE','ATTACK_COOLDOWN');ok(c=4,'authoritative monster state columns absent');
 select count(*) into c from user_source where name='DOOM_MONSTERS' and type='PACKAGE BODY' and upper(text) like '%DOOM_REJECT_BYTE%';ok(c>0,'REJECT negative filter absent from package');
 select count(*) into c from user_source where name='DOOM_MONSTERS' and type='PACKAGE BODY' and regexp_like(upper(text),'INTERSECT|DOOM_R1_RAYS');ok(c>0,'exact intercept LOS path absent from package');
 select count(*) into c from user_source where name='DOOM_MONSTERS' and type='PACKAGE BODY' and regexp_like(upper(text),'CONNECT BY|BREADTH|SECTOR_GRAPH|SOUND_REACH');ok(c>0,'graph sound reachability absent from package');
 select count(*) into c from user_source where name='DOOM_MONSTERS' and type='PACKAGE BODY' and regexp_like(upper(text),'DBMS_RANDOM|SYSDATE|SYSTIMESTAMP|EXECUTE IMMEDIATE|PRAGMA AUTONOMOUS');ok(c=0,'forbidden nondeterminism/dynamic SQL in monsters');
 select count(*) into c from user_source where name='DOOM_MONSTERS' and type='PACKAGE BODY' and regexp_like(upper(text),'WHEN[[:space:]]+(9|58|3001|3002|3004)[[:space:]]+THEN');ok(c=0,'hard-coded reviewed monster type dispatch');
 -- Every reviewed E1M1 monster placement is definition-backed.
 select count(*) into c from (select distinct thing_type from doom_map_thing where thing_type in(9,58,3001,3002,3004)) p where not exists(select 1 from doom_monster_def d where d.thing_type=p.thing_type);ok(c=0,'E1M1 monster placement lacks definition');
 select count(distinct thing_type) into c from doom_map_thing where thing_type in(9,58,3001,3002,3004);ok(c=5,'reviewed E1M1 monster type set drift');
 dbms_output.put_line('PASS T7.2-ORACLE-PRODUCTION (five types, state graph, perception paths, relational attacks/drops, anti-nondeterminism)');
end;
/
