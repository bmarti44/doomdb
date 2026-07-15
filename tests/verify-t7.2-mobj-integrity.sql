whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
declare
  k_token constant varchar2(32) := '72f172f172f172f172f172f172f172f1';
  l_sha varchar2(64);l_payload blob;l_count number;l_sector number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20972,p_message);end if;end;
begin
  select min(sector_id) into l_sector from doom_map_sector;
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,1,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T72-MOBJ-INTEGRITY','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,
    pending_weapon,weapon_state,weapon_state_tics,flash_state,flash_state_tics,
    refire,backpack,power_berserk)
  values(k_token,0,0,0,0,0,0,0,0,41,0,90,0,0,0,0,0,50,0,0,0,
    3,'PISTOL',0,0,0,0,0,0,0,1,null,'WEAPON_PISTOL_READY',0,null,0,0,0,0);
  update game_sessions set current_player_id=0 where session_token=k_token;

  -- A real consumable is the actor being removed.  The other actors exercise
  -- every self-referencing MOBJ pointer that must be detached atomically.
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
    projectile_kind,exploded,sector_id)
  values(k_token,10,2011,'THING_2011_SPAWN',8,0,0,0,0,0,0,0,8,8,1,0,
    null,null,0,null,null,null,0,l_sector);
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
    projectile_kind,exploded,sector_id)
  values(k_token,11,2011,'THING_2011_SPAWN',8,100,100,0,0,0,0,0,8,8,1,0,
    10,10,0,null,10,null,0,l_sector);

  doom_combat.advance(k_token,1);
  select count(*) into l_count from mobjs
    where session_token=k_token and mobj_id=10;
  ok(l_count=0,'consumed actor was not removed');
  select count(*) into l_count from mobjs
    where session_token=k_token and mobj_id=11
      and target_mobj_id is null and tracer_mobj_id is null
      and owner_mobj_id is null;
  ok(l_count=1,'inbound actor pointers were not detached before removal');
  select count(*) into l_count from players
    where session_token=k_token and player_id=0 and health=100 and item_count=1;
  ok(l_count=1,'real pickup path did not apply its authoritative result');

  doom_history.save_game(k_token,72,l_sha);
  doom_history.load_game(k_token,72,l_payload);
end;
/
set constraints all immediate;
declare
  k_token constant varchar2(32) := '72f172f172f172f172f172f172f172f1';
  l_count number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20972,p_message);end if;end;
begin
  select count(*) into l_count from mobjs m
    where m.session_token=k_token and (
      (m.target_mobj_id is not null and not exists (
        select 1 from mobjs t where t.session_token=m.session_token
          and t.mobj_id=m.target_mobj_id))
      or (m.tracer_mobj_id is not null and not exists (
        select 1 from mobjs t where t.session_token=m.session_token
          and t.mobj_id=m.tracer_mobj_id))
      or (m.owner_mobj_id is not null and not exists (
        select 1 from mobjs t where t.session_token=m.session_token
          and t.mobj_id=m.owner_mobj_id)));
  ok(l_count=0,'save/load retained a dangling actor pointer');
end;
/
commit;
delete from game_sessions
  where session_token='72f172f172f172f172f172f172f172f1';
commit;
begin
  dbms_output.put_line('PASS T7.2-MOBJ-INTEGRITY (combat cleanup, save/load and committed immediate constraints)');
end;
/
