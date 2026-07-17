set serveroutput on size unlimited
set feedback on
set sqlblanklines on
set define off

declare
  k_session constant varchar2(32) := 'f5c560edf961fb6373e0c0cf47814af3';
  l_payload blob;
  l_seq number;
  l_state_sha varchar2(64);

  procedure go(
    p_count number,
    p_turn number default 0,
    p_forward number default 0,
    p_fire number default 0,
    p_use number default 0
  ) is
    l_commands clob;
  begin
    for step in 1..p_count loop
      l_commands := '{"v":1,"commands":[{"seq":' ||
        to_char(l_seq + 1, 'TM9') || ',"turn":' ||
        to_char(p_turn, 'TM9') || ',"forward":' ||
        to_char(p_forward, 'TM9') ||
        ',"strafe":0,"run":1,"fire":' ||
        to_char(p_fire, 'TM9') || ',"use":' ||
        to_char(p_use, 'TM9') ||
        ',"weapon":3,"pause":0,"automap":0,' ||
        '"menu":"NONE","cheat":""}]}';
      doom_tic_tx.apply_batch(k_session, l_commands, l_payload);
      l_seq := l_seq + 1;
    end loop;
  end;
begin
  doom_history.load_game(k_session, 96, l_payload);
  select last_command_seq
    into l_seq
    from game_sessions
   where session_token = k_session;

  -- Retreat through the already-cleared north hall, open sector 78's door,
  -- and take the medkit before returning to the blue-door/exit route.
  go(23, p_turn => -1);
  go(33, p_forward => 1);
  go(1, p_use => 1);
  go(28);
  go(10, p_forward => 1);

  -- Reopen the medkit alcove, clear its south-east wall corner, and use the
  -- sector-80 door to collect the east stimpack without waking the south room.
  go(32, p_turn => 1);
  go(7, p_forward => 1);
  go(1, p_use => 1);
  go(28);
  go(6, p_forward => 1);
  go(16, p_turn => 1);
  go(36, p_forward => 1);
  go(16, p_turn => 1);
  go(1, p_use => 1);
  go(28);
  go(12, p_forward => 1);

  for result_row in (
    select
      session_row.current_tic,
      player.x,
      player.y,
      player.angle,
      player.health,
      player.alive,
      player.kill_count,
      player.item_count,
      player.secret_count,
      player.blue_key,
      player.ammo_shells
    from game_sessions session_row
    join players player
      on player.session_token = session_row.session_token
     and player.player_id = session_row.current_player_id
    where session_row.session_token = k_session
  ) loop
    if result_row.current_tic <> 3158 or
       abs(result_row.x - 480.01582430798503) > 0.000000000001 or
       result_row.y <> 2208 or
       result_row.angle <> 90 or
       result_row.health <> 43 or
       result_row.alive <> 1 or
       result_row.kill_count <> 33 or
       result_row.item_count <> 28 or
       result_row.secret_count <> 1 or
       result_row.blue_key <> 1 or
       result_row.ammo_shells <> 14 then
      raise_application_error(-20881, 'health-recovery checkpoint diverged');
    end if;
    dbms_output.put_line(
      'T81_HEALTH_RECOVERY|tic=' || result_row.current_tic ||
      '|pos=' || result_row.x || ',' || result_row.y ||
      '|angle=' || result_row.angle ||
      '|health=' || result_row.health ||
      '|kills=' || result_row.kill_count ||
      '|items=' || result_row.item_count ||
      '|secrets=' || result_row.secret_count ||
      '|blue=' || result_row.blue_key ||
      '|shells=' || result_row.ammo_shells
    );
  end loop;

  doom_history.save_game(k_session, 99, l_state_sha);
  execute immediate 'set constraints all immediate';
  commit;
  dbms_output.put_line(
    'T81_HEALTH_RECOVERY_SAVED|slot=99|state_sha=' || l_state_sha
  );
end;
/

exit
