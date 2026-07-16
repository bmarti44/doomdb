whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;snapshot_ clob;
  result_ varchar2(4000);request_ varchar2(32);delta_ raw(32767);
  player_x_ number;player_y_ number;player_sector_ number;hidden_sector_ number;
  actor_count_ pls_integer;dirty_ pls_integer;
  actual_id_ number;actual_seen_ number;actual_cooldown_ number;offset_ pls_integer;
  unchanged_ pls_integer;events_ pls_integer;failures_ pls_integer:=0;rng_before_ number;rng_after_ number;
  actor_before_ clob;actor_after_ clob;
  fixture_found_ boolean:=false;
  samples_ sys.odcinumberlist:=sys.odcinumberlist();started_ timestamp with time zone;
  elapsed_ interval day to second;ms_ number;p50_ number;p95_ number;max_ number;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  doom_api.new_game(3,session_,payload_);
  select g.save_lineage,p.x,p.y
    into lineage_,player_x_,player_y_
    from game_sessions g join players p on p.session_token=g.session_token
      and p.player_id=g.current_player_id
    where g.session_token=session_;
  select sector_id into player_sector_
    from table(doom_bsp_locate(player_x_,player_y_)) where rownum=1;
  -- Pick a real map coordinate whose sector has a REJECT-hidden but
  -- sound-connected source. This exercises both the quiet and audible gates.
  for point_ in (select x,y from doom_map_thing order by thing_id) loop
    select sector_id into player_sector_
      from table(doom_bsp_locate(point_.x,point_.y)) where rownum=1;
    select min(r.source_sector_id) into hidden_sector_ from doom_sector_reject r
      join doom_sector_sound_reach s on s.source_sector_id=player_sector_
        and s.target_sector_id=r.source_sector_id
      where r.target_sector_id=player_sector_ and r.rejected=1;
    if hidden_sector_ is not null then
      player_x_:=point_.x;player_y_:=point_.y;fixture_found_:=true;exit;
    end if;
  end loop;
  if not fixture_found_ then
    raise_application_error(-20000,'no REJECT-hidden actor fixture sector');
  end if;
  update players set x=player_x_,y=player_y_ where session_token=session_
    and player_id=(select current_player_id from game_sessions where session_token=session_);

  -- Rollback-only controlled fixture: every monster is alive, asleep, unheard,
  -- and REJECT-hidden from the player. The native loop can therefore perform
  -- only its common health/cooldown housekeeping and then continue.
  delete from game_events where session_token=session_;
  update mobjs m set sector_id=hidden_sector_,awake=0,target_mobj_id=null,
    monster_health_seen=null,attack_cooldown=1+mod(m.mobj_id,5)
    where m.session_token=session_
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  select json_arrayagg(json_array(m.mobj_id,m.thing_type,m.state_id,m.state_tics,
           m.x,m.y,m.z,m.momentum_x,m.momentum_y,m.momentum_z,m.angle,m.radius,m.height,
           m.health,m.flags,m.target_mobj_id,m.tracer_mobj_id,m.reaction_time,m.spawn_thing_id,
           m.sector_id,m.move_direction,m.awake,m.death_processed
           null on null returning varchar2) order by m.mobj_id returning clob)
    into actor_before_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;
  select rng_cursor into rng_before_ from game_sessions where session_token=session_;
  select count(*) into actor_count_ from mobjs m
    where m.session_token=session_
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  if actor_count_=0 or actor_count_>255 then
    raise_application_error(-20000,'actor fixture count='||actor_count_);
  end if;
  select json_arrayagg(
           json_array(m.mobj_id,m.health,m.monster_health_seen,
             m.attack_cooldown,m.awake,m.state_tics,m.sector_id
             null on null returning varchar2)
           order by m.mobj_id returning clob)
    into snapshot_
    from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;
  result_:=doom_sim_catalog_load;
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  result_:=doom_common_actor_load(session_,lineage_,1,snapshot_);
  if result_<>'OK|'||actor_count_ then raise_application_error(-20000,result_);end if;

  -- Wrong fences and malformed request IDs reject without publishing pending state.
  delta_:=doom_common_actor_prepare(session_,lineage_,2,
    '11111111111111111111111111111111',to_binary_double(player_x_),
    to_binary_double(player_y_),0);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then
    raise_application_error(-20000,'generation fence accepted');
  end if;
  delta_:=doom_common_actor_prepare(session_,lineage_,1,'bad-request',
    to_binary_double(player_x_),to_binary_double(player_y_),0);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then
    raise_application_error(-20000,'malformed request accepted');
  end if;

  -- DISCARD must leave the retained committed frontier reusable.
  request_:='22222222222222222222222222222222';
  delta_:=doom_common_actor_prepare(session_,lineage_,1,request_,
    to_binary_double(player_x_),to_binary_double(player_y_),1);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then
    raise_application_error(-20000,'sound wake proof accepted');
  end if;
  delta_:=doom_common_actor_prepare(session_,lineage_,1,request_,
    to_binary_double(player_x_),to_binary_double(player_y_),0);
  if utl_raw.length(delta_)<>3068 or rawtohex(utl_raw.substr(delta_,1,8))<>'444143540100'||
       lpad(to_char(actor_count_,'fm0x'),2,'0')||'00' then
    raise_application_error(-20000,'actor delta header '||rawtohex(utl_raw.substr(delta_,1,8)));
  end if;
  result_:=doom_common_actor_load(session_,lineage_,1,snapshot_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'pending load accepted');end if;
  result_:=doom_common_actor_accept(session_,lineage_,1,
    '99999999999999999999999999999999');
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'wrong accept accepted');end if;
  result_:=doom_common_actor_discard(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  result_:=doom_common_actor_discard(session_,lineage_,1,request_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'double discard accepted');end if;

  request_:='33333333333333333333333333333333';
  delta_:=doom_common_actor_prepare(session_,lineage_,1,request_,
    to_binary_double(player_x_),to_binary_double(player_y_),0);
  dirty_:=to_number(rawtohex(utl_raw.substr(delta_,7,1)),'xx');
  if dirty_<>actor_count_ then
    raise_application_error(-20000,'dirty actor count='||dirty_||' expected='||actor_count_);
  end if;
  select count(*) into unchanged_ from mobjs m
    where m.session_token=session_ and m.monster_health_seen is null
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  if unchanged_<>actor_count_ then
    raise_application_error(-20000,'prepare leaked into relational state');
  end if;

  -- Execute the untouched SQL oracle against the identical controlled snapshot.
  doom_monsters.advance(session_,900);
  select count(*) into events_ from game_events
    where session_token=session_ and tic=900;
  if events_<>0 then raise_application_error(-20000,'quiet fixture emitted events='||events_);end if;
  select json_arrayagg(json_array(m.mobj_id,m.thing_type,m.state_id,m.state_tics,
           m.x,m.y,m.z,m.momentum_x,m.momentum_y,m.momentum_z,m.angle,m.radius,m.height,
           m.health,m.flags,m.target_mobj_id,m.tracer_mobj_id,m.reaction_time,m.spawn_thing_id,
           m.sector_id,m.move_direction,m.awake,m.death_processed
           null on null returning varchar2) order by m.mobj_id returning clob)
    into actor_after_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;
  select rng_cursor into rng_after_ from game_sessions where session_token=session_;
  if dbms_lob.compare(actor_before_,actor_after_)<>0 or rng_before_<>rng_after_ then
    raise_application_error(-20000,'quiet oracle changed non-housekeeping state');
  end if;
  for row_ in (
    select m.mobj_id,m.health,m.monster_health_seen,m.attack_cooldown,m.awake,m.state_tics
      from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=session_ order by m.mobj_id
  ) loop
    offset_:=9+failures_*12;
    actual_id_:=utl_raw.cast_to_binary_integer(
      utl_raw.substr(delta_,offset_,4),utl_raw.big_endian);
    actual_seen_:=utl_raw.cast_to_binary_integer(
      utl_raw.substr(delta_,offset_+4,4),utl_raw.big_endian);
    actual_cooldown_:=utl_raw.cast_to_binary_integer(
      utl_raw.substr(delta_,offset_+8,4),utl_raw.big_endian);
    if actual_id_<>row_.mobj_id or actual_seen_<>row_.monster_health_seen or
       actual_cooldown_<>row_.attack_cooldown or row_.awake<>0 then
      raise_application_error(-20000,'actor parity index='||failures_||
        ' packed='||actual_id_||','||actual_seen_||','||actual_cooldown_||
        ' sql='||row_.mobj_id||','||row_.monster_health_seen||','||row_.attack_cooldown);
    end if;
    failures_:=failures_+1;
  end loop;
  if failures_<>actor_count_ then raise_application_error(-20000,'actor row count');end if;
  result_:=doom_common_actor_accept(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  result_:=doom_common_actor_accept(session_,lineage_,1,request_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'double accept accepted');end if;

  -- Warm retained scan/prepare/accept cost after cooldowns have reached zero.
  for warmup_ in 1..5 loop
    request_:=lower(rawtohex(sys_guid()));
    delta_:=doom_common_actor_prepare(session_,lineage_,1,request_,
      to_binary_double(player_x_),to_binary_double(player_y_),0);
    result_:=doom_common_actor_accept(session_,lineage_,1,request_);
    if result_<>'OK' then raise_application_error(-20000,result_);end if;
  end loop;
  for sample_ in 1..300 loop
    request_:=lower(rawtohex(sys_guid()));started_:=systimestamp;
    delta_:=doom_common_actor_prepare(session_,lineage_,1,request_,
      to_binary_double(player_x_),to_binary_double(player_y_),0);
    if rawtohex(utl_raw.substr(delta_,1,6))<>'444143540100' then
      raise_application_error(-20000,'actor benchmark rejected '||doom_common_actor_last_error);
    end if;
    result_:=doom_common_actor_accept(session_,lineage_,1,request_);
    if result_<>'OK' then raise_application_error(-20000,result_);end if;
    elapsed_:=systimestamp-started_;
    ms_:=extract(day from elapsed_)*86400000+extract(hour from elapsed_)*3600000+
      extract(minute from elapsed_)*60000+extract(second from elapsed_)*1000;
    samples_.extend;samples_(samples_.count):=ms_;
  end loop;
  select percentile_cont(.5) within group(order by column_value),
         percentile_cont(.95) within group(order by column_value),max(column_value)
    into p50_,p95_,max_ from table(samples_);
  dbms_output.put_line('common_actor_quiet_parity='||actor_count_||'/'||actor_count_);
  dbms_output.put_line('common_actor_transaction_fences=PASS');
  dbms_output.put_line('common_actor_quiet_prepare_accept_ms='||
    round(p50_,3)||'|'||round(p95_,3)||'|'||round(max_,3));
  rollback;
end;
/
