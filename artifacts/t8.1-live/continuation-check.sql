set serveroutput on size unlimited
set feedback on
set sqlblanklines on
declare
  l_session varchar2(32);
  l_payload blob;
  l_seq number;
  l_tic number;
  l_save_sha varchar2(64);

  procedure mark(p_label varchar2) is
  begin
    for r in (
      select p.x,p.y,p.z,p.angle,p.health,p.alive,p.kill_count,p.item_count,
        p.secret_count,p.blue_key,p.ammo_bullets,p.ammo_shells,
        p.selected_weapon,p.weapon_mask,p.armor,p.armor_type,g.current_tic,
        g.map_status,(select count(*) from active_movers a
          where a.session_token=p.session_token) mover_count,
        (select listagg(a.source_linedef_id||':'||a.sector_id||':'||a.direction||
          ':'||a.timer_tics||':'||a.target_height,',')
          within group(order by a.mover_id) from active_movers a
          where a.session_token=p.session_token) mover_sources,
        (select floor_height from sector_state s where s.session_token=p.session_token
          and s.sector_id=98) floor98,
        (select floor_height from sector_state s where s.session_token=p.session_token
          and s.sector_id=103) floor103,
        (select b.sector_id from table(doom_bsp_locate(p.x,p.y)) b
          where rownum=1) sector_id
      from players p join game_sessions g on g.session_token=p.session_token
      where p.session_token=l_session and p.player_id=0
    ) loop
      dbms_output.put_line('PUBLIC_CONT|'||p_label||'|tic='||r.current_tic||
        '|command_seq='||l_seq||'|pos='||r.x||','||r.y||','||r.z||'|angle='||r.angle||
        '|sector='||r.sector_id||'|hp='||r.health||'|alive='||r.alive||
        '|kills='||r.kill_count||'|items='||r.item_count||'|secrets='||
        r.secret_count||'|blue='||r.blue_key||'|ammo='||r.ammo_bullets||','||
        r.ammo_shells||'|weapon='||r.selected_weapon||','||r.weapon_mask||
        '|armor='||r.armor||','||r.armor_type||'|status='||r.map_status||
        '|movers='||r.mover_count||'['||r.mover_sources||']|floors98,103='||
        r.floor98||','||r.floor103);
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
    where s.slot_number=35 and s.saved_tic=1478 order by g.created_at desc
  ) where rownum=1;
  doom_history.load_game(l_session,35,l_payload);
  select last_command_seq,current_tic into l_seq,l_tic from game_sessions
    where session_token=l_session;
  mark('restored-west-sweep-circle');
  go(16,p_turn=>-1,p_forward=>1,p_strafe=>1,p_run=>1,p_fire=>1);
  mark('preclear-shotgunner-aim-circle');

  doom_history.save_game(l_session,34,l_save_sha);
  execute immediate 'set constraints all immediate';
  select current_tic into l_tic from game_sessions where session_token=l_session;
  dbms_output.put_line('EVAL_PUBLIC_CHECKPOINT_SAVED|session='||l_session||
    '|slot=34|tic='||l_tic||'|command_seq='||l_seq||'|state_sha='||l_save_sha);
  commit;
end;
/
