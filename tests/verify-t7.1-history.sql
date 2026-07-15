whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
declare
  k_token varchar2(32);l_sha varchar2(64);l_payload blob;l_count number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20972,p_message);end if;end;
begin
  select lower(substr(standard_hash('T71-COMBAT-HISTORY','MD5'),1,32))
    into k_token from dual;
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,19,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T71-COMBAT-LINEAGE','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,
    pending_weapon,weapon_state,weapon_state_tics,flash_state,flash_state_tics,
    refire,backpack,power_berserk)
  values(k_token,0,0,0,0,0,0,0,0,41,0,87,33,1,1,0,0,175,19,4,80,
    7,'PISTOL',0,0,0,0,0,2,0,1,'SHOTGUN','WEAPON_PISTOL_LOWER',2,
    'WEAPON_PISTOL_FLASH',1,3,1,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
    projectile_kind,exploded)
  values(k_token,91,9001,'PROJECTILE_ROCKET_FLY',1,12,3,32,20,0,0,0,11,8,
    1,0,null,null,0,null,null,'ROCKET',0);
  doom_history.save_game(k_token,7,l_sha);

  update players set ammo_bullets=0,pending_weapon=null,weapon_state='WEAPON_FIST_READY',
    weapon_state_tics=0,flash_state=null,flash_state_tics=0,refire=0,
    backpack=0,power_berserk=0 where session_token=k_token;
  delete from mobjs where session_token=k_token;
  doom_history.load_game(k_token,7,l_payload);

  select count(*) into l_count from players where session_token=k_token
    and ammo_bullets=175 and pending_weapon='SHOTGUN'
    and weapon_state='WEAPON_PISTOL_LOWER' and weapon_state_tics=2
    and flash_state='WEAPON_PISTOL_FLASH' and flash_state_tics=1
    and refire=3 and backpack=1 and power_berserk=1;
  ok(l_count=1,'combat player fields did not survive save/load');
  select count(*) into l_count from mobjs where session_token=k_token
    and mobj_id=91 and owner_mobj_id is null and projectile_kind='ROCKET'
    and exploded=0 and momentum_x=20;
  ok(l_count=1,'projectile authority did not survive save/load');
  rollback;
  dbms_output.put_line('PASS T7.1-HISTORY-CLOSURE (player inventory/weapon and projectile fields)');
end;
/
