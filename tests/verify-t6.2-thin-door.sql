whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
set constraints all deferred;

declare
  k_token constant varchar2(32) := '6232646f6f727468726f617474657374';
  l_weapon varchar2(32);
  l_x number;l_y number;l_contacts number;l_first number;l_sector number;
  l_started number;l_elapsed number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin
    if not p_value then raise_application_error(-20926,p_message);end if;
  end;
  procedure place(p_x number,p_y number) is
  begin
    update players set x=p_x,y=p_y,z=-128
     where session_token=k_token and player_id=0;
  end;
  procedure move_(p_dx number,p_dy number) is
  begin
    select dest_x,dest_y,contact_count,first_blocker_id,destination_sector_id
      into l_x,l_y,l_contacts,l_first,l_sector
      from table(doom_player_move(k_token,p_dx,p_dy));
  end;
begin
  delete from game_sessions where session_token=k_token;
  select weapon_id into l_weapon from (
    select weapon_id from doom_weapon_def order by slot_number
  ) where rownum=1;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T62-THIN-DOOR','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,noclip)
  values(k_token,0,752,2064,-128,0,0,0,90,41,0,100,0,0,0,0,0,
    50,0,0,0,1,l_weapon,0,0,0,0,0,0,0,1,0);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
    light_level,secret_found,damage_clock)
  select k_token,sector_id,floor_height,ceiling_height,light_level,0,0
    from doom_map_sector;

  -- E1M1 sector 81 is a sixteen-unit throat: portal 483 at y=2080 and
  -- portal 442 at y=2096. One 64-unit sweep must cross both without requiring
  -- the radius-16 center to be owned by the thin intermediate BSP leaf.
  update sector_state set ceiling_height=0
   where session_token=k_token and sector_id=81;
  place(752,2064);move_(0,64);
  ok(l_x=752 and l_y=2128 and l_contacts=0 and l_sector=74,
    'open paired portals did not traverse thin sector 81 continuously');

  -- Exact radius tangency to east jamb endpoint (768,2080) is not entry.
  place(784,2064);move_(0,64);
  ok(l_x=784 and l_y=2128 and l_contacts=0,
    'exact jamb endpoint tangency was treated as inward contact');

  -- E1M1's sector-10 door has an ordinary one-sided east jamb rather than the
  -- sub-diameter paired-portal shape above. Once the door has player-height
  -- clearance, a radius-exact center moving parallel/away from endpoint
  -- (896,512) must not stick at y=512.
  update sector_state set ceiling_height=-54
   where session_token=k_token and sector_id=10;
  place(880,512);move_(0,16);
  ok(l_x=880 and l_y=528 and l_contacts=0,
    'ordinary exact jamb tangency blocked non-inward motion');

  -- Genuine inward motion into the east one-sided jamb remains blocked.
  place(736,2088);move_(64,0);
  ok(l_x=752 and l_y=2088 and l_contacts=1 and l_first=484,
    'sector 81 east jamb did not block an overlapping sweep');

  -- The retained T8 opening replay first escaped at command 784: its center
  -- changed from BSP sector 19 to sector 74 beyond the finite east boundary,
  -- without crossing any two-sided portal. A phantom BSP partition transition
  -- is not a traversable map opening.
  place(1086.630241096433411158005136299359457888,
        2095.647841757095777322710134507527611864);
  move_(-22.192637525154359389145907065063018098,
          4.414390068527088197375321018709966118);
  ok(abs(l_x-1086.630241096433411158005136299359457888)<0.000000000001
     and abs(l_y-2095.647841757095777322710134507527611864)<0.000000000001
     and l_sector=19,
    'portal-free BSP sector transition escaped the finite map boundary');

  -- Closing the door restores the south portal as a blocker.
  update sector_state set ceiling_height=-128
   where session_token=k_token and sector_id=81;
  place(752,2064);move_(0,64);
  ok(l_x=752 and l_y=2064 and l_contacts=1 and l_first=483 and l_sector=86,
    'closed sector 81 door admitted the player');

  -- Bound the ordinary fast path and both changed-sector decisions. This is
  -- deliberately state-only: no frame/history work obscures collision cost.
  update sector_state set ceiling_height=0
   where session_token=k_token and sector_id=81;
  l_started:=dbms_utility.get_time;
  place(752,2064);
  for i in 1..100 loop move_(1,0);end loop;
  place(1086.630241096433411158005136299359457888,
        2095.647841757095777322710134507527611864);
  for i in 1..25 loop
    move_(-22.192637525154359389145907065063018098,
            4.414390068527088197375321018709966118);
  end loop;
  place(784,2064);
  for i in 1..25 loop move_(0,64);end loop;
  l_elapsed:=dbms_utility.get_time-l_started;
  ok(l_elapsed<1000,'collision transition benchmark exceeded ten seconds');
  dbms_output.put_line('T62_PERF|ordinary=100|invalid=25|thin_tangent=25|centiseconds='||l_elapsed);

  rollback;
  dbms_output.put_line('PASS T6.2-THIN-DOOR (open paired portals, exact tangency, jamb, closed door)');
end;
/
