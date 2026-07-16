whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  a_ varchar2(32);b_ varchar2(32);sql_payload_ blob;ignored_ blob;
  snapshot_a_ blob;snapshot_b_ blob;delta_ blob;payload_ blob;jdbc_payload_ blob;
  result_ varchar2(4000);packed_sha_ varchar2(4000);jdbc_sha_ varchar2(4000);
  a1_ varchar2(4000);a2_ varchar2(4000);b1_ varchar2(4000);
  frames_ sys.odcivarchar2list:=sys.odcivarchar2list();
  update_samples_ sys.odcinumberlist:=sys.odcinumberlist();
  render_samples_ sys.odcinumberlist:=sys.odcinumberlist();
  update_p50_ number;update_p95_ number;update_max_ number;
  render_p50_ number;render_p95_ number;render_max_ number;distinct_ number;
  sector_id_ number;existing_id_ number;removed_id_ number;new_id_ number;
  world_sha_ varchar2(4000);world_jdbc_sha_ varchar2(4000);
  frame_delta_bytes_ number;world_delta_bytes_ number;
  zero_sha_ constant varchar2(64):=rpad('0',64,'0');
  procedure set_angle(p_session varchar2,p_index pls_integer) is begin
    update players set angle=mod(p_index,64)*5.625 where session_token=p_session
      and player_id=(select current_player_id from game_sessions where session_token=p_session);
  end;
  procedure fill_delta(p_session varchar2) is begin doom_renderer_delta_fill(p_session,delta_);end;
  procedure append_raw(p_value raw) is begin
    dbms_lob.writeappend(delta_,utl_raw.length(p_value),p_value);end;
  procedure append_int(p_value number) is begin append_raw(
    utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian));end;
  procedure append_double(p_value number) is begin append_raw(
    utl_raw.cast_from_binary_double(cast(p_value as binary_double),utl_raw.big_endian));end;
  procedure append_string(p_value varchar2) is l_raw raw(32767):=
    utl_i18n.string_to_raw(p_value,'AL32UTF8');
  begin append_int(utl_raw.length(l_raw));append_raw(l_raw);end;
  procedure build_world_delta is
  begin
    fill_delta(a_);dbms_lob.trim(delta_,dbms_lob.getlength(delta_)-4);
    for s in (select sector_id,floor_height,ceiling_height,light_level from sector_state
      where session_token=a_ and sector_id=sector_id_) loop
      append_int(1);append_int(s.sector_id);append_double(s.floor_height);
      append_double(s.ceiling_height);append_int(s.light_level);
    end loop;
    for m in (select mobj_id,state_id,x,y,z,angle from mobjs where session_token=a_
      and mobj_id in(existing_id_,new_id_) order by mobj_id) loop
      append_int(2);append_int(m.mobj_id);append_string(m.state_id);append_double(m.x);
      append_double(m.y);append_double(m.z);append_double(m.angle);
    end loop;
    append_int(5);append_int(removed_id_);append_int(4);
  end;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  doom_api.new_game(3,a_,sql_payload_);doom_api.new_game(3,b_,ignored_);
  dbms_lob.createtemporary(snapshot_a_,true);dbms_lob.createtemporary(snapshot_b_,true);
  dbms_lob.createtemporary(delta_,true);dbms_lob.createtemporary(payload_,true);
  dbms_lob.createtemporary(jdbc_payload_,true);
  doom_renderer_snapshot_fill(a_,snapshot_a_);doom_renderer_snapshot_fill(b_,snapshot_b_);

  result_:=doom_retained_render_load(a_,1,snapshot_a_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  fill_delta(a_);packed_sha_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
  result_:=doom_bsp_compare_current_payload(sql_payload_);
  if result_<>'0|0|0|320|-1|200|-1' then
    raise_application_error(-20000,'retained SQL anchor '||result_);end if;

  -- Reload A/B/A scenes and prove both owner fencing and deterministic recovery.
  set_angle(a_,1);fill_delta(a_);a1_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
  result_:=doom_retained_render_load(b_,2,snapshot_b_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  set_angle(b_,2);fill_delta(b_);b1_:=doom_retained_render_update(b_,2,delta_,zero_sha_,payload_);
  fill_delta(a_);result_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
  if result_ not like 'ERROR:%' or dbms_lob.getlength(payload_)<>0 then
    raise_application_error(-20000,'retained A/B fence');end if;
  result_:=doom_retained_render_load(a_,1,snapshot_a_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  fill_delta(a_);a2_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
  if a1_<>a2_ or a1_=b1_ then raise_application_error(-20000,'retained A-B-A');end if;

  -- Compact retained update and the legacy JDBC reader must agree at all angles.
  for angle_index_ in 0..63 loop
    set_angle(a_,angle_index_);fill_delta(a_);
    packed_sha_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
    jdbc_sha_:=doom_bsp_render_session(a_,zero_sha_,jdbc_payload_);
    if not regexp_like(packed_sha_,'^[0-9a-f]{64}$') or packed_sha_<>jdbc_sha_ then
      raise_application_error(-20000,'retained angle='||angle_index_||' packed='||
        packed_sha_||' jdbc='||jdbc_sha_||' error='||doom_retained_render_last_error);end if;
    frames_.extend;frames_(frames_.count):=packed_sha_;
  end loop;
  select count(distinct column_value) into distinct_ from table(frames_);
  if distinct_<>64 then raise_application_error(-20000,'retained distinct='||distinct_);end if;

  for warmup_ in 1..500 loop
    set_angle(a_,warmup_*17);fill_delta(a_);
    packed_sha_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
  end loop;
  for sample_ in 1..300 loop
    set_angle(a_,sample_*17);fill_delta(a_);
    packed_sha_:=doom_retained_render_update(a_,1,delta_,zero_sha_,payload_);
    if not regexp_like(packed_sha_,'^[0-9a-f]{64}$') then
      raise_application_error(-20000,'retained sample='||sample_);end if;
    update_samples_.extend;update_samples_(update_samples_.count):=
      doom_retained_render_last_update_ns/1e6;
    render_samples_.extend;render_samples_(render_samples_.count):=
      (doom_bsp_last_render_ns+doom_bsp_last_codec_ns+doom_bsp_last_blob_ns)/1e6;
  end loop;
  frame_delta_bytes_:=dbms_lob.getlength(delta_);
  select percentile_cont(.5) within group(order by column_value),
    percentile_cont(.95) within group(order by column_value),max(column_value)
    into update_p50_,update_p95_,update_max_ from table(update_samples_);
  select percentile_cont(.5) within group(order by column_value),
    percentile_cont(.95) within group(order by column_value),max(column_value)
    into render_p50_,render_p95_,render_max_ from table(render_samples_);

  -- Rollback-only world mutation proves sector patch, existing/new mobj upsert,
  -- and mobj removal against a fresh JDBC reconstruction of the same state.
  select sector_id into sector_id_ from table(doom_bsp_locate(
    (select p.x from players p join game_sessions s on s.session_token=p.session_token
      and s.current_player_id=p.player_id where s.session_token=a_),
    (select p.y from players p join game_sessions s on s.session_token=p.session_token
      and s.current_player_id=p.player_id where s.session_token=a_))) where rownum=1;
  select min(mobj_id),min(mobj_id) keep(dense_rank first order by mobj_id),max(mobj_id)+100
    into existing_id_,removed_id_,new_id_ from mobjs where session_token=a_;
  select min(mobj_id) into removed_id_ from mobjs where session_token=a_
    and mobj_id>existing_id_;
  update sector_state set light_level=case when light_level<255 then light_level+1
    else light_level-1 end where session_token=a_ and sector_id=sector_id_;
  update mobjs set x=x+1 where session_token=a_ and mobj_id=existing_id_;
  insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
    momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,target_mobj_id,
    tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,projectile_kind,exploded,
    sector_id,move_direction,awake,attack_cooldown,monster_health_seen,death_processed)
  select session_token,new_id_,thing_type,state_id,state_tics,x,y,z,momentum_x,momentum_y,
    momentum_z,angle,radius,height,health,flags,null,null,reaction_time,spawn_thing_id,
    owner_mobj_id,projectile_kind,exploded,sector_id,move_direction,awake,attack_cooldown,
    monster_health_seen,death_processed from mobjs
    where session_token=a_ and mobj_id=removed_id_;
  delete from mobjs where session_token=a_ and mobj_id=removed_id_;
  result_:=doom_retained_render_load(a_,3,snapshot_a_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  build_world_delta;
  world_delta_bytes_:=dbms_lob.getlength(delta_);
  world_sha_:=doom_retained_render_update(a_,3,delta_,zero_sha_,payload_);
  world_jdbc_sha_:=doom_bsp_render_session(a_,zero_sha_,jdbc_payload_);
  if not regexp_like(world_sha_,'^[0-9a-f]{64}$') or world_sha_<>world_jdbc_sha_ then
    raise_application_error(-20000,'retained world delta packed='||world_sha_||
      ' jdbc='||world_jdbc_sha_||' error='||doom_retained_render_last_error);end if;
  dbms_output.put_line('RETAINED_RENDER_64_ANGLE_OK distinct_frames='||distinct_||
    ' scene_bytes='||dbms_lob.getlength(snapshot_a_)||
    ' delta_bytes='||frame_delta_bytes_);
  dbms_output.put_line('RETAINED_RENDER_ISOLATION_OK a='||substr(a1_,1,12)||
    ' b='||substr(b1_,1,12)||' a2='||substr(a2_,1,12));
  dbms_output.put_line('RETAINED_RENDER_WORLD_DELTA_OK sector='||sector_id_||
    ' update='||existing_id_||' add='||new_id_||' remove='||removed_id_||
    ' bytes='||world_delta_bytes_||' sha='||substr(world_sha_,1,12));
  dbms_output.put_line('retained_update_ms='||round(update_p50_,3)||'|'||
    round(update_p95_,3)||'|'||round(update_max_,3));
  dbms_output.put_line('retained_render_codec_blob_ms='||round(render_p50_,3)||'|'||
    round(render_p95_,3)||'|'||round(render_max_,3));
  rollback;
end;
/
