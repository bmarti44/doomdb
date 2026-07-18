set serveroutput on size unlimited
set feedback on
set sqlblanklines on
declare
  l_session varchar2(32);
  l_payload blob;
  l_seq number := 0;
  l_tic number := 0;
  l_alive number;
  l_hp number;
  l_x number;
  l_y number;
  l_items number;
  l_misses number;
  l_distance number;
  l_best_alive number := -1;
  l_best_hp number := -1;
  l_best_distance number := 1e30;
  l_best_s number;
  l_best_mode number;
  l_save_sha varchar2(64);

  procedure mark(p_label varchar2) is
  begin
    for r in (
      select p.x,p.y,p.angle,p.health,p.alive,p.kill_count,p.item_count,
             p.secret_count,p.blue_key,p.yellow_key,p.red_key,
             p.ammo_bullets,p.ammo_shells,p.selected_weapon,p.weapon_mask,
             p.armor,p.armor_type,
             g.current_tic,g.map_status,
             (select count(*) from active_movers a
               where a.session_token=p.session_token) mover_count
      from players p
      join game_sessions g on g.session_token=p.session_token
      where p.session_token=l_session and p.player_id=0
    ) loop
      dbms_output.put_line('MARK|'||p_label||'|seq='||r.current_tic||
        '|command_seq='||l_seq||'|pos='||
        r.x||','||r.y||'|a='||r.angle||'|hp='||r.health||'|alive='||
        r.alive||'|k='||r.kill_count||'|i='||r.item_count||'|s='||
        r.secret_count||'|keys='||r.blue_key||r.yellow_key||r.red_key||
        '|ammo='||r.ammo_bullets||','||r.ammo_shells||'|weapon='||
        r.selected_weapon||','||r.weapon_mask||
        '|armor='||r.armor||','||r.armor_type||
        '|tic='||r.current_tic||'|status='||r.map_status||'|movers='||
        r.mover_count);
    end loop;
  end;

  procedure graph_route(p_label varchar2) is
    l_sector number;
  begin
    select b.sector_id into l_sector
    from players p cross apply table(doom_bsp_locate(p.x,p.y)) b
    where p.session_token=l_session and p.player_id=0 and rownum=1;
    dbms_output.put_line('GRAPH_START|'||p_label||'|sector='||l_sector);
    for r in (
      select l.linedef_id,rs.sector_id right_sector,ls.sector_id left_sector,
             v1.x x1,v1.y y1,v2.x x2,v2.y y2,
             sr.floor_height right_floor,sl.floor_height left_floor,
             least(sr.ceiling_height,sl.ceiling_height)-
               greatest(sr.floor_height,sl.floor_height) opening
      from doom_map_linedef l
      join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
      join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
      join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join sector_state sr on sr.session_token=l_session and sr.sector_id=rs.sector_id
      join sector_state sl on sl.session_token=l_session and sl.sector_id=ls.sector_id
      where bitand(l.flags,1)=0
        and sqrt(power(v2.x-v1.x,2)+power(v2.y-v1.y,2))>32
        and least(sr.ceiling_height,sl.ceiling_height)-
              greatest(sr.floor_height,sl.floor_height)>=56
      order by l.linedef_id
    ) loop
      dbms_output.put_line('GRAPH_PORTAL|line='||r.linedef_id||'|sectors='||
        r.right_sector||','||r.left_sector||'|xy='||r.x1||','||r.y1||'->'||
        r.x2||','||r.y2||'|floors='||r.right_floor||','||r.left_floor||
        '|opening='||r.opening);
    end loop;
    for e in (
      select l.linedef_id,rs.sector_id right_sector,ls.sector_id left_sector,
             v1.x x1,v1.y y1,v2.x x2,v2.y y2,
             sr.floor_height right_floor,sr.ceiling_height right_ceiling,
             sl.floor_height left_floor,sl.ceiling_height left_ceiling
      from doom_map_linedef l
      join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
      join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
      join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join sector_state sr on sr.session_token=l_session and sr.sector_id=rs.sector_id
      join sector_state sl on sl.session_token=l_session and sl.sector_id=ls.sector_id
      where rs.sector_id=l_sector or ls.sector_id=l_sector
      order by l.linedef_id
    ) loop
      dbms_output.put_line('GRAPH_EDGE|line='||e.linedef_id||'|sectors='||
        e.right_sector||','||e.left_sector||'|xy='||e.x1||','||e.y1||'->'||
        e.x2||','||e.y2||'|heights='||e.right_floor||':'||e.right_ceiling||
        ','||e.left_floor||':'||e.left_ceiling);
    end loop;
  end;

  procedure sight(p_label varchar2) is
    l_x number;l_y number;l_angle number;l_wall number;l_line number;l_special number;
  begin
    select x,y,angle into l_x,l_y,l_angle from players
      where session_token=l_session and player_id=0;
    select hit_t,linedef_id into l_wall,l_line from (
      select hit_t,linedef_id from table(doom_r1_hits(l_session))
      where column_no=160 and is_solid=1 order by hit_t,linedef_id) where rownum=1;
    select special into l_special from doom_map_linedef where linedef_id=l_line;
    dbms_output.put_line('SIGHT|'||p_label||'|angle='||l_angle||'|wall='||l_wall||
      '|line='||l_line||'|special='||l_special);
    for m in (
      select m.mobj_id,m.thing_type,m.x,m.y,m.health,
        (m.x-l_x)*cos(l_angle*acos(-1)/180)+
          (m.y-l_y)*sin(l_angle*acos(-1)/180) depth,
        abs((m.x-l_x)*sin(l_angle*acos(-1)/180)-
          (m.y-l_y)*cos(l_angle*acos(-1)/180)) miss,
        m.radius
      from mobjs m join doom_thing_type_def d on d.thing_type=m.thing_type
      where m.session_token=l_session and d.category='monster' and m.health>0
      order by depth,m.mobj_id
      fetch first 8 rows only
    ) loop
      dbms_output.put_line('TARGET|'||m.mobj_id||'|'||m.thing_type||'|pos='||
        m.x||','||m.y||'|hp='||m.health||'|depth='||round(m.depth,3)||
        '|miss='||round(m.miss,3)||'|radius='||m.radius||'|wall='||l_wall);
    end loop;
  end;

  procedure go(p_count number,p_turn number default 0,
    p_forward number default 0,p_strafe number default 0,
    p_run number default 0,p_fire number default 0,
    p_use number default 0,p_weapon number default 0) is
    l_done number := 0;
    l_take number;
    l_commands clob;
  begin
    while l_done<p_count loop
      l_take:=least(4,p_count-l_done);
      l_commands:='{"v":1,"commands":[';
      for i in 1..l_take loop
        if i>1 then l_commands:=l_commands||',';end if;
        l_commands:=l_commands||'{"seq":'||to_char(l_seq+i,'TM9')||
          ',"turn":'||to_char(p_turn,'TM9')||
          ',"forward":'||to_char(p_forward,'TM9')||
          ',"strafe":'||to_char(p_strafe,'TM9')||
          ',"run":'||to_char(p_run,'TM9')||
          ',"fire":'||to_char(p_fire,'TM9')||
          ',"use":'||to_char(p_use,'TM9')||
          ',"weapon":'||to_char(p_weapon,'TM9')||
          ',"pause":0,"automap":0,"menu":"NONE","cheat":""}';
      end loop;
      l_commands:=l_commands||']}';
      doom_tic_tx.apply_batch(l_session,l_commands,l_payload);
      l_seq:=l_seq+l_take;
      l_done:=l_done+l_take;
    end loop;
  end;
