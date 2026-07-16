whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;
  sectors_ clob;actors_ clob;result_ varchar2(4000);delta_ raw(32767);
  actor_count_ pls_integer;row_index_ pls_integer;offset_ pls_integer;length_ pls_integer;
  actual_id_ number;actual_x_ number;actual_y_ number;actual_sector_ number;actual_direction_ number;
  player_x_ number;player_y_ number;request_ varchar2(32);mismatches_ pls_integer:=0;
  rng_before_ number;rng_after_ number;events_ number;cases_ pls_integer:=0;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  doom_api.new_game(3,session_,payload_);
  select save_lineage into lineage_ from game_sessions where session_token=session_;

  -- Every actor enters an immediate movement-only CHASE action. A prior-snapshot
  -- cooldown of one prevents all attack branches even though housekeeping writes
  -- zero before the action loop. Radius and height deliberately vary by actor.
  update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d
      where d.thing_type=m.thing_type),state_tics=0,awake=1,
      attack_cooldown=1,health=greatest(1,m.health),
      monster_health_seen=greatest(1,m.health),death_processed=0,
      radius=8+4*mod(m.mobj_id,4),height=32+16*mod(m.mobj_id,3)
    where m.session_token=session_
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  delete from game_events where session_token=session_;

  select count(*) into actor_count_ from mobjs m where m.session_token=session_
    and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  if actor_count_=0 or actor_count_>255 then
    raise_application_error(-20000,'chase actor fixture count='||actor_count_);
  end if;
  select json_arrayagg(json_array(sector_id,floor_height,ceiling_height returning varchar2)
           order by sector_id returning clob)
    into sectors_ from sector_state where session_token=session_;
  select json_arrayagg(json_array(m.mobj_id,m.x,m.y,m.z,m.radius,m.height,m.health,d.speed
           returning varchar2) order by m.mobj_id returning clob)
    into actors_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;

  result_:=doom_sim_catalog_load;
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  result_:=doom_monster_chase_load(session_,lineage_,1,sectors_,actors_);
  if result_<>'OK|'||actor_count_ then raise_application_error(-20000,result_);end if;

  -- Fences and malformed requests must fail closed with no result records.
  delta_:=doom_monster_chase_prepare(session_,lineage_,2,
    '11111111111111111111111111111111',0,0);
  if rawtohex(delta_)<>'444D434801010000' then
    raise_application_error(-20000,'chase generation fence accepted');
  end if;
  delta_:=doom_monster_chase_prepare(session_,lineage_,1,'bad-request',0,0);
  if rawtohex(delta_)<>'444D434801010000' then
    raise_application_error(-20000,'chase malformed request accepted');
  end if;

  -- Four real map targets exercise every directional sign combination while the
  -- relational oracle and Java kernel start from the identical actor snapshot.
  for target_ in (
    select x,y from (
      select x,y,row_number() over(order by x,y,thing_id) ordinal from doom_map_thing
    ) where ordinal in(1,15,30,45) order by ordinal
  ) loop
    savepoint chase_case;
    player_x_:=target_.x;player_y_:=target_.y;
    update players set x=player_x_,y=player_y_
      where session_token=session_ and player_id=(select current_player_id
        from game_sessions where session_token=session_);
    request_:=lower(rawtohex(sys_guid()));
    delta_:=doom_monster_chase_prepare(session_,lineage_,1,request_,player_x_,player_y_);
    if utl_raw.length(delta_)<>8+actor_count_*58 or
       rawtohex(utl_raw.substr(delta_,1,8))<>'444D43480100'||lpad(to_char(actor_count_,'fm0xxx'),4,'0') then
      raise_application_error(-20000,'chase delta '||doom_monster_chase_last_error);
    end if;
    select rng_cursor into rng_before_ from game_sessions where session_token=session_;
    doom_monsters.advance(session_,950+cases_);
    select rng_cursor into rng_after_ from game_sessions where session_token=session_;
    if rng_after_<>rng_before_ then raise_application_error(-20000,'chase consumed RNG');end if;
    select count(*) into events_ from game_events
      where session_token=session_ and tic=950+cases_;
    if events_<>0 then raise_application_error(-20000,'chase emitted events='||events_);end if;

    row_index_:=0;
    for row_ in (
      select m.mobj_id,m.x,m.y,m.sector_id,m.move_direction
        from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
        where m.session_token=session_ order by m.mobj_id
    ) loop
      offset_:=9+row_index_*58;
      actual_id_:=utl_raw.cast_to_binary_integer(
        utl_raw.substr(delta_,offset_,4),utl_raw.big_endian);
      length_:=to_number(rawtohex(utl_raw.substr(delta_,offset_+4,1)),'xx');
      actual_x_:=utl_raw.cast_to_number(utl_raw.substr(delta_,offset_+5,length_));
      length_:=to_number(rawtohex(utl_raw.substr(delta_,offset_+27,1)),'xx');
      actual_y_:=utl_raw.cast_to_number(utl_raw.substr(delta_,offset_+28,length_));
      actual_sector_:=utl_raw.cast_to_binary_integer(
        utl_raw.substr(delta_,offset_+50,4),utl_raw.big_endian);
      actual_direction_:=utl_raw.cast_to_binary_integer(
        utl_raw.substr(delta_,offset_+54,4),utl_raw.big_endian);
      if actual_id_<>row_.mobj_id or actual_x_<>row_.x or actual_y_<>row_.y or
         actual_sector_<>row_.sector_id or actual_direction_<>row_.move_direction then
        mismatches_:=mismatches_+1;
        dbms_output.put_line('CHASE_MISMATCH case='||cases_||' actor='||row_.mobj_id||
          ' java='||actual_x_||','||actual_y_||','||actual_sector_||','||actual_direction_||
          ' sql='||row_.x||','||row_.y||','||row_.sector_id||','||row_.move_direction);
      end if;
      row_index_:=row_index_+1;
    end loop;
    if row_index_<>actor_count_ then raise_application_error(-20000,'chase row count');end if;
    rollback to chase_case; cases_:=cases_+1;
  end loop;
  if cases_<>4 or mismatches_<>0 then
    raise_application_error(-20000,'chase parity cases='||cases_||' mismatches='||mismatches_);
  end if;
  dbms_output.put_line('MONSTER_CHASE_PARITY_OK cases='||cases_||
    ' actors_per_case='||actor_count_||' comparisons='||cases_*actor_count_);
  rollback;
end;
/
