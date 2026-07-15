whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
declare
  l_session varchar2(32):='f6859126c01ab587f9f8852358304222';
  l_seq number:=0;l_start_x number;l_end_x number;l_health number;l_alive number;
  l_kills number;l_hits number;l_misses number;
  procedure ok(p_value boolean,p_message varchar2) is
  begin if not p_value then raise_application_error(-20972,p_message);end if;end;
  procedure go(p_count number,p_turn number default 0,
    p_forward number default 0,p_strafe number default 0,
    p_run number default 0,p_fire number default 0) is
    l_previous_x number;l_previous_y number;l_angle number;l_delta_x number;
    l_delta_y number;l_player number;l_dest_x number;l_dest_y number;
    l_dest_z number;l_dest_view number;
  begin
    for i in 1..p_count loop
      l_seq:=l_seq+1;
      select p.x,p.y,mod(p.angle+p_turn*5.625+360,360)
        into l_previous_x,l_previous_y,l_angle
        from game_sessions g join players p on p.session_token=g.session_token
          and p.player_id=g.current_player_id where g.session_token=l_session;
      update players set angle=l_angle where session_token=l_session and player_id=0;
      l_delta_x:=(p_forward*cos(l_angle*acos(-1)/180)
        +p_strafe*sin(l_angle*acos(-1)/180))*8*(p_run+1);
      l_delta_y:=(p_forward*sin(l_angle*acos(-1)/180)
        -p_strafe*cos(l_angle*acos(-1)/180))*8*(p_run+1);
      select player_id,dest_x,dest_y,dest_z,view_height
        into l_player,l_dest_x,l_dest_y,l_dest_z,l_dest_view
        from table(doom_player_move(l_session,l_delta_x,l_delta_y));
      update players set x=l_dest_x,y=l_dest_y,z=l_dest_z,view_height=l_dest_view
        where session_token=l_session and player_id=l_player;
      insert into tic_commands(session_token,command_seq,tic,command_ordinal,
        turn,forward_move,strafe,run,fire,use_action,weapon_slot,pause_toggle,
        automap_toggle,menu_action,cheat_code,command_sha,lineage)
      select l_session,l_seq,l_seq,0,p_turn,p_forward,p_strafe,p_run,p_fire,
        0,0,0,0,'NONE',null,lpad(to_char(l_seq),64,'0'),save_lineage
        from game_sessions where session_token=l_session;
      doom_world_machines.advance(l_session,l_seq,l_previous_x,l_previous_y,0);
      doom_combat.advance(l_session,l_seq);
      doom_monsters.advance(l_session,l_seq);
      update game_sessions set current_tic=l_seq,last_command_seq=l_seq
        where session_token=l_session;
    end loop;
  end;
begin
  savepoint survivability_start;
  -- Same fast opening/resource route used by the independent T8.1 lab.
  for step in 1..30 loop
    if step<=8 then
      go(1,p_forward=>1,p_strafe=>-1,p_run=>1,
        p_fire=>case when mod(step,5)=1 then 1 else 0 end);
    elsif step<=16 then
      go(1,p_forward=>1,p_strafe=>1,p_run=>1,
        p_fire=>case when mod(step,5)=1 then 1 else 0 end);
    else
      go(1,p_forward=>1,p_strafe=>-1,p_run=>1,
        p_fire=>case when mod(step,5)=1 then 1 else 0 end);
    end if;
  end loop;
  go(5,p_forward=>-1,p_run=>1);
  go(100);
  go(2,p_strafe=>1,p_run=>1);go(2,p_turn=>-1);
  select x into l_start_x from players where session_token=l_session and player_id=0;
  go(80,p_fire=>1);
  go(8,p_forward=>1,p_run=>1,p_fire=>1);
  select x,health,alive,kill_count into l_end_x,l_health,l_alive,l_kills
    from players where session_token=l_session and player_id=0;
  select count(*) into l_hits from game_events where session_token=l_session
    and event_type='HITSCAN_HIT';
  select count(*) into l_misses from game_events where session_token=l_session
    and event_type='MONSTER_MISS';
  ok(l_alive=1 and l_health>0,'ordinary cumulative fight killed the player');
  ok(l_kills>=1,'ordinary aligned pistol fire killed no representative monster');
  ok(l_hits>=1,'player hitscan produced no authoritative hit');
  ok(l_misses>=1,'monster spread produced no authoritative miss');
  ok(l_end_x<>l_start_x,'surviving player could not advance after the fight');
  dbms_output.put_line('PASS T7.2-SURVIVABILITY (hp='||l_health||', kills='||
    l_kills||', hits='||l_hits||', monster_misses='||l_misses||', advance='||
    l_start_x||'->'||l_end_x||')');
  rollback to survivability_start;
end;
/
