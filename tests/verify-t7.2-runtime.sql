whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
declare
  k_token varchar2(32);l_x number;l_y number;l_sector number;l_count number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20972,p_message);end if;end;
begin
  select lower(substr(standard_hash('T72-LIFECYCLE','MD5'),1,32)) into k_token from dual;
  select x,y into l_x,l_y from doom_map_thing where thing_type=3004
    order by thing_id fetch first 1 row only;
  select sector_id into l_sector from table(doom_bsp_locate(l_x,l_y)) where rownum=1;
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T72-LIFECYCLE-LINEAGE','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values(k_token,0,l_x,l_y,0,0,0,0,0,41,0,100,0,0,0,0,0,50,0,0,0,
    3,'PISTOL',0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,sector_id,
    move_direction,awake,attack_cooldown,monster_health_seen,death_processed)
  values(k_token,72,3004,'MON_ZOMBIE_IDLE',1,l_x,l_y,0,0,0,0,0,20,56,
    20,1,null,null,0,null,l_sector,-1,0,0,20,0);

  doom_monsters.advance(k_token,1);
  select count(*) into l_count from mobjs where session_token=k_token
    and mobj_id=72 and awake=1 and state_id='MON_ZOMBIE_SEE';
  ok(l_count=1,'coincident visible monster did not wake through database LOS');

  update mobjs set health=0 where session_token=k_token and mobj_id=72;
  doom_monsters.advance(k_token,2);
  select count(*) into l_count from mobjs where session_token=k_token
    and mobj_id=72 and state_id='MON_ZOMBIE_DEATH' and death_processed=1
    and awake=0 and flags=0;
  ok(l_count=1,'lethal combat result did not enter once-only death state');
  select count(*) into l_count from mobjs where session_token=k_token
    and owner_mobj_id=72 and thing_type=2007 and x=l_x and y=l_y;
  ok(l_count=1,'relational zombieman drop was not created exactly once');
  select count(*) into l_count from players where session_token=k_token
    and player_id=0 and kill_count=1;
  ok(l_count=1,'once-only kill credit missing');
  rollback;
  dbms_output.put_line('PASS T7.2-LIFECYCLE (wake, death, drop and kill credit)');
end;
/
