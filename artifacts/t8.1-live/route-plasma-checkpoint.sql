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
        if step > 1 then
          l_commands := l_commands || ',';
        end if;
        l_commands := l_commands || '{"seq":' ||
          to_char(l_seq + 1, 'TM9') || ',"turn":' ||
          to_char(p_turn, 'TM9') || ',"forward":' ||
          to_char(p_forward, 'TM9') ||
          ',"strafe":0,"run":1,"fire":' ||
          to_char(p_fire, 'TM9') || ',"use":' ||
          to_char(p_use, 'TM9') || ',"weapon":' ||
          to_char(p_weapon, 'TM9') ||
          ',"pause":0,"automap":0,"menu":"NONE","cheat":""}';
        l_seq := l_seq + 1;
      end loop;
      l_commands := l_commands || ']}';
      doom_tic_tx.apply_batch(k_session, l_commands, l_payload);
    end loop;
  end;
begin
  doom_history.load_game(k_session, 99, l_payload);
  select last_command_seq
    into l_seq
    from game_sessions
   where session_token = k_session;

  -- Leave alcove 80, take the nearby plasma rifle in sector 87, and select it
  -- early enough for the database-authored lower/raise sequence to complete.
  go(32, p_turn => 1);
  go(6, p_forward => 1);
  go(1, p_use => 1);
  go(28);
  go(7, p_forward => 1);
  go(4, p_forward => 1);
  go(16, p_turn => 1);
  go(2, p_forward => 1);
  go(1, p_weapon => 6);
  go(16, p_turn => 1);
  go(4, p_forward => 1);
  go(16, p_turn => 1);
  go(2, p_forward => 1);

  -- Detour through alcove 81 for its stimpack, reopen the timed door on the
  -- way out, and stop centered on the blue-door approach corridor.
  go(32, p_turn => 1);
  go(16, p_forward => 1);
  go(16, p_turn => 1);
  go(6, p_forward => 1);
  go(1, p_use => 1);
  go(28);
  go(9, p_forward => 1);
  go(32, p_turn => 1);
  go(6, p_forward => 1);
  go(1, p_use => 1);
  go(28);
  go(7, p_forward => 1);
  go(16, p_turn => -1);
  go(52, p_forward => 1);

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
      player.ammo_shells,
      player.ammo_cells,
      player.weapon_mask,
      player.selected_weapon
    from game_sessions session_row
    join players player
      on player.session_token = session_row.session_token
     and player.player_id = session_row.current_player_id
    where session_row.session_token = k_session
  ) loop
    if result_row.current_tic <> 3543 or
       abs(result_row.x - (-95.98417569201497)) > 0.000000000001 or
       result_row.y <> 2000 or
       result_row.angle <> 180 or
       result_row.health <> 53 or
       result_row.alive <> 1 or
       result_row.kill_count <> 33 or
       result_row.item_count <> 30 or
       result_row.secret_count <> 1 or
       result_row.blue_key <> 1 or
       result_row.ammo_shells <> 14 or
       result_row.ammo_cells <> 240 or
       result_row.weapon_mask <> 39 or
       result_row.selected_weapon <> 'PLASMA_RIFLE' then
      raise_application_error(-20882, 'plasma checkpoint diverged');
    end if;
    dbms_output.put_line(
      'T81_PLASMA_CHECKPOINT|tic=' || result_row.current_tic ||
      '|pos=' || result_row.x || ',' || result_row.y ||
      '|angle=' || result_row.angle ||
      '|health=' || result_row.health ||
      '|kills=' || result_row.kill_count ||
      '|items=' || result_row.item_count ||
      '|cells=' || result_row.ammo_cells ||
      '|weapon=' || result_row.selected_weapon || ',' || result_row.weapon_mask
    );
  end loop;

  doom_history.save_game(k_session, 99, l_state_sha);
  if l_state_sha <>
     '8c25c91be470e6b0f9808e229b3e2db4dac6722a9b0fda04ae7295eec1bc996a' then
    raise_application_error(-20883, 'plasma checkpoint SHA diverged');
  end if;
  execute immediate 'set constraints all immediate';
  commit;
  dbms_output.put_line(
    'T81_PLASMA_CHECKPOINT_SAVED|slot=99|state_sha=' || l_state_sha
  );
end;
/

exit
