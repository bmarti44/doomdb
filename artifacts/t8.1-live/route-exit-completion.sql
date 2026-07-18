set serveroutput on size unlimited
set define off
variable result varchar2(4000)

declare
  k_session constant varchar2(32) := 'f5c560edf961fb6373e0c0cf47814af3';
  k_state_sha constant varchar2(64) :=
    'ac5d82cba9ab641192e91e02dc6856dd9210dc57b4b7fad156bab0b40373b7e6';
  l_payload blob;
  l_seq number;
  l_terminal_rows number := 0;

  procedure assert_(p_condition boolean, p_message varchar2) is
  begin
    if not p_condition then
      raise_application_error(-20010, p_message);
    end if;
  end;

  procedure go(
    p_count number,
    p_turn number default 0,
    p_forward number default 0,
    p_strafe number default 0,
    p_fire number default 0,
    p_use number default 0,
    p_weapon number default 0
  ) is
    l_commands clob;
    l_width pls_integer;
  begin
    for batch_start in 0..ceil(p_count / 4) - 1 loop
      l_width := least(4, p_count - batch_start * 4);
      l_commands := '{"v":1,"commands":[';
      for step in 1..l_width loop
        if step > 1 then l_commands := l_commands || ','; end if;
        l_commands := l_commands || '{"seq":' ||
          to_char(l_seq + 1, 'TM9') || ',"turn":' ||
          to_char(p_turn, 'TM9') || ',"forward":' ||
          to_char(p_forward, 'TM9') || ',"strafe":' ||
          to_char(p_strafe, 'TM9') ||
          ',"run":1,"fire":' || to_char(p_fire, 'TM9') ||
          ',"use":' || to_char(p_use, 'TM9') ||
          ',"weapon":' || to_char(p_weapon, 'TM9') ||
          ',"pause":0,"automap":0,' ||
          '"menu":"NONE","cheat":""}';
        l_seq := l_seq + 1;
      end loop;
      l_commands := l_commands || ']}';
      doom_tic_tx.apply_batch(k_session, l_commands, l_payload);
    end loop;
  end;

  procedure report is
  begin
    select 'EXIT_COMPLETION|tic=' || session_row.current_tic ||
      '|status=' || session_row.map_status ||
      '|mode=' || session_row.game_mode ||
      '|pos=' || player.x || ',' || player.y ||
      '|angle=' || player.angle ||
      '|health=' || player.health ||
      '|alive=' || player.alive ||
      '|kills=' || player.kill_count ||
      '|items=' || player.item_count ||
      '|secrets=' || player.secret_count ||
      '|blue=' || player.blue_key ||
      '|cells=' || player.ammo_cells ||
      '|sha=' || coalesce((
        select command_row.state_sha
        from tic_commands command_row
        where command_row.session_token = k_session
          and command_row.lineage = session_row.save_lineage
          and command_row.tic = session_row.current_tic
          and command_row.command_ordinal = 0
      ), 'NONE') ||
      '|movers=[' || coalesce((
        select listagg(mover.sector_id || ':' || mover.direction || ':' ||
          mover.timer_tics || ':' || mover.target_height, ',')
          within group(order by mover.mover_id)
        from active_movers mover
        where mover.session_token = k_session
      ), '') || ']' ||
      '|hits=[' || coalesce((
        select listagg(hit.actor_mobj_id || ':' || hit.hit_count || ':' ||
          hit.damage, ',') within group(order by hit.actor_mobj_id)
        from (
          select actor_mobj_id, count(*) hit_count, sum(number_value) damage
          from game_events
          where session_token = k_session
            and tic > 3543
            and event_type = 'MONSTER_HIT'
          group by actor_mobj_id
        ) hit
      ), '') || ']' ||
      '|monsters=[' || coalesce((
        select listagg(monster.mobj_id || ':' || monster.x || ':' ||
          monster.y || ':' || monster.health, ',')
          within group(order by sqrt(power(monster.x - player.x, 2) +
            power(monster.y - player.y, 2)), monster.mobj_id)
        from mobjs monster
        join doom_thing_type_def monster_def
          on monster_def.thing_type = monster.thing_type
        where monster.session_token = k_session
          and monster_def.category = 'monster'
          and monster.health > 0
          and sqrt(power(monster.x - player.x, 2) +
            power(monster.y - player.y, 2)) < 800
      ), '') || ']'
      into :result
      from game_sessions session_row
      join players player
        on player.session_token = session_row.session_token
       and player.player_id = session_row.current_player_id
      where session_row.session_token = k_session;
  end;
