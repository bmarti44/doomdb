whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

declare
  k_token constant varchar2(32):='53535353535353535353535353535353';
  l_weapon varchar2(32);l_state varchar2(64);l_count number;l_bad number;
  procedure fail(m varchar2)is begin raise_application_error(-20953,m);end;
  procedure ok(v boolean,m varchar2)is begin if not v then fail(m);end if;end;
begin
  select count(*) into l_count from user_objects where object_name in ('DOOM_R2_MASKED_CANDIDATES','DOOM_R2_MASKED_PIXELS') and object_type='FUNCTION' and status='VALID';ok(l_count=2,'valid reviewed macros');
  select min(weapon_id) into l_weapon from doom_weapon_def;select spawn_state_id into l_state from doom_thing_type_def where thing_type=5;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T53',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(
    session_token,sector_id,floor_height,ceiling_height,light_level,
    secret_found,damage_clock
  )
  select k_token,sector_id,floor_height,ceiling_height,light_level,0,0
    from doom_map_sector;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id)values(k_token,1,5,l_state,8,-384,256,0,0,0,0,0,16,16,1,0,null,null,0,null);
  select count(*) into l_count from table(doom_r2_masked_candidates(k_token));ok(l_count>0,'no projected candidates');
  select count(*) into l_bad from table(doom_r2_masked_candidates(k_token)) where source_kind not in ('MASKED','SPRITE') or depth<=0 or palette_index not between 0 and 255 or screen_visible not in(0,1) or sector_visible not in(0,1) or wall_visible not in(0,1) or is_selected not in(0,1);ok(l_bad=0,'invalid candidate contract');
  select count(*) into l_bad from table(doom_r2_masked_pixels(k_token)) where column_no not between 0 and 319 or row_no not between 0 and 199 or palette_index not between 0 and 255;ok(l_bad=0,'invalid pixel bounds');
  select count(*) into l_bad from(select column_no,row_no,count(*) n from table(doom_r2_masked_pixels(k_token)) group by column_no,row_no having count(*)<>1);ok(l_bad=0,'duplicate winning pixel');
  select count(*) into l_bad from table(doom_r2_masked_pixels(k_token)) where screen_visible<>1 or sector_visible<>1 or wall_visible<>1 or is_selected<>1;ok(l_bad=0,'ineligible winner');
  rollback;dbms_output.put_line('PASS T5.3-ORACLE-PRODUCTION');
end;
/
