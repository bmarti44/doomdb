whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;snapshot_ clob;bad_snapshot_ clob;
  request_ varchar2(32);result_ varchar2(4000);delta_ raw(32767);
  actor_count_ pls_integer;drop_count_ pls_integer;event_count_ pls_integer;
  kill_before_ number;kill_after_ number;next_mobj_ number;mobj_before_ number;mobj_after_ number;
  rng_before_ number;rng_after_ number;actor_offset_ pls_integer;drop_offset_ pls_integer;
  event_offset_ pls_integer;index_ pls_integer:=0;drop_index_ pls_integer:=0;event_index_ pls_integer:=0;
  next_event_ number:=5;

  function int_(p_raw raw,p_offset pls_integer) return binary_integer is
  begin
    return utl_raw.cast_to_binary_integer(utl_raw.substr(p_raw,p_offset,4),utl_raw.big_endian);
  end;
  function uint16_(p_raw raw,p_offset pls_integer) return pls_integer is
  begin
    return to_number(rawtohex(utl_raw.substr(p_raw,p_offset,2)),'xxxx');
  end;
  procedure equal_(p_actual number,p_expected number,p_message varchar2) is
  begin
    if (p_actual is null and p_expected is not null)
       or (p_actual is not null and p_expected is null)
       or p_actual<>p_expected then
      raise_application_error(-20000,p_message||' actual='||p_actual||' expected='||p_expected);
    end if;
  end;
