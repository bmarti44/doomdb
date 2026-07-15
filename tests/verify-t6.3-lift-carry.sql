whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off

declare
  k_token constant varchar2(32) := '63c463c463c463c463c463c463c463c4';
  l_floor number;l_ceiling number;l_z number;l_mobj_z number;l_count number;
  l_direction number;l_timer number;l_target number;l_sector number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin
    if not p_value then raise_application_error(-20963,p_message);end if;
  end;
begin
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T63-LIFT-CARRY','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values(k_token,0,200,256,-124,0,0,0,180,41,0,100,0,0,0,0,0,50,0,0,0,
    3,'PISTOL',0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
    light_level,light_timer,secret_found,damage_clock)
  select k_token,sector_id,floor_height,ceiling_height,light_level,null,0,0
    from doom_map_sector;
  insert into line_state(session_token,linedef_id,trigger_count,switch_on)
  select k_token,linedef_id,0,0 from doom_map_linedef;

  -- Real L594 activation begins the tag-1 lift at its reviewed speed.
  doom_world_machines.advance(k_token,1,200,256,1);
  select count(*) into l_count from active_movers
    where session_token=k_token and sector_id=98 and plane='FLOOR'
      and mover_kind='LIFT' and direction=-1 and speed=1
      and target_height=-124 and origin_height=12 and wait_tics=105
      and source_linedef_id=594;
  ok(l_count=1,'L594 did not create the reviewed sector-98 lift');
  select floor_height into l_floor from sector_state
    where session_token=k_token and sector_id=98;
  ok(l_floor=11,'lift did not lower on its activation tic');

  for l_tic in 2..136 loop
    doom_world_machines.advance(k_token,l_tic,200,256,0);
  end loop;
  select s.floor_height,m.direction,m.timer_tics
    into l_floor,l_direction,l_timer
    from sector_state s join active_movers m
      on m.session_token=s.session_token and m.sector_id=s.sector_id
   where s.session_token=k_token and s.sector_id=98;
  ok(l_floor=-124 and l_direction=0 and l_timer=105,
    'lift bottom or wait timer is incorrect');

  -- Enter only after the platform is level.  The mobj verifies that carrying
  -- applies to the sector thing list as well as to the current player.
  update players set x=176,y=256,z=-124 where session_token=k_token;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,sector_id)
  values(k_token,6301,2011,'THING_2011_SPAWN',8,128,256,-124,
    0,0,0,0,8,16,1,0,null,null,0,null,98);
  for l_tic in 137..241 loop
    doom_world_machines.advance(k_token,l_tic,176,256,0);
  end loop;
  select floor_height into l_floor from sector_state
    where session_token=k_token and sector_id=98;
  select direction,timer_tics into l_direction,l_timer from active_movers
    where session_token=k_token and sector_id=98;
  ok(l_floor=-124 and l_direction=1 and l_timer=0,
    'occupied lift did not complete its exact bottom wait');

  doom_world_machines.advance(k_token,242,176,256,0);
  select floor_height into l_floor from sector_state
    where session_token=k_token and sector_id=98;
  select z into l_z from players where session_token=k_token and player_id=0;
  select z into l_mobj_z from mobjs where session_token=k_token and mobj_id=6301;
  ok(l_floor=-123 and l_z=-123 and l_mobj_z=-123,
    'first rising tic did not advance and carry supported actors');

  for l_tic in 243..377 loop
    doom_world_machines.advance(k_token,l_tic,176,256,0);
  end loop;
  select floor_height into l_floor from sector_state
    where session_token=k_token and sector_id=98;
  select z into l_z from players where session_token=k_token and player_id=0;
  select z into l_mobj_z from mobjs where session_token=k_token and mobj_id=6301;
  select count(*) into l_count from active_movers
    where session_token=k_token and sector_id=98;
  ok(l_floor=12 and l_z=12 and l_mobj_z=12 and l_count=0,
    'lift did not carry actors to its origin and terminate');

  update players set x=128,y=176,z=0 where session_token=k_token;
  select sector_id into l_sector from table(doom_bsp_locate(128,176))
    where rownum=1;
  ok(l_sector=147,'player exit point is not beyond the sector-98 lift');

  -- A non-crushing lift may stall for actual headroom obstruction, but only
  -- after completing every safe increment and carrying its supported actor.
  delete from mobjs where session_token=k_token and mobj_id=6301;
  update sector_state set floor_height=-124,ceiling_height=-67
    where session_token=k_token and sector_id=98;
  update players set x=176,y=256,z=-124 where session_token=k_token;
  insert into active_movers(session_token,mover_id,sector_id,plane,direction,
    speed,target_height,wait_tics,timer_tics,mover_kind,origin_height,
    source_linedef_id)
  values(k_token,1,98,'FLOOR',1,1,12,105,0,'LIFT',12,594);
  doom_world_machines.advance(k_token,378,176,256,0);
  doom_world_machines.advance(k_token,379,176,256,0);
  select s.floor_height,s.ceiling_height,p.z,m.direction,m.target_height
    into l_floor,l_ceiling,l_z,l_direction,l_target
    from sector_state s join players p on p.session_token=s.session_token
    join active_movers m on m.session_token=s.session_token
      and m.sector_id=s.sector_id
   where s.session_token=k_token and s.sector_id=98 and p.player_id=0;
  ok(l_floor=-123 and l_ceiling=-67 and l_z=-123
      and l_direction=1 and l_target=12,
    'headroom obstruction did not preserve the last safe lift state');
  select count(*) into l_count from game_events
    where session_token=k_token and tic=379 and event_type='LIFT_BLOCKED'
      and number_value=98;
  ok(l_count=1,'true headroom obstruction did not emit LIFT_BLOCKED');

  rollback;
  dbms_output.put_line('PASS T6.3-LIFT-CARRY (lower, wait, carry, target, exit and headroom obstruction)');
end;
/
