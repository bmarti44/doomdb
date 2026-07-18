whenever sqlerror exit failure rollback
set define off

create or replace procedure doom_renderer_json_snapshot_fill(
  p_session in varchar2,p_snapshot in out nocopy blob
) authid definer as
  l_json blob;l_length pls_integer;
begin
  if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
    raise_application_error(-20000,'invalid renderer snapshot session');
  end if;
  if p_snapshot is null then raise_application_error(-20000,'snapshot locator required');end if;
  select json_object(
    'p' value (select json_array(s.current_tic,lower(s.game_mode),p.selected_weapon,
      case when s.map_status='DONE' then 1 else 0 end,s.paused,p.x,p.y,
      p.z+p.view_height+p.view_bob,p.angle,p.health,p.armor,p.blue_key,p.yellow_key,
      p.red_key,p.ammo_bullets,p.ammo_shells,p.ammo_rockets,p.ammo_cells returning clob)
      from game_sessions s join players p on p.session_token=s.session_token
        and p.player_id=s.current_player_id where s.session_token=p_session) format json,
    's' value (select json_arrayagg(
      json_array(sector_id,floor_height,ceiling_height,light_level returning clob)
      order by sector_id returning clob) from sector_state where session_token=p_session) format json,
    'm' value (select json_arrayagg(json_array(mobj_id,state_id,x,y,z,angle returning clob)
      order by mobj_id returning clob) from mobjs where session_token=p_session) format json,
    'a' value (select json_arrayagg(
      json_array(a.event_ordinal,a.asset_name,a.volume,a.separation returning clob)
      order by a.event_ordinal returning clob) from audio_events a
      join game_sessions g on g.session_token=a.session_token and g.save_lineage=a.lineage
      where a.session_token=p_session and a.tic=g.current_tic) format json
    returning blob) into l_json from dual;
  l_length:=dbms_lob.getlength(l_json);dbms_lob.trim(p_snapshot,0);
  dbms_lob.copy(p_snapshot,l_json,l_length,1,1);dbms_lob.freetemporary(l_json);
end;
/
