whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
declare
  k_token varchar2(32);l_sha varchar2(64);l_payload blob;l_count number;l_sector number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20972,p_message);end if;end;
begin
  select lower(substr(standard_hash('T72-MONSTER-HISTORY','MD5'),1,32)),
         min(sector_id) into k_token,l_sector from doom_map_sector;
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,17,29,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T72-MONSTER-LINEAGE','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values(k_token,0,0,0,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,
    3,'PISTOL',0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
    projectile_kind,exploded,sector_id,move_direction,awake,attack_cooldown,
    monster_health_seen,death_processed)
  values(k_token,72,3001,'MON_IMP_CHASE',2,32,16,0,0,0,0,90,20,56,41,1,
    null,null,0,null,null,null,0,l_sector,3,1,5,52,0);

  doom_history.save_game(k_token,8,l_sha);
  update mobjs set sector_id=null,move_direction=-1,awake=0,attack_cooldown=0,
    monster_health_seen=null,death_processed=1,state_id='MON_IMP_CORPSE',
    state_tics=-1 where session_token=k_token and mobj_id=72;
  doom_history.load_game(k_token,8,l_payload);

  select count(*) into l_count from mobjs where session_token=k_token
    and mobj_id=72 and thing_type=3001 and state_id='MON_IMP_CHASE'
    and state_tics=2 and sector_id=l_sector and move_direction=3 and awake=1
    and attack_cooldown=5 and monster_health_seen=52 and death_processed=0;
  ok(l_count=1,'monster authority did not survive save/load');
  rollback;
  dbms_output.put_line('PASS T7.2-HISTORY-CLOSURE (monster state, perception, direction and lifecycle fields)');
end;
/