begin
  doom_history.load_game(k_session, 99, l_payload);
  select last_command_seq into l_seq
  from game_sessions where session_token = k_session;

  go(1, p_weapon => 3);
  go(16, p_turn => 1);
  go(16, p_forward => 1);
  go(1, p_use => 1);
  go(8, p_forward => -1);
  go(3, p_turn => -1);
  go(12, p_strafe => 1, p_fire => 1);
  go(12, p_strafe => -1, p_fire => 1);
  go(20, p_fire => 1);
  go(2, p_turn => -1, p_fire => 1);
  go(20, p_fire => 1);
  go(1, p_weapon => 6);
  go(5, p_turn => 1);
  go(12, p_strafe => 1);
  go(12, p_strafe => -1);
  go(40, p_fire => 1);
  go(40, p_fire => 1);
  go(3, p_strafe => 1, p_fire => 1);
  go(16, p_forward => 1, p_fire => 1);
  go(13, p_turn => -1, p_fire => 1);
  go(15, p_forward => 1, p_fire => 1);
  go(13, p_turn => 1);
  go(3, p_forward => 1, p_fire => 1);
  go(16, p_turn => 1, p_fire => 1);
  go(8, p_forward => 1, p_fire => 1);
  go(1, p_turn => -1);
  go(8, p_fire => 1);
  go(15, p_turn => -1, p_fire => 1);
  go(4, p_forward => 1);
  go(1, p_use => 1);
  go(8, p_forward => -1, p_fire => 1);
  go(12, p_strafe => 1, p_fire => 1);
  go(12, p_strafe => -1, p_fire => 1);
  go(20, p_forward => 1, p_fire => 1);
  go(5, p_forward => -1, p_fire => 1);
  go(3, p_strafe => 1, p_fire => 1);
  go(40, p_fire => 1);
  go(40, p_fire => 1);
  go(7, p_forward => 1, p_fire => 1);
  go(9, p_turn => 1, p_fire => 1);
  go(12, p_fire => 1);
  go(4, p_turn => 1, p_fire => 1);
  go(20, p_fire => 1);
  go(24, p_turn => -1);
  go(13, p_forward => 1, p_fire => 1);
  -- The E1M1 exit is an S1 switch: face its west wall and activate it.
  go(5, p_turn => -1);
  go(1, p_forward => -1);
  go(1, p_strafe => -1);
  go(1, p_forward => 1);
  go(1, p_use => 1);
  report;

  for terminal in (
    select session_row.current_tic, session_row.map_status,
      session_row.game_mode, player.x, player.y, player.angle,
      player.health, player.alive, player.kill_count, player.item_count,
      player.secret_count, player.blue_key, player.ammo_cells,
      command_row.state_sha,
      (select count(*) from game_events event
        where event.session_token = k_session
          and event.tic = session_row.current_tic
          and event.event_type = 'MAP_COMPLETE') completion_events,
      (select trigger_count from line_state line
        where line.session_token = k_session
          and line.linedef_id = 407) exit_triggers
    from game_sessions session_row
    join players player
      on player.session_token = session_row.session_token
     and player.player_id = session_row.current_player_id
    join tic_commands command_row
      on command_row.session_token = session_row.session_token
     and command_row.lineage = session_row.save_lineage
     and command_row.tic = session_row.current_tic
     and command_row.command_ordinal = 0
    where session_row.session_token = k_session
  ) loop
    l_terminal_rows := l_terminal_rows + 1;
    assert_(terminal.current_tic = 4118, 'terminal tic drifted');
    assert_(terminal.map_status = 'DONE', 'exit did not seal E1M1 completion');
    assert_(terminal.game_mode = 'INTERMISSION',
      'exit command did not enter intermission');
    assert_(abs(terminal.x + 368) < 0.000001 and
      abs(terminal.y - 1296) < 0.000001 and terminal.angle = 180,
      'terminal pose drifted');
    assert_(terminal.health = 49 and terminal.alive = 1,
      'terminal survivability drifted');
    assert_(terminal.kill_count = 42 and terminal.item_count = 34 and
      terminal.secret_count = 1 and terminal.blue_key = 1,
      'terminal progression drifted: kills=' || terminal.kill_count ||
      ',items=' || terminal.item_count || ',secrets=' ||
      terminal.secret_count || ',blue=' || terminal.blue_key);
    assert_(terminal.ammo_cells = 143, 'terminal plasma count drifted');
    assert_(terminal.state_sha = k_state_sha,
      'terminal state SHA drifted: ' || terminal.state_sha);
    assert_(terminal.completion_events = 1 and terminal.exit_triggers = 1,
      'exit activation evidence drifted');
  end loop;
  assert_(l_terminal_rows = 1, 'terminal state row is missing or duplicated');

  dbms_output.put_line('PASS T8.1-EXIT-COMPLETION ' || :result);
  rollback;
end;
/

print result
exit
