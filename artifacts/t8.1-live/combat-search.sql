set serveroutput on size unlimited
set feedback on
set sqlblanklines on
whenever sqlerror continue
prompt BEFORE_COMBAT_SEARCH_BLOCK
declare
  l_session varchar2(32);
  l_payload blob;
  l_seq number;
  l_sha varchar2(64);

  procedure go(p_count number,p_turn number default 0,
    p_forward number default 0,p_strafe number default 0,
    p_run number default 0,p_fire number default 0,
    p_weapon number default 0) is
    l_done number:=0; l_take number; l_commands clob;
  begin
    while l_done<p_count loop
      l_take:=least(4,p_count-l_done);
      l_commands:='{"v":1,"commands":[';
      for i in 1..l_take loop
        if i>1 then l_commands:=l_commands||','; end if;
        l_commands:=l_commands||'{"seq":'||to_char(l_seq+i,'TM9')||
          ',"turn":'||to_char(p_turn,'TM9')||
          ',"forward":'||to_char(p_forward,'TM9')||
          ',"strafe":'||to_char(p_strafe,'TM9')||
          ',"run":'||to_char(p_run,'TM9')||
          ',"fire":'||to_char(p_fire,'TM9')||
          ',"use":0,"weapon":'||to_char(p_weapon,'TM9')||
          ',"pause":0,"automap":0,"menu":"NONE","cheat":""}';
      end loop;
      l_commands:=l_commands||']}';
      doom_tic_tx.apply_batch(l_session,l_commands,l_payload);
      l_seq:=l_seq+l_take; l_done:=l_done+l_take;
    end loop;
  end;

  procedure result(p_candidate number,p_stage varchar2) is
  begin
    for r in (
      select g.current_tic,p.x,p.y,p.angle,p.health,p.alive,p.kill_count,
        p.ammo_shells,p.selected_weapon,
        (select floor_height from sector_state s where s.session_token=l_session
          and s.sector_id=103) floor103
      from players p join game_sessions g on g.session_token=p.session_token
      where p.session_token=l_session and p.player_id=0
    ) loop
      dbms_output.put_line('COMBAT_SEARCH|'||p_candidate||'|'||p_stage||
        '|tic='||r.current_tic||'|pos='||r.x||','||r.y||'|angle='||r.angle||
        '|hp='||r.health||'|alive='||r.alive||'|kills='||r.kill_count||
        '|shells='||r.ammo_shells||'|weapon='||r.selected_weapon||
        '|floor103='||r.floor103);
    end loop;
  end;
begin
  select session_token into l_session from (
    select s.session_token from save_slots s join game_sessions g
      on g.session_token=s.session_token
    where s.slot_number=45 and s.saved_tic=1407 order by g.created_at desc
  ) where rownum=1;

  for c in 1..3 loop
    doom_history.load_game(l_session,45,l_payload);
    commit;
    select last_command_seq into l_seq from game_sessions
      where session_token=l_session;
    go(1,p_forward=>1,p_run=>1,p_fire=>1,p_weapon=>3);
    go(6,p_forward=>1,p_run=>1,p_fire=>1);
    result(c,'baseline');
    if c=1 then
      for i in 1..16 loop
        if mod(i,2)=0 then go(1,p_turn=>1,p_forward=>1,p_run=>1,p_fire=>1);
        else go(1,p_turn=>1,p_forward=>-1,p_run=>1,p_fire=>1); end if;
      end loop;
    elsif c=2 then
      go(16,p_turn=>1,p_forward=>1,p_strafe=>1,p_run=>1,p_fire=>1);
    elsif c=3 then
      go(16,p_turn=>1,p_forward=>-1,p_strafe=>1,p_run=>1,p_fire=>1);
    elsif c=4 then
      go(16,p_turn=>1,p_strafe=>1,p_run=>1,p_fire=>1);
    elsif c=5 then
      go(16,p_turn=>1,p_forward=>1,p_run=>1,p_fire=>1);
    elsif c=6 then
      go(16,p_turn=>-1,p_forward=>1,p_strafe=>1,p_run=>1,p_fire=>1);
    elsif c=7 then
      go(16,p_turn=>-1,p_forward=>-1,p_strafe=>1,p_run=>1,p_fire=>1);
    else
      go(16,p_turn=>-1,p_strafe=>-1,p_run=>1,p_fire=>1);
    end if;
    result(c,'after16');
    doom_history.save_game(l_session,40+c,l_sha);
    commit;
    dbms_output.put_line('COMBAT_SEARCH_SAVE|candidate='||c||
      '|slot='||(40+c)||'|sha='||l_sha);
  end loop;
  commit;
end;
/
prompt AFTER_COMBAT_SEARCH_BLOCK
exit
