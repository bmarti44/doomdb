whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off

declare
  k_token constant varchar2(32):='7437326272616e636869736f6c617465';
  l_blob blob;l_sha varchar2(64);l_old_lineage varchar2(64);
  l_new_lineage varchar2(64);l_x number;l_y number;l_count number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20978,p_message);end if;end;
  procedure command_(p_seq number,p_fire number,p_use number,p_weapon number) is
    l_document clob;
  begin
    l_document:='{"v":1,"commands":[{"seq":'||p_seq||
      ',"turn":0,"forward":0,"strafe":0,"run":0,"fire":'||p_fire||
      ',"use":'||p_use||',"weapon":'||p_weapon||
      ',"pause":0,"automap":0,"menu":"NONE","cheat":""}]}';
    doom_tic_tx.apply_batch(k_token,l_document,l_blob);
  end;
begin
  delete from game_sessions where session_token=k_token;
  insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
    map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
    last_command_seq,expires_at,created_at)
  values(k_token,'GAME',3,0,0,'ACTIVE',0,'NONE','OFF',null,
    lower(standard_hash('T72-BRANCH-OLD','SHA256')),0,
    systimestamp+interval '1' hour,systimestamp);
  insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
    yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
    weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
    power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
  values(k_token,0,-416,256,0,0,0,0,0,41,0,100,0,0,0,0,0,50,8,0,0,
    7,'PISTOL',0,0,0,0,0,0,0,1);
  update game_sessions set current_player_id=0 where session_token=k_token;
  insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
    light_level,light_timer,secret_found,damage_clock)
  select k_token,sector_id,floor_height,ceiling_height,light_level,null,0,0
    from doom_map_sector;
  insert into line_state(session_token,linedef_id,trigger_count,switch_on)
  select k_token,linedef_id,0,0 from doom_map_linedef;

  select save_lineage into l_old_lineage from game_sessions
    where session_token=k_token;
  doom_history.save_game(k_token,12,l_sha);
  command_(1,1,0,0);
  command_(2,0,1,3);
  doom_history.load_game(k_token,12,l_blob);
  select save_lineage into l_new_lineage from game_sessions
    where session_token=k_token;
  ok(l_new_lineage<>l_old_lineage,'load did not create a continuation lineage');

  -- These commands overlap old-branch logical tics one and two. Old FIRE,
  -- WEAPON, and USE values must be invisible to current gameplay consumers.
  command_(3,0,0,0);
  select count(*) into l_count from players where session_token=k_token
    and player_id=0 and ammo_bullets=50 and pending_weapon is null;
  ok(l_count=1,'old branch fire or weapon contaminated overlapping tic one');
  command_(4,0,0,0);
  select x,y into l_x,l_y from players where session_token=k_token and player_id=0;
  doom_world_machines.advance(k_token,2,l_x,l_y,null);
  select count(*) into l_count from players where session_token=k_token
    and player_id=0 and ammo_bullets=50 and pending_weapon is null;
  ok(l_count=1,'old branch weapon contaminated overlapping tic two');
  select count(*) into l_count from active_movers where session_token=k_token;
  ok(l_count=0,'old branch use activated a world mover');
  select count(*) into l_count from game_events where session_token=k_token
    and lineage=l_new_lineage and tic between 1 and 2
    and event_type in('HITSCAN_HIT','HITSCAN_MISS','DRY_FIRE','WEAPON_LOWER',
                      'LINE_TRIGGER');
  ok(l_count=0,'old branch command emitted a current-lineage gameplay event');

  command_(5,1,0,0);
  select count(*) into l_count from players where session_token=k_token
    and player_id=0 and ammo_bullets=49;
  ok(l_count=1,'current branch fire command was not consumed');
  select count(*) into l_count from game_events where session_token=k_token
    and lineage=l_new_lineage and tic=3
    and event_type in('HITSCAN_HIT','HITSCAN_MISS');
  ok(l_count=1,'current branch fire event missing');
  execute immediate 'set constraints all immediate';
  rollback;
  dbms_output.put_line('PASS T7.2-BRANCH-COMMAND-ISOLATION (fire, weapon and use scoped to current lineage)');
end;
/