begin
  select session_token into l_session from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=96 and s.saved_tic=0 order by g.created_at desc
  ) where rownum=1;
  doom_history.load_game(l_session,96,l_payload);
  select last_command_seq,current_tic into l_seq,l_tic from game_sessions
    where session_token=l_session;
  dbms_output.put_line('SESSION|'||l_session||
    '|TIC0_AUTHORITATIVE=1|PUBLIC_TX_ONLY=1|COMMAND_FRONTIER='||l_seq);
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
  mark('medkit-opening');
  go(5,p_forward=>-1,p_run=>1);
  mark('stimpack-west');
  go(8,p_turn=>-1,p_fire=>1);
  mark('face-lift-southeast');
  go(16,p_forward=>1,p_run=>1,p_fire=>1);
  mark('cross-lift-boundary');
  go(1,p_use=>1);
  mark('use-inside-lift');
  go(8,p_turn=>1,p_fire=>1);
  go(8,p_forward=>1,p_run=>1,p_fire=>1);
  mark('cross-east-lift-door');
  go(8,p_turn=>1,p_fire=>1);
  go(14,p_forward=>1,p_run=>1,p_fire=>1);
  mark('north-from-lift');
  go(8,p_turn=>-1,p_fire=>1);
  go(13,p_forward=>1,p_run=>1,p_fire=>1);
  go(12,p_fire=>1);
  mark('east-to-berserk');
  go(6,p_turn=>1,p_fire=>1);
  go(20,p_fire=>1);
  go(6,p_turn=>-1,p_fire=>1);
  mark('opening-clear');
  doom_history.save_game(l_session,97,l_save_sha);
  execute immediate 'set constraints all immediate';
  select current_tic into l_tic from game_sessions where session_token=l_session;
  dbms_output.put_line('EVAL_TUNING_SEGMENT_SAVED|PUBLIC_TX_ONLY=1|session='||
    l_session||'|slot=97|tic='||l_tic||'|command_seq='||l_seq||
    '|state_sha='||l_save_sha);
  commit;
  return;
  go(8,p_turn=>-1);
  go(4,p_forward=>1,p_run=>1);
  go(16,p_turn=>1);
  go(12,p_forward=>1,p_run=>1);
  mark('dogleg-around-wall');
  go(8,p_turn=>-1);
  go(20,p_forward=>1,p_run=>1,p_fire=>1);
  mark('central-east');
  go(16,p_turn=>1);
  go(5,p_forward=>1,p_run=>1);
  mark('east-door-approach');
  go(1,p_use=>1);
  go(40);
  go(5,p_strafe=>-1,p_run=>1,p_fire=>1);
  go(10,p_forward=>1,p_run=>1,p_fire=>1);
  mark('through-east-door');
  go(1,p_forward=>1,p_run=>1);
  go(1,p_forward=>-1,p_run=>1);
  go(1,p_weapon=>3);
  go(6);
  go(24,p_fire=>1);
  mark('north-room-clear');
  go(8,p_turn=>-1);
  go(5,p_forward=>1,p_run=>1,p_fire=>1);
  go(1,p_forward=>1,p_run=>1,p_fire=>1,p_weapon=>2);
  go(24,p_forward=>1,p_run=>1,p_fire=>1);
  go(23,p_forward=>1,p_strafe=>1,p_run=>1,p_fire=>1);
  go(6,p_forward=>1,p_strafe=>-1,p_run=>1,p_fire=>1);
  mark('green-armor');
  go(3,p_forward=>1,p_strafe=>1,p_run=>1);
  go(5,p_forward=>-1,p_strafe=>-1,p_run=>1);
  go(2,p_forward=>1,p_strafe=>1,p_run=>1);
  go(3,p_forward=>1,p_strafe=>-1,p_run=>1);
  go(5,p_forward=>-1,p_strafe=>1,p_run=>1);
  go(2,p_forward=>1,p_strafe=>-1,p_run=>1);
  mark('health-bonus-cluster');
  go(16,p_turn=>-1,p_fire=>1);
  go(47,p_forward=>1,p_run=>1,p_fire=>1);
  mark('blue-key-approach');
  go(23,p_strafe=>-1,p_run=>1);
  go(5,p_forward=>-1,p_strafe=>-1,p_run=>1);
  mark('chaingun');
  go(1,p_weapon=>4);
  go(6);
  go(16,p_turn=>-1,p_fire=>1);
  go(8,p_fire=>1);
  mark('key-route-clear');
  go(18,p_strafe=>-1,p_run=>1);
  go(11,p_forward=>1,p_strafe=>-1,p_run=>1);
  go(14,p_forward=>1,p_strafe=>1,p_run=>1);
  mark('blue-key-east');
  go(3,p_forward=>1,p_strafe=>1,p_run=>1);
  go(1,p_strafe=>-1,p_run=>1);
  mark('blue-key');
  go(21,p_strafe=>1,p_run=>1);
  go(31,p_forward=>-1,p_strafe=>1,p_run=>1);
  mark('key-west-corridor');
  go(4,p_forward=>-1,p_strafe=>-1,p_run=>1);
  go(10,p_forward=>-1,p_strafe=>1,p_run=>1);
  mark('west-corner-north');
  go(2,p_turn=>-1,p_fire=>1);
  go(28,p_forward=>1,p_strafe=>1,p_run=>1,p_fire=>1);
  mark('west-threat-burst');
  go(8,p_forward=>1,p_strafe=>-1,p_run=>1);
  go(14,p_forward=>1,p_strafe=>1,p_run=>1);
  mark('search-survivor-715');
  for step in 1..12 loop
    go(1,p_forward=>-1,p_strafe=>-1,p_run=>1,
      p_fire=>case when mod(step,3)=1 then 1 else 0 end);
  end loop;
  mark('endpoint-east');
  go(14,p_forward=>-1,p_strafe=>1,p_run=>1);
  mark('endpoint-north');
  go(22,p_forward=>1,p_strafe=>1,p_run=>1);
  mark('endpoint-west');
  doom_history.save_game(l_session,98,l_save_sha);
  execute immediate 'set constraints all immediate';
  dbms_output.put_line('EVAL_TUNING_PREFIX_SAVED|NON_AUTHORITATIVE_MANUAL_HISTORY=1|session='||
    l_session||'|slot=98|seq='||l_seq||'|state_sha='||l_save_sha);
  commit;
  return;
  go(2,p_forward=>-1,p_strafe=>-1,p_run=>1);
  go(16,p_forward=>-1,p_strafe=>1,p_run=>1);
  go(18,p_forward=>1,p_strafe=>1,p_run=>1);
  mark('blue-route-above-secret');
  go(10,p_turn=>1);
  go(2,p_forward=>1,p_run=>1);
  go(8,p_turn=>-1);
  go(1,p_use=>1);
  go(65);
  mark('secret-door-open');
  doom_history.save_game(l_session,99,l_save_sha);
  execute immediate 'set constraints all immediate';
  dbms_output.put_line('EVAL_PREFIX_SAVED|session='||l_session||'|slot=99|seq='||
    l_seq||'|state_sha='||l_save_sha);
  commit;
  return;
  go(12,p_forward=>1,p_run=>1);
  mark('portal-442-483-cross');
  go(4,p_forward=>1,p_strafe=>1,p_run=>1);
  mark('sector86-west-tangent');
  go(8,p_turn=>1);
  go(2,p_strafe=>1,p_run=>1);
  go(34,p_forward=>1,p_run=>1);
  go(6,p_strafe=>1,p_run=>1);
  mark('blue-route-door-vector');
  mark('blue-door-search-approach');
  go(1,p_use=>1);
  mark('blue-door-search-use');
  for e in (
    select event_type,count(*) event_count,min(tic) first_tic,max(tic) last_tic
    from game_events where session_token=l_session group by event_type
    order by event_type
  ) loop
    dbms_output.put_line('EVENT|'||e.event_type||'|'||e.event_count||'|'||
      e.first_tic||'|'||e.last_tic);
  end loop;
  for m in (
    select thing_type,count(*) dead_count from mobjs
    where session_token=l_session and death_processed=1
    group by thing_type order by thing_type
  ) loop
    dbms_output.put_line('DEAD|'||m.thing_type||'|'||m.dead_count);
  end loop;
  for a in (
    select mover_id,sector_id,mover_kind,direction,target_height,timer_tics,
      source_linedef_id from active_movers where session_token=l_session
    order by mover_id
  ) loop
    dbms_output.put_line('MOVER|'||a.mover_id||'|'||a.sector_id||'|'||
      a.mover_kind||'|'||a.direction||'|'||a.target_height||'|'||
      a.timer_tics||'|'||a.source_linedef_id);
  end loop;
  for m in (
    select m.mobj_id,m.thing_type,m.x,m.y,m.health,m.awake,m.state_id
    from mobjs m join doom_thing_type_def d on d.thing_type=m.thing_type
    where m.session_token=l_session and d.category='monster' and m.awake=1
    order by m.mobj_id
  ) loop
    dbms_output.put_line('MONSTER|'||m.mobj_id||'|'||m.thing_type||'|'||m.x||
      '|'||m.y||'|'||m.health||'|'||m.awake||'|'||m.state_id);
  end loop;
end;
/
rollback;