begin
  doom_api.new_game(3,session_,payload_);
  select g.save_lineage,p.kill_count,g.rng_cursor
    into lineage_,kill_before_,rng_before_
    from game_sessions g join players p on p.session_token=g.session_token
      and p.player_id=g.current_player_id where g.session_token=session_;
  delete from game_events where session_token=session_;
  insert into game_events(session_token,tic,event_ordinal,event_type)
    values(session_,900,4,'DEATH_FIXTURE_BASE');

  -- Every placed monster becomes a fresh death. This covers no-drop definitions
  -- and the two resolved drop definitions in one frozen mobj-id iteration.
  update mobjs m set health=0,monster_health_seen=77,
    attack_cooldown=1+mod(m.mobj_id,5),awake=1,death_processed=0,
    flags=7,target_mobj_id=(select current_player_id from game_sessions where session_token=session_),
    move_direction=3,sector_id=(
      select sector_id from table(doom_bsp_locate(m.x,m.y)) where rownum=1)
    where m.session_token=session_
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  select count(*),count(d.drop_thing_type)
    into actor_count_,drop_count_
    from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;
  select count(*) into mobj_before_ from mobjs where session_token=session_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
  event_count_:=actor_count_+drop_count_;
  if actor_count_=0 or actor_count_>128 or drop_count_=0 then
    raise_application_error(-20000,'fresh death fixture actors='||actor_count_||' drops='||drop_count_);
  end if;

  -- A declared drop with missing resolved spawn data must fail at load.
  with state_index as (
    select state_id,row_number() over(order by state_id)-1 state_index from doom_state_def
  )
  select json_arrayagg(json_array(m.mobj_id,m.health,m.monster_health_seen,
           m.attack_cooldown,m.awake,m.state_tics,m.death_processed,m.flags,
           m.target_mobj_id,m.move_direction,death_state.state_index,death_def.tics,
           m.x,m.y,m.z,m.sector_id,d.drop_thing_type,null,null,null,null
           null on null returning varchar2) returning clob)
    into bad_snapshot_
    from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    join state_index death_state on death_state.state_id=d.death_state_id
    join doom_state_def death_def on death_def.state_id=d.death_state_id
    where m.session_token=session_ and d.drop_thing_type is not null and rownum=1;
  result_:=doom_fresh_death_load(session_,lineage_,1,kill_before_,bad_snapshot_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'unresolved drop load accepted');end if;

  with state_index as (
    select state_id,row_number() over(order by state_id)-1 state_index from doom_state_def
  )
  select json_arrayagg(json_array(m.mobj_id,m.health,m.monster_health_seen,
           m.attack_cooldown,m.awake,m.state_tics,m.death_processed,m.flags,
           m.target_mobj_id,m.move_direction,death_state.state_index,death_def.tics,
           m.x,m.y,m.z,m.sector_id,d.drop_thing_type,drop_state.state_index,
           drop_def.tics,
           case when d.drop_thing_type is null then null else coalesce(drop_type.radius,8) end,
           case when d.drop_thing_type is null then null else coalesce(drop_type.height,8) end
           null on null returning varchar2) order by m.mobj_id returning clob)
    into snapshot_
    from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    join state_index death_state on death_state.state_id=d.death_state_id
    join doom_state_def death_def on death_def.state_id=d.death_state_id
    left join doom_thing_type_def drop_type on drop_type.thing_type=d.drop_thing_type
    left join state_index drop_state on drop_state.state_id=drop_type.spawn_state_id
    left join doom_state_def drop_def on drop_def.state_id=drop_type.spawn_state_id
    where m.session_token=session_;
  result_:=doom_fresh_death_load(session_,lineage_,1,kill_before_,snapshot_);
  if result_<>'OK|'||actor_count_||'|'||kill_before_ then raise_application_error(-20000,result_);end if;

  -- Generation, discard and pending-load fences leave committed retained state reusable.
  delta_:=doom_fresh_death_prepare(session_,lineage_,2,
    '11111111111111111111111111111111',next_event_,next_mobj_);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then raise_application_error(-20000,'death generation fence');end if;
  request_:='22222222222222222222222222222222';
  delta_:=doom_fresh_death_prepare(session_,lineage_,1,request_,next_event_,next_mobj_);
  result_:=doom_fresh_death_load(session_,lineage_,1,kill_before_,snapshot_);
  if substr(result_,1,4)<>'ERR|' then raise_application_error(-20000,'pending death load accepted');end if;
  result_:=doom_fresh_death_discard(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;

  request_:='33333333333333333333333333333333';
  delta_:=doom_fresh_death_prepare(session_,lineage_,1,request_,next_event_,next_mobj_);
  if rawtohex(utl_raw.substr(delta_,1,6))<>'444446540100' or utl_raw.length(delta_)>32767 then
    raise_application_error(-20000,'fresh death delta header');
  end if;
  equal_(uint16_(delta_,7),actor_count_,'actor count');
  equal_(uint16_(delta_,9),drop_count_,'drop count');
  equal_(uint16_(delta_,11),event_count_,'event count');
  equal_(int_(delta_,13),actor_count_,'kill increment');
  equal_(int_(delta_,17),next_mobj_+drop_count_,'next mobj frontier');
  equal_(int_(delta_,21),next_event_+event_count_,'next event frontier');
  select count(*) into mobj_after_ from mobjs where session_token=session_;
  equal_(mobj_after_,mobj_before_,'prepare leaked relational state');

  -- Execute the untouched SQL oracle against the identical prior-tic snapshot.
  doom_monsters.advance(session_,900);
  select p.kill_count,g.rng_cursor into kill_after_,rng_after_
    from game_sessions g join players p on p.session_token=g.session_token
      and p.player_id=g.current_player_id where g.session_token=session_;
  equal_(kill_after_,kill_before_+actor_count_,'kill count');
  equal_(rng_after_,rng_before_,'death RNG');
  select count(*) into mobj_after_ from mobjs where session_token=session_;
  equal_(mobj_after_,mobj_before_+drop_count_,'drop row count');

  actor_offset_:=25;
  drop_offset_:=actor_offset_+actor_count_*40;
  event_offset_:=drop_offset_+drop_count_*92;
  for row_ in (
    with state_index as (
      select state_id,row_number() over(order by state_id)-1 state_index from doom_state_def
    )
    select m.mobj_id,m.monster_health_seen,m.attack_cooldown,s.state_index,m.state_tics,
      m.death_processed,m.awake,m.flags,m.target_mobj_id,m.move_direction
      from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      join state_index s on s.state_id=m.state_id
      where m.session_token=session_ and m.death_processed=1 order by m.mobj_id
  ) loop
    equal_(int_(delta_,actor_offset_+index_*40),row_.mobj_id,'death actor id');
    equal_(int_(delta_,actor_offset_+index_*40+4),row_.monster_health_seen,'death seen');
    equal_(int_(delta_,actor_offset_+index_*40+8),row_.attack_cooldown,'death cooldown');
    equal_(int_(delta_,actor_offset_+index_*40+12),row_.state_index,'death state');
    equal_(int_(delta_,actor_offset_+index_*40+16),row_.state_tics,'death tics');
    equal_(int_(delta_,actor_offset_+index_*40+20),row_.death_processed,'death processed');
    equal_(int_(delta_,actor_offset_+index_*40+24),row_.awake,'death awake');
    equal_(int_(delta_,actor_offset_+index_*40+28),row_.flags,'death flags');
    equal_(int_(delta_,actor_offset_+index_*40+32),coalesce(row_.target_mobj_id,-1),'death target');
    equal_(int_(delta_,actor_offset_+index_*40+36),row_.move_direction,'death direction');
    index_:=index_+1;
  end loop;
  equal_(index_,actor_count_,'death actor rows');

  for row_ in (
    with state_index as (
      select state_id,row_number() over(order by state_id)-1 state_index from doom_state_def
    )
    select m.mobj_id,m.thing_type,s.state_index,m.state_tics,m.x,m.y,m.z,
      m.momentum_x,m.momentum_y,m.momentum_z,m.angle,m.radius,m.height,m.health,m.flags,
      m.target_mobj_id,m.tracer_mobj_id,m.reaction_time,m.spawn_thing_id,m.owner_mobj_id,
      m.projectile_kind,m.exploded,m.sector_id
      from mobjs m join state_index s on s.state_id=m.state_id
      where m.session_token=session_ and m.mobj_id>=next_mobj_ order by m.mobj_id
  ) loop
    for field_ in 0..22 loop
      equal_(int_(delta_,drop_offset_+drop_index_*92+field_*4),
        case field_ when 0 then row_.mobj_id when 1 then row_.thing_type when 2 then row_.state_index
          when 3 then row_.state_tics when 4 then row_.x when 5 then row_.y when 6 then row_.z
          when 7 then row_.momentum_x when 8 then row_.momentum_y when 9 then row_.momentum_z
          when 10 then row_.angle when 11 then row_.radius when 12 then row_.height
          when 13 then row_.health when 14 then row_.flags when 15 then coalesce(row_.target_mobj_id,-1)
          when 16 then coalesce(row_.tracer_mobj_id,-1) when 17 then row_.reaction_time
          when 18 then coalesce(row_.spawn_thing_id,-1) when 19 then row_.owner_mobj_id
          when 20 then case when row_.projectile_kind is null then -1 else -2 end
          when 21 then row_.exploded when 22 then row_.sector_id end,'drop field '||field_);
    end loop;
    drop_index_:=drop_index_+1;
  end loop;
  equal_(drop_index_,drop_count_,'drop rows');

  for row_ in (
    select event_ordinal,event_type,actor_mobj_id,target_mobj_id,number_value,text_value
      from game_events where session_token=session_ and tic=900 and event_ordinal>=next_event_
      order by event_ordinal
  ) loop
    equal_(int_(delta_,event_offset_+event_index_*20),row_.event_ordinal,'event ordinal');
    equal_(int_(delta_,event_offset_+event_index_*20+4),
      case row_.event_type when 'MONSTER_DEATH' then 1 when 'MONSTER_DROP' then 2 else -1 end,
      'event type');
    equal_(int_(delta_,event_offset_+event_index_*20+8),row_.actor_mobj_id,'event actor');
    equal_(int_(delta_,event_offset_+event_index_*20+12),coalesce(row_.target_mobj_id,-1),'event target');
    equal_(int_(delta_,event_offset_+event_index_*20+16),coalesce(row_.number_value,-1),'event number');
    if row_.text_value is not null then raise_application_error(-20000,'death event text');end if;
    event_index_:=event_index_+1;
  end loop;
  equal_(event_index_,event_count_,'death event rows');

  result_:=doom_fresh_death_accept(session_,lineage_,1,request_);
  if result_<>'OK|'||kill_after_ then raise_application_error(-20000,result_);end if;
  delta_:=doom_fresh_death_prepare(session_,lineage_,1,
    '44444444444444444444444444444444',next_event_+event_count_,next_mobj_+drop_count_);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then
    raise_application_error(-20000,'processed death accepted twice');
  end if;
  dbms_output.put_line('fresh_death_actor_parity='||actor_count_||'/'||actor_count_);
  dbms_output.put_line('fresh_death_drop_parity='||drop_count_||'/'||drop_count_);
  dbms_output.put_line('fresh_death_event_parity='||event_count_||'/'||event_count_);
  dbms_output.put_line('fresh_death_transaction_fences=PASS');
  rollback;
end;
/
