set serveroutput on size unlimited
set feedback on
declare
  l_session varchar2(32);
  l_payload blob;
  l_seq number;

  procedure mark(p_label varchar2) is
  begin
    for r in (
      select p.x,p.y,p.angle,p.health,p.alive,p.blue_key,p.secret_count,
             g.current_tic,g.map_status,b.sector_id,
             (select count(*) from active_movers a
               where a.session_token=p.session_token) mover_count
      from players p join game_sessions g on g.session_token=p.session_token
      cross apply table(doom_bsp_locate(p.x,p.y)) b
      where p.session_token=l_session and p.player_id=0 and rownum=1
    ) loop
      dbms_output.put_line('CONT|'||p_label||'|seq='||l_seq||'|pos='||r.x||','||
        r.y||'|angle='||r.angle||'|sector='||r.sector_id||'|hp='||r.health||
        '|alive='||r.alive||'|blue='||r.blue_key||'|secret='||r.secret_count||
        '|status='||r.map_status||'|movers='||r.mover_count);
    end loop;
  end;

  procedure go(p_count number,p_turn number default 0,
    p_forward number default 0,p_strafe number default 0,
    p_run number default 0,p_fire number default 0,
    p_use number default 0,p_weapon number default 0) is
    l_previous_x number;l_previous_y number;l_angle number;
    l_delta_x number;l_delta_y number;l_player_id number;
    l_dest_x number;l_dest_y number;l_dest_z number;l_dest_view number;
  begin
    for i in 1..p_count loop
      l_seq:=l_seq+1;
      select p.x,p.y,mod(p.angle+p_turn*5.625+360,360)
        into l_previous_x,l_previous_y,l_angle
      from game_sessions g join players p
        on p.session_token=g.session_token and p.player_id=g.current_player_id
      where g.session_token=l_session;
      update players set angle=l_angle where session_token=l_session and player_id=0;
      l_delta_x:=(p_forward*cos(l_angle*acos(-1)/180)+
        p_strafe*sin(l_angle*acos(-1)/180))*8*(p_run+1);
      l_delta_y:=(p_forward*sin(l_angle*acos(-1)/180)-
        p_strafe*cos(l_angle*acos(-1)/180))*8*(p_run+1);
      select player_id,dest_x,dest_y,dest_z,view_height
        into l_player_id,l_dest_x,l_dest_y,l_dest_z,l_dest_view
      from table(doom_player_move(l_session,l_delta_x,l_delta_y));
      update players set x=l_dest_x,y=l_dest_y,z=l_dest_z,view_height=l_dest_view
        where session_token=l_session and player_id=l_player_id;
      insert into tic_commands(session_token,command_seq,tic,command_ordinal,
        turn,forward_move,strafe,run,fire,use_action,weapon_slot,pause_toggle,
        automap_toggle,menu_action,cheat_code,command_sha,lineage)
      select l_session,l_seq,l_seq,0,p_turn,p_forward,p_strafe,p_run,p_fire,
        p_use,p_weapon,0,0,'NONE',null,lpad(to_char(l_seq),64,'0'),save_lineage
      from game_sessions where session_token=l_session;
      doom_world_machines.advance(l_session,l_seq,l_previous_x,l_previous_y,p_use);
      doom_combat.advance(l_session,l_seq);
      doom_monsters.advance(l_session,l_seq);
      update game_sessions set current_tic=l_seq,last_command_seq=l_seq
        where session_token=l_session;
    end loop;
  end;
begin
  select session_token into l_session from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=99 order by g.created_at desc
  ) where rownum=1;
  doom_history.rewind_to_tic(l_session,715,l_payload);
  select current_tic into l_seq from game_sessions where session_token=l_session;
  mark('restored');
  rollback;
end;
/
