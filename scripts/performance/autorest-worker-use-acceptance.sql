whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- First bridge gate: one dynamically selected repeatable USE-door proves the
-- public AutoREST -> worker -> SQL-oracle -> retained-renderer transaction.
-- The full special matrix (key denial/allow, exit, lift carry/blocking,
-- WALK 88, switch reset, mover timelines and restart mid-mover) is a separate
-- required gate; this script intentionally does not claim that completion.

declare
  retained_ varchar2(32);oracle_ varchar2(32);payload_ blob;commands_ clob;
  retained_payload_ blob;oracle_payload_ blob;
  old_enabled_ number;old_parity_ number;old_split_use_ number;line_ number;special_ number;
  x_ number;y_ number;angle_ number;sector_ number;length_ number;
  retained_world_ clob;oracle_world_ clob;retained_player_ clob;oracle_player_ clob;
  retained_events_ clob;oracle_events_ clob;
  retained_status_ varchar2(16);oracle_status_ varchar2(16);
  retained_frame_ varchar2(64);oracle_frame_ varchar2(64);
  function world_(p_session varchar2) return clob is result_ clob;
  begin
    select json_object(
      'lines' value (select json_arrayagg(json_array(linedef_id,trigger_count,switch_on)
        order by linedef_id returning clob) from line_state where session_token=p_session) format json,
      'sectors' value (select json_arrayagg(json_array(sector_id,floor_height,ceiling_height)
        order by sector_id returning clob) from sector_state where session_token=p_session) format json,
      'movers' value (select coalesce(json_arrayagg(json_array(mover_id,sector_id,plane,direction,
        speed,target_height,wait_tics,timer_tics,mover_kind,origin_height,source_linedef_id)
        order by mover_id returning clob),to_clob('[]')) from active_movers where session_token=p_session) format json,
      'switches' value (select coalesce(json_arrayagg(json_array(linedef_id,timer_tics,restore_texture)
        order by linedef_id returning clob),to_clob('[]')) from active_switches where session_token=p_session) format json
      returning clob) into result_ from dual;
    return result_;
  end;
  function player_(p_session varchar2) return clob is result_ clob;
  begin
    select json_array(p.x,p.y,p.z,p.angle,p.health,p.alive,p.secret_count,
      p.ammo_bullets,p.ammo_shells,p.ammo_rockets,p.ammo_cells,p.selected_weapon,
      p.pending_weapon,p.weapon_state,p.weapon_state_tics,p.flash_state,p.flash_state_tics,
      p.refire returning clob) into result_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id
      where g.session_token=p_session;return result_;
  end;
  function events_(p_session varchar2) return clob is result_ clob;
  begin
    select coalesce(json_arrayagg(json_array(tic,event_ordinal,event_type,actor_mobj_id,
      target_mobj_id,number_value,text_value) order by tic,event_ordinal returning clob),to_clob('[]'))
      into result_ from game_events where session_token=p_session;return result_;
  end;
  procedure step_(p_session varchar2,p_payload out blob) is
  begin
    commands_:='{"v":1,"commands":[{"seq":1,"turn":0,"forward":0,'||
      '"strafe":0,"run":0,"fire":0,"use":1,"weapon":0,"pause":0,'||
      '"automap":0,"menu":"NONE","cheat":""}]}';
    doom_api.step(p_session,commands_,p_payload);
    if p_payload is null or dbms_lob.getlength(p_payload)=0 then
      raise_application_error(-20000,'empty USE frame');
    end if;
  end;
  procedure cleanup_ is
  begin
    begin if retained_ is not null then doom_unified_worker.request_stop(retained_);end if;
      exception when others then null;end;
    if old_enabled_ is not null then update doom_config set number_value=old_enabled_
      where config_key='UNIFIED_WORKER_ENABLED';end if;
    if old_parity_ is not null then update doom_config set number_value=old_parity_
      where config_key='UNIFIED_WORKER_PARITY_INTERVAL';end if;
    if old_split_use_ is not null then update doom_config set number_value=old_split_use_
      where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';end if;
    if retained_ is not null then delete from game_sessions where session_token=retained_;end if;
    if oracle_ is not null then delete from game_sessions where session_token=oracle_;end if;
    commit;
  exception when others then rollback;
  end;
