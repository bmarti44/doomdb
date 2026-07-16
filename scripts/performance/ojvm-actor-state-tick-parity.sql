whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;snapshot_ clob;sector_snapshot_ clob;
  result_ varchar2(4000);request_ varchar2(32);delta_ raw(32767);
  player_x_ number;player_y_ number;player_target_ number;rng_before_ number;rng_after_ number;
  actor_count_ number;dirty_ number;events_ number;row_index_ number:=0;offset_ number;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  doom_api.new_game(3,session_,payload_);
  select g.save_lineage,p.x,p.y,max(m.mobj_id),g.rng_cursor
    into lineage_,player_x_,player_y_,player_target_,rng_before_
    from game_sessions g join players p on p.session_token=g.session_token
      and p.player_id=g.current_player_id
    left join mobjs m on m.session_token=g.session_token and m.mobj_id=g.current_player_id
    where g.session_token=session_ group by g.save_lineage,p.x,p.y,g.rng_cursor;
  player_target_:=coalesce(player_target_,-1);
  delete from game_events where session_token=session_;
  update mobjs m set awake=1,monster_health_seen=m.health,
    attack_cooldown=0,state_tics=3,sector_id=coalesce(m.sector_id,
      (select sector_id from table(doom_bsp_locate(m.x,m.y)) where rownum=1))
    where m.session_token=session_
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  select count(*) into actor_count_ from mobjs m where m.session_token=session_
    and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  with states as (
    select state_id,tics,row_number() over(order by state_id)-1 state_index from doom_state_def
  )
  select json_arrayagg(json_array(m.mobj_id,m.health,m.monster_health_seen,
           m.attack_cooldown,m.awake,m.state_tics,m.sector_id,m.x,m.y,cur.state_index,
           m.target_mobj_id,see.state_index,see.tics,d.pain_chance,
           pain.state_index,pain.tics null on null returning varchar2)
           order by m.mobj_id returning clob)
    into snapshot_
    from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    join states cur on cur.state_id=m.state_id join states see on see.state_id=d.see_state_id
    join states pain on pain.state_id=d.pain_state_id
    where m.session_token=session_;
  result_:=doom_sim_catalog_load;
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  select json_arrayagg(json_array(sector_id,floor_height,ceiling_height returning varchar2)
           order by sector_id returning clob)
    into sector_snapshot_ from sector_state where session_token=session_;
  result_:=doom_retained_los_load(sector_snapshot_);
  if result_<>'OK|182' then raise_application_error(-20000,result_);end if;
  result_:=doom_actor_wake_load(session_,lineage_,1,rng_before_,snapshot_);
  if result_<>'OK|'||actor_count_ then raise_application_error(-20000,result_);end if;
  request_:='55555555555555555555555555555555';
  delta_:=doom_actor_wake_prepare(session_,lineage_,1,request_,
    player_x_,player_y_,0,player_target_,0);
  if rawtohex(utl_raw.substr(delta_,1,6))<>'4441574B0100' then
    raise_application_error(-20000,'state tick prepare '||doom_actor_wake_last_error);
  end if;
  dirty_:=to_number(rawtohex(utl_raw.substr(delta_,7,2)),'xxxx');
  events_:=to_number(rawtohex(utl_raw.substr(delta_,9,2)),'xxxx');
  if dirty_<>actor_count_ or events_<>0 then raise_application_error(-20000,'state tick counts');end if;
  doom_monsters.advance(session_,903);
  select rng_cursor into rng_after_ from game_sessions where session_token=session_;
  if rng_after_<>rng_before_ then raise_application_error(-20000,'state tick RNG');end if;
  for row_ in (
    with states as (
      select state_id,row_number() over(order by state_id)-1 state_index from doom_state_def
    )
    select m.mobj_id,m.monster_health_seen,m.attack_cooldown,m.awake,s.state_index,
      m.state_tics,coalesce(m.target_mobj_id,-1) target_mobj_id
      from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      join states s on s.state_id=m.state_id
      where m.session_token=session_ order by m.mobj_id
  ) loop
    offset_:=13+row_index_*32;
    if utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_,4),utl_raw.big_endian)<>
         row_.mobj_id or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+4,4),utl_raw.big_endian)<>2 or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+8,4),utl_raw.big_endian)<>
         row_.monster_health_seen or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+12,4),utl_raw.big_endian)<>
         row_.attack_cooldown or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+16,4),utl_raw.big_endian)<>
         row_.awake or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+20,4),utl_raw.big_endian)<>
         row_.state_index or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+24,4),utl_raw.big_endian)<>
         row_.state_tics or
       utl_raw.cast_to_binary_integer(utl_raw.substr(delta_,offset_+28,4),utl_raw.big_endian)<>
         row_.target_mobj_id then raise_application_error(-20000,'state tick mismatch');end if;
    row_index_:=row_index_+1;
  end loop;
  result_:=doom_actor_wake_accept(session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  dbms_output.put_line('actor_active_state_tick_parity='||actor_count_||'/'||actor_count_);
  dbms_output.put_line('actor_active_state_tick_events=0/0');
  dbms_output.put_line('actor_active_state_tick_rng=PASS');
  rollback;
end;
/
