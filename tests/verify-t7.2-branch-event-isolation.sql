whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off

declare
  k_token constant varchar2(32):='7437326272616e63686576656e746973';
  l_blob blob;l_sha varchar2(64);l_old_lineage varchar2(64);
  l_new_lineage varchar2(64);l_player_x number;l_player_y number;
  l_player_sector number;l_hidden_sector number;l_count number;
  l_fixture boolean:=false;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20979,p_message);end if;end;
begin
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T72-BRANCH-EVENT-OLD','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  select x,y into l_player_x,l_player_y from doom_map_thing
    where thing_type=1 and rownum=1;
  for point_ in (select x,y from doom_map_thing order by thing_id) loop
    select sector_id into l_player_sector
      from table(doom_bsp_locate(point_.x,point_.y)) where rownum=1;
    select min(reject_row.source_sector_id) into l_hidden_sector
      from doom_sector_reject reject_row
      join doom_sector_sound_reach sound_row
        on sound_row.source_sector_id=l_player_sector
       and sound_row.target_sector_id=reject_row.source_sector_id
      where reject_row.target_sector_id=l_player_sector
        and reject_row.rejected=1;
    if l_hidden_sector is not null then
      l_player_x:=point_.x;l_player_y:=point_.y;l_fixture:=true;exit;
    end if;
  end loop;
  ok(l_fixture,'no REJECT-hidden sound-connected fixture');
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive,noclip)
  select k_token,0,l_player_x,l_player_y,sector.floor_height,0,0,0,0,41,0,
    100,0,0,0,0,0,50,0,0,0,3,'PISTOL',0,0,0,0,0,0,0,1,0
  from doom_map_sector sector where sector.sector_id=l_player_sector;
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
    light_level,light_timer,secret_found,damage_clock)
  select k_token,sector_id,floor_height,ceiling_height,light_level,null,0,0
    from doom_map_sector;
  insert into line_state(session_token,linedef_id,trigger_count,switch_on)
  select k_token,linedef_id,0,0 from doom_map_linedef;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
    target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,sector_id,
    move_direction,awake,attack_cooldown,monster_health_seen,death_processed)
  select k_token,thing.thing_id,thing.thing_type,type_def.spawn_state_id,
    state_def.tics,thing.x,thing.y,0,0,0,0,thing.angle,
    coalesce(type_def.radius,0),coalesce(type_def.height,0),
    coalesce(type_def.spawn_health,1),type_def.flags,null,null,0,thing.thing_id,
    case when monster_def.thing_type is not null then l_hidden_sector end,
    -1,0,case when monster_def.thing_type is not null then 1 else 0 end,null,0
  from doom_map_thing thing
  join doom_thing_type_def type_def on type_def.thing_type=thing.thing_type
  join doom_state_def state_def on state_def.state_id=type_def.spawn_state_id
  left join doom_monster_def monster_def on monster_def.thing_type=thing.thing_type
  where thing.thing_type<>1 and type_def.spawn_state_id is not null;

  select save_lineage into l_old_lineage from game_sessions
    where session_token=k_token;
  doom_history.save_game(k_token,13,l_sha);
  insert into game_events(session_token,tic,event_ordinal,event_type)
    values(k_token,1,0,'DRY_FIRE');
  doom_history.load_game(k_token,13,l_blob);
  select save_lineage into l_new_lineage from game_sessions
    where session_token=k_token;
  ok(l_new_lineage<>l_old_lineage,'load did not create a continuation lineage');

  doom_tic_tx.apply_batch(k_token,
    '{"v":1,"commands":[{"seq":1,"turn":0,"forward":0,"strafe":0,'||
    '"run":0,"fire":0,"use":0,"weapon":0,"pause":1,"automap":0,'||
    '"menu":"NONE","cheat":""}]}',l_blob);
  select count(*) into l_count from game_events where session_token=k_token
    and lineage=l_new_lineage and tic=1 and event_type='CONTROL_PAUSE'
    and event_ordinal=0;
  ok(l_count=1,'abandoned event shifted current-lineage ordinal');
  select count(*) into l_count from game_events where session_token=k_token
    and lineage=l_new_lineage and tic=1 and event_type='MONSTER_WAKE';
  ok(l_count=0,'abandoned DRY_FIRE woke a current-lineage monster');
  select count(*) into l_count from mobjs m where m.session_token=k_token
    and m.awake<>0 and exists(select 1 from doom_monster_def d
      where d.thing_type=m.thing_type);
  ok(l_count=0,'current-lineage monster state was contaminated');
  select count(*) into l_count from game_events where session_token=k_token
    and lineage=l_old_lineage and tic=1 and event_type='DRY_FIRE';
  ok(l_count=1,'abandoned history was erased');
  execute immediate 'set constraints all immediate';
  rollback;
  dbms_output.put_line('PASS T7.2-BRANCH-EVENT-ISOLATION (ordinal and sound consumers are lineage-fenced)');
end;
/