begin
  -- Select by generic special semantics. The offset is on the actionable
  -- right side; snapping to the engine's 64 angle profiles exercises the
  -- same ray/tie rules as a real client without naming an E1M1 route line.
  for candidate_ in (
    select ml.linedef_id,ml.special,v1.x x1,v1.y y1,v2.x x2,v2.y y2
      from doom_map_linedef ml join doom_map_vertex v1 on v1.vertex_id=ml.start_vertex_id
      join doom_map_vertex v2 on v2.vertex_id=ml.end_vertex_id
      join doom_linedef_special_def d on d.special_id=ml.special
     where ml.special in(1,62,117) and instr(d.semantics,'USE|')=1
     order by case ml.special when 1 then 1 when 62 then 2 else 3 end,ml.linedef_id
  ) loop
    length_:=sqrt(power(candidate_.x2-candidate_.x1,2)+power(candidate_.y2-candidate_.y1,2));
    x_:=(candidate_.x1+candidate_.x2)/2+(candidate_.y2-candidate_.y1)*24/length_;
    y_:=(candidate_.y1+candidate_.y2)/2-(candidate_.x2-candidate_.x1)*24/length_;
    angle_:=mod(round(atan2((candidate_.y1+candidate_.y2)/2-y_,
      (candidate_.x1+candidate_.x2)/2-x_)*180/acos(-1)/5.625)*5.625+360,360);
    begin
      select sector_id into sector_ from table(doom_bsp_locate(x_,y_)) where rownum=1;
      line_:=candidate_.linedef_id;special_:=candidate_.special;exit;
    exception when no_data_found then null;end;
  end loop;
  if line_ is null then raise_application_error(-20000,'no generic USE fixture geometry');end if;

  select number_value into old_enabled_ from doom_config where config_key='UNIFIED_WORKER_ENABLED';
  select number_value into old_parity_ from doom_config where config_key='UNIFIED_WORKER_PARITY_INTERVAL';
  select number_value into old_split_use_ from doom_config
    where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';
  update doom_config set number_value=1 where config_key='UNIFIED_WORKER_PARITY_INTERVAL';commit;
  doom_api.new_game(3,retained_,payload_);doom_api.new_game(3,oracle_,payload_);
  for session_ in (select retained_ token from dual union all select oracle_ from dual) loop
    update players set x=x_,y=y_,angle=angle_,z=(select floor_height from sector_state
      where session_token=session_.token and sector_id=sector_)
      where session_token=session_.token and player_id=(select current_player_id from game_sessions
        where session_token=session_.token);
  end loop;
  commit;

  update doom_config set number_value=1 where config_key in(
    'UNIFIED_WORKER_ENABLED','UNIFIED_WORKER_SPLIT_USE_ENABLED');commit;
  step_(retained_,retained_payload_);
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_SPLIT_USE_ENABLED';commit;
  update doom_config set number_value=0 where config_key='UNIFIED_WORKER_ENABLED';commit;
  step_(oracle_,oracle_payload_);
  retained_world_:=world_(retained_);oracle_world_:=world_(oracle_);
  retained_player_:=player_(retained_);oracle_player_:=player_(oracle_);
  retained_events_:=events_(retained_);oracle_events_:=events_(oracle_);
  select map_status into retained_status_ from game_sessions where session_token=retained_;
  select map_status into oracle_status_ from game_sessions where session_token=oracle_;
  -- Compare what the public endpoint actually returned.  The SQL tic ledger's
  -- frame_sha is a pre-render state-SHA placeholder; render_payload finalizes
  -- step_responses and the response envelope after APPLY_BATCH commits.
  select json_value(utl_compress.lz_uncompress(retained_payload_),'$.frame_sha'),
         json_value(utl_compress.lz_uncompress(oracle_payload_),'$.frame_sha')
    into retained_frame_,oracle_frame_ from dual;
  if dbms_lob.compare(retained_world_,oracle_world_)<>0 or
     dbms_lob.compare(retained_player_,oracle_player_)<>0 or
     dbms_lob.compare(retained_events_,oracle_events_)<>0 or
     retained_frame_<>oracle_frame_ or
     retained_status_<>oracle_status_ then
    dbms_output.put_line('USE_DIFF_SESSIONS retained='||retained_||' oracle='||oracle_);
    dbms_output.put_line('USE_DIFF world='||dbms_lob.compare(retained_world_,oracle_world_)||
      ' player='||dbms_lob.compare(retained_player_,oracle_player_)||
      ' events='||dbms_lob.compare(retained_events_,oracle_events_)||
      ' status='||retained_status_||'/'||oracle_status_||
      ' frame='||retained_frame_||'/'||oracle_frame_);
    dbms_output.put_line('RETAINED_WORLD_TAIL '||dbms_lob.substr(retained_world_,4000,
      greatest(1,dbms_lob.getlength(retained_world_)-3999)));
    dbms_output.put_line('ORACLE_WORLD_TAIL '||dbms_lob.substr(oracle_world_,4000,
      greatest(1,dbms_lob.getlength(oracle_world_)-3999)));
    dbms_output.put_line('RETAINED_PLAYER '||dbms_lob.substr(retained_player_,4000,1));
    dbms_output.put_line('ORACLE_PLAYER '||dbms_lob.substr(oracle_player_,4000,1));
    dbms_output.put_line('RETAINED_EVENTS '||dbms_lob.substr(retained_events_,4000,1));
    dbms_output.put_line('ORACLE_EVENTS '||dbms_lob.substr(oracle_events_,4000,1));
    raise_application_error(-20000,'retained/SQL USE differential mismatch');
  end if;
  dbms_output.put_line('AUTOREST_WORKER_USE_DOOR_BRIDGE_OK special='||special_||' generic_line='||line_||
    ' status='||retained_status_||' bytes='||dbms_lob.getlength(retained_payload_));
  cleanup_;
exception when others then
  declare code_ number:=sqlcode;message_ varchar2(2048):=sqlerrm;begin cleanup_;
    raise_application_error(-20000,'USE acceptance failed ['||code_||'] '||message_);end;
end;
/
exit
