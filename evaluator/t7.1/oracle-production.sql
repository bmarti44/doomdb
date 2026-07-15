whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
 c number; v number; s varchar2(128);
 procedure fail(m varchar2) is begin raise_application_error(-20971,m);end;
 procedure ok(b boolean,m varchar2) is begin if not b then fail(m);end if;end;
begin
 select count(*) into c from user_objects where object_name='DOOM_COMBAT' and object_type='PACKAGE' and status='VALID';ok(c=1,'valid DOOM_COMBAT package absent');
 select count(*) into c from user_procedures where object_name='DOOM_COMBAT' and procedure_name='ADVANCE';ok(c=1,'DOOM_COMBAT.ADVANCE absent or overloaded');
 select count(*) into c from doom_weapon_def;ok(c=7,'reviewed seven-weapon catalog absent');
 select count(distinct slot_number) into c from doom_weapon_def;ok(c=7,'weapon slot collision');
 select count(*) into c from doom_ammo_def where (ammo_type='BULLET' and normal_cap=200 and backpack_cap=400) or (ammo_type='SHELL' and normal_cap=50 and backpack_cap=100) or (ammo_type='ROCKET' and normal_cap=50 and backpack_cap=100) or (ammo_type='CELL' and normal_cap=300 and backpack_cap=600);ok(c=4,'ammo cap matrix drift');
 select count(*) into c from doom_projectile_def where projectile_kind in('ROCKET','PLASMA') and speed>0 and radius>0 and damage>0;ok(c=2,'projectile definition matrix absent');
 select count(*) into c from doom_rng_value;ok(c=256,'Doom RNG table must contain 256 rows');
 select count(distinct rng_index) into c from doom_rng_value where rng_index between 0 and 255;ok(c=256,'Doom RNG index domain drift');
 select count(*) into c from (select distinct mt.thing_type from doom_map_thing mt join doom_thing_type_def td on td.thing_type=mt.thing_type where td.category in('pickup','weapon_pickup') or mt.thing_type=2035) e where not exists(select 1 from doom_pickup_def p where p.thing_type=e.thing_type) and e.thing_type<>2035;ok(c=0,'E1M1 interactive pickup/weapon lacks definition');
 select count(distinct mt.thing_type) into c from doom_map_thing mt join doom_thing_type_def td on td.thing_type=mt.thing_type where td.category in('pickup','weapon_pickup') or mt.thing_type=2035;ok(c=23,'reviewed E1M1 interactive type set drift');
 select count(*) into c from doom_map_thing where thing_type=2035;ok(c=22,'reviewed E1M1 barrel placement count drift');
 select count(*) into c from user_tab_columns where table_name='PLAYERS' and column_name in('WEAPON_STATE','FLASH_STATE','REFIRE','BACKPACK');ok(c=4,'authoritative player weapon/inventory columns absent');
 select count(*) into c from user_tab_columns where table_name='MOBJS' and column_name in('OWNER_MOBJ_ID','PROJECTILE_KIND','EXPLODED');ok(c=3,'projectile/barrel authority columns absent');
 select count(*) into c from user_source where name='DOOM_COMBAT' and type='PACKAGE BODY' and upper(text) like '%DOOM_R1_RAYS%';ok(c>0,'hitscan does not use intersection query');
 select count(*) into c from user_source where name='DOOM_COMBAT' and type='PACKAGE BODY' and regexp_like(upper(text),'DBMS_RANDOM|SYSDATE|SYSTIMESTAMP|EXECUTE IMMEDIATE|PRAGMA AUTONOMOUS');ok(c=0,'forbidden nondeterminism/dynamic SQL in combat');
 -- Focused production replay: one session owns every E1M1 interactive mobj;
 -- ADVANCE must consume a useful nearby bullet box exactly once and clamp.
 declare tok varchar2(32):='71717171717171717171717171717171'; before_n number; after_n number;
 begin
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at) values(tok,'GAME',3,1,0,'ACTIVE',0,'NONE','OFF',null,'T71',0,timestamp'2099-01-02 00:00:00 UTC',timestamp'2099-01-01 00:00:00 UTC');
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,noclip,weapon_state,flash_state,refire,backpack) values(tok,0,0,0,0,0,0,0,0,41,0,100,0,0,0,0,0,195,0,0,0,3,'PISTOL',0,0,0,0,0,0,0,1,0,'WEAPON_PISTOL_READY',null,0,0);
  update game_sessions set current_player_id=0 where session_token=tok;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,projectile_kind,exploded) values(tok,10,2048,'THING_2048_SPAWN',8,8,0,0,0,0,0,0,16,16,1,0,null,null,0,null,null,null,0);
  insert into tic_commands(session_token,command_seq,tic,command_ordinal,turn,forward_move,strafe,run,fire,use_action,weapon_slot,pause_toggle,automap_toggle,menu_action,cheat_code,command_sha) values(tok,1,1,0,0,0,0,0,0,0,0,0,0,'NONE',null,rpad('0',64,'0'));
  select count(*) into before_n from mobjs where session_token=tok and mobj_id=10;doom_combat.advance(tok,1);select ammo_bullets into v from players where session_token=tok and player_id=0;ok(v=200,'bullet-box cap replay failed');select count(*) into after_n from mobjs where session_token=tok and mobj_id=10;ok(before_n=1 and after_n=0,'useful pickup not consumed exactly once');
  delete from game_sessions where session_token=tok;
 end;
 rollback;
 dbms_output.put_line('PASS T7.1-ORACLE-PRODUCTION (catalog, E1M1 coverage, useful pickup replay, anti-nondeterminism)');
end;
/
