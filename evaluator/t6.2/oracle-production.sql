whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set time_zone='UTC';
declare
  k_token constant varchar2(32):='62626262626262626262626262626262';
  l_weapon varchar2(32);l_count number;l_x number;l_y number;l_z number;l_sector number;l_view number;l_eye number;l_contacts number;
  procedure fail(m varchar2) is begin raise_application_error(-20962,m);end;
  procedure ok(v boolean,m varchar2) is begin if not v then fail(m);end if;end;
begin
  select count(*) into l_count from user_objects where object_name='DOOM_PLAYER_MOVE' and object_type='FUNCTION' and status='VALID';ok(l_count=1,'valid movement macro absent');
  for k in (select config_key,number_value from doom_config where config_key in ('PLAYER_RADIUS','PLAYER_HEIGHT','PLAYER_STEP_HEIGHT','PLAYER_VIEW_HEIGHT','PLAYER_MAX_CONTACTS')) loop
    null;
  end loop;
  select count(*) into l_count from doom_config where (config_key='PLAYER_RADIUS' and number_value=16) or (config_key='PLAYER_HEIGHT' and number_value=56) or (config_key='PLAYER_STEP_HEIGHT' and number_value=24) or (config_key='PLAYER_VIEW_HEIGHT' and number_value=41) or (config_key='PLAYER_MAX_CONTACTS' and number_value=2);ok(l_count=5,'reviewed movement configuration absent');
  select weapon_id into l_weapon from (select weapon_id from doom_weapon_def order by slot_number) where rownum=1;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,map_status,paused,menu_state,automap_state,current_player_id,save_lineage,last_command_seq,expires_at,created_at)
    values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,'T62',0,systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,weapon_mask,selected_weapon,power_invulnerability,power_invisibility,power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,noclip)
    values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1,0);
  update game_sessions set current_player_id=0 where session_token=k_token;
  select count(*),min(dest_x),min(dest_y),min(dest_z),min(destination_sector_id),min(view_height),min(eye_z),min(contact_count)
    into l_count,l_x,l_y,l_z,l_sector,l_view,l_eye,l_contacts from table(doom_player_move(k_token,0,0));
  ok(l_count=1,'zero move must return exactly one row');ok(l_x=-416 and l_y=256,'zero move changed horizontal pose');ok(l_view=41 and l_eye=l_z+41,'destination eye contract');ok(l_contacts=0,'zero move has contact');
  update players set noclip=1 where session_token=k_token and player_id=0;
  select count(*),min(dest_x),min(dest_y),min(contact_count) into l_count,l_x,l_y,l_contacts from table(doom_player_move(k_token,5,-3));
  ok(l_count=1 and l_x=-411 and l_y=253 and l_contacts=0,'database noclip displacement');
  rollback;dbms_output.put_line('PASS T6.2-ORACLE-PRODUCTION');
end;
/
