whenever sqlerror exit failure rollback
set define off

create or replace procedure doom_renderer_snapshot_fill(
  p_session in varchar2,p_snapshot in out nocopy blob
) authid definer as
  l_buffer raw(32767);l_tic number;

  procedure flush_buffer is
  begin
    if l_buffer is not null then
      dbms_lob.writeappend(p_snapshot,utl_raw.length(l_buffer),l_buffer);
      l_buffer:=null;
    end if;
  end;

  procedure append_raw(p_value raw) is
    l_length pls_integer:=coalesce(utl_raw.length(p_value),0);
  begin
    if coalesce(utl_raw.length(l_buffer),0)+l_length>1024 then flush_buffer;end if;
    if l_length>0 then l_buffer:=utl_raw.concat(l_buffer,p_value);end if;
  end;

  procedure append_int(p_value number) is
  begin
    append_raw(utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian));
  end;

  procedure append_double(p_value number) is
  begin
    append_raw(utl_raw.cast_from_binary_double(cast(p_value as binary_double),
      utl_raw.big_endian));
  end;

  procedure append_string(p_value varchar2) is
    l_raw raw(32767):=utl_i18n.string_to_raw(p_value,'AL32UTF8');
  begin
    append_int(utl_raw.length(l_raw));append_raw(l_raw);
  end;
begin
  if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
    raise_application_error(-20000,'invalid renderer snapshot session');
  end if;
  if p_snapshot is null then raise_application_error(-20000,'snapshot locator required');end if;
  -- DRS2 binds every packed buffer to its owning game. The renderer rejects a
  -- locator presented under another session before publishing any frame bytes.
  dbms_lob.trim(p_snapshot,0);append_int(1146245938);append_string(p_session);

  for p in (
    select s.current_tic,lower(s.game_mode) game_mode,p.selected_weapon,
      case when s.map_status='DONE' then 1 else 0 end complete,s.paused,
      to_char(p.x,'TM9','NLS_NUMERIC_CHARACTERS=''.,''') x_text,
      to_char(p.y,'TM9','NLS_NUMERIC_CHARACTERS=''.,''') y_text,
      p.z+p.view_height+p.view_bob eye_z,p.angle,p.health,p.armor,
      p.blue_key,p.yellow_key,p.red_key,p.ammo_bullets,p.ammo_shells,
      p.ammo_rockets,p.ammo_cells
    from game_sessions s join players p on p.session_token=s.session_token
      and p.player_id=s.current_player_id where s.session_token=p_session
  ) loop
    l_tic:=p.current_tic;append_int(0);append_int(p.current_tic);
    append_string(p.game_mode);append_string(p.selected_weapon);
    append_int(p.complete);append_int(p.paused);append_string(p.x_text);
    append_string(p.y_text);append_double(p.eye_z);append_double(p.angle);
    append_int(p.health);append_int(p.armor);append_int(p.blue_key);
    append_int(p.yellow_key);append_int(p.red_key);append_int(p.ammo_bullets);
    append_int(p.ammo_shells);append_int(p.ammo_rockets);append_int(p.ammo_cells);
  end loop;
  if l_tic is null then raise_application_error(-20000,'renderer session not found');end if;

  for s in (select sector_id,floor_height,ceiling_height,light_level
    from sector_state where session_token=p_session order by sector_id) loop
    append_int(1);append_int(s.sector_id);append_double(s.floor_height);
    append_double(s.ceiling_height);append_int(s.light_level);
  end loop;
  for m in (select mobj_id,state_id,x,y,z,angle from mobjs
    where session_token=p_session order by mobj_id) loop
    append_int(2);append_int(m.mobj_id);append_string(m.state_id);
    append_double(m.x);append_double(m.y);append_double(m.z);append_double(m.angle);
  end loop;
  for a in (select event_ordinal,asset_name,volume,separation from audio_events
    where session_token=p_session and tic=l_tic order by event_ordinal) loop
    append_int(3);append_int(a.event_ordinal);append_string(a.asset_name);
    append_int(a.volume);append_int(a.separation);
  end loop;
  append_int(4);flush_buffer;
end;
/

-- Compact retained-scene update. Sector and mobj records use the same kind
-- layouts as DRS2 and may be appended by the future authoritative array owner;
-- this relational bridge emits only the player/presentation record plus audio.
create or replace procedure doom_renderer_delta_fill(
  p_session in varchar2,p_delta in out nocopy blob
) authid definer as
  l_buffer raw(32767);l_tic number;
  procedure flush_buffer is begin if l_buffer is not null then
    dbms_lob.writeappend(p_delta,utl_raw.length(l_buffer),l_buffer);l_buffer:=null;end if;end;
  procedure append_raw(p_value raw) is l_length pls_integer:=coalesce(utl_raw.length(p_value),0);
  begin if coalesce(utl_raw.length(l_buffer),0)+l_length>1024 then flush_buffer;end if;
    if l_length>0 then l_buffer:=utl_raw.concat(l_buffer,p_value);end if;end;
  procedure append_int(p_value number) is begin append_raw(
    utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian));end;
  procedure append_double(p_value number) is begin append_raw(utl_raw.cast_from_binary_double(
    cast(p_value as binary_double),utl_raw.big_endian));end;
  procedure append_string(p_value varchar2) is l_raw raw(32767):=
    utl_i18n.string_to_raw(p_value,'AL32UTF8');
  begin append_int(utl_raw.length(l_raw));append_raw(l_raw);end;
begin
  if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
    raise_application_error(-20000,'invalid renderer delta session');end if;
  if p_delta is null then raise_application_error(-20000,'delta locator required');end if;
  dbms_lob.trim(p_delta,0);append_int(1146242097);append_string(p_session);
  for p in (select s.current_tic,lower(s.game_mode) game_mode,p.selected_weapon,
      case when s.map_status='DONE' then 1 else 0 end complete,s.paused,
      to_char(p.x,'TM9','NLS_NUMERIC_CHARACTERS=''.,''') x_text,
      to_char(p.y,'TM9','NLS_NUMERIC_CHARACTERS=''.,''') y_text,
      p.z+p.view_height+p.view_bob eye_z,p.angle,p.health,p.armor,
      p.blue_key,p.yellow_key,p.red_key,p.ammo_bullets,p.ammo_shells,
      p.ammo_rockets,p.ammo_cells from game_sessions s join players p
      on p.session_token=s.session_token and p.player_id=s.current_player_id
      where s.session_token=p_session) loop
    l_tic:=p.current_tic;append_int(0);append_int(p.current_tic);append_string(p.game_mode);
    append_string(p.selected_weapon);append_int(p.complete);append_int(p.paused);
    append_string(p.x_text);append_string(p.y_text);append_double(p.eye_z);
    append_double(p.angle);append_int(p.health);append_int(p.armor);append_int(p.blue_key);
    append_int(p.yellow_key);append_int(p.red_key);append_int(p.ammo_bullets);
    append_int(p.ammo_shells);append_int(p.ammo_rockets);append_int(p.ammo_cells);
  end loop;
  if l_tic is null then raise_application_error(-20000,'renderer delta session not found');end if;
  for a in (select event_ordinal,asset_name,volume,separation from audio_events
    where session_token=p_session and tic=l_tic order by event_ordinal) loop
    append_int(3);append_int(a.event_ordinal);append_string(a.asset_name);
    append_int(a.volume);append_int(a.separation);
  end loop;
  append_int(4);flush_buffer;
end;
/
