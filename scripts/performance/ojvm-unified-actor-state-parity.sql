whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  chase_session_ varchar2(32);death_session_ varchar2(32);lineage_ varchar2(64);payload_ blob;
  map_clob_ clob;map_blob_ blob;map_sha_ varchar2(64);before_ clob;after_ clob;targets_ clob;
  result_ varchar2(4000);delta_ raw(32767);request_ varchar2(32);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;next_event_ number;
  actors_ pls_integer;chase_actors_ pls_integer;drops_ pls_integer;events_ pls_integer;idx_ pls_integer;
  child_ pls_integer;off_ pls_integer;len_ pls_integer;kill_ number;mobj_rows_ number;
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;

  function int_(p raw,o pls_integer) return binary_integer is
  begin return utl_raw.cast_to_binary_integer(utl_raw.substr(p,o,4),utl_raw.big_endian);end;
  function uint16_(p raw,o pls_integer) return pls_integer is
  begin return to_number(rawtohex(utl_raw.substr(p,o,2)),'xxxx');end;
  procedure eq(a number,e number,m varchar2) is
  begin if (a is null and e is not null) or (a is not null and e is null) or a<>e then
    raise_application_error(-20000,m||' actual='||a||' expected='||e);end if;end;
  procedure frontiers(s varchar2) is
  begin
    select current_tic,last_command_seq,rng_cursor into tic_,seq_,rng_
      from game_sessions where session_token=s;
    select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=s;
    select coalesce(max(event_ordinal)+1,0) into next_event_ from game_events
      where session_token=s and tic=tic_;
  end;
  procedure unchanged(s varchar2,expected_rows number,expected_kill number) is
    t number;q number;r number;nm number;ne number;rows_ number;k number;
  begin
    select current_tic,last_command_seq,rng_cursor into t,q,r from game_sessions where session_token=s;
    select coalesce(max(mobj_id),0)+1,count(*) into nm,rows_ from mobjs where session_token=s;
    select coalesce(max(event_ordinal)+1,0) into ne from game_events
      where session_token=s and tic=t;
    select p.kill_count into k from players p join game_sessions g on g.session_token=p.session_token
      and g.current_player_id=p.player_id where g.session_token=s;
    eq(t,tic_,'prepare tic mutation');eq(q,seq_,'prepare seq mutation');
    eq(r,rng_,'prepare RNG mutation');eq(nm,next_mobj_,'prepare mobj frontier mutation');
    eq(ne,next_event_,'prepare event frontier mutation');eq(rows_,expected_rows,'prepare mobj rows mutation');
    eq(k,expected_kill,'prepare player mutation');
  end;
  function actor_image(s varchar2) return clob is value_ clob;
  begin
    select json_arrayagg(json_array(m.mobj_id,m.state_id,m.state_tics,m.x,m.y,m.z,m.health,
      m.flags,m.target_mobj_id,m.sector_id,m.move_direction,m.awake,m.attack_cooldown,
      m.monster_health_seen,m.death_processed null on null returning varchar2)
      order by m.mobj_id returning clob) into value_
      from mobjs m where m.session_token=s;
    return value_;
  end;
begin
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,
      sprite_prefix,sprite_frame,rotations null on null returning varchar2)
      order by state_id returning clob) into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);
  dbms_lob.converttoblob(map_blob_,map_clob_,dbms_lob.lobmaxsize,dest_,src_,
    nls_charset_id('AL32UTF8'),context_,warning_);
  if warning_<>0 then raise_application_error(-20000,'unified state map UTF-8');end if;
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));

  -- One movement-only CHASE operation, from retained typed state to a compact
  -- delta, is compared field-for-field with the untouched relational oracle.
  doom_api.new_game(3,chase_session_,payload_);
  select save_lineage into lineage_ from game_sessions where session_token=chase_session_;
  update players set (x,y)=(select x,y from (select x,y from doom_map_thing order by x,y,thing_id)
      where rownum=1) where session_token=chase_session_;
  update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d
      where d.thing_type=m.thing_type),state_tics=0,awake=1,attack_cooldown=1,
      health=greatest(1,m.health),monster_health_seen=greatest(1,m.health),death_processed=0
    where m.session_token=chase_session_ and exists(
      select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  delete from game_events where session_token=chase_session_;
  select count(*) into actors_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=chase_session_;
  chase_actors_:=actors_;
  select count(*) into mobj_rows_ from mobjs where session_token=chase_session_;
  select p.kill_count into kill_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id
    where g.session_token=chase_session_;
  frontiers(chase_session_);
  result_:=doom_unified_actor_load(chase_session_,lineage_,1,rpad('0',64,'0'));
  if substr(result_,1,4)<>'ERR|' or instr(result_,'state map fence')=0 then
    raise_application_error(-20000,'unified state-map fence '||result_);end if;
  result_:=doom_unified_actor_load(chase_session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'unified chase load '||result_);end if;
  delta_:=doom_unified_actor_prepare(chase_session_,lineage_,2,
    '11111111111111111111111111111111','CHASE',tic_,seq_,rng_,next_mobj_,next_event_);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then raise_application_error(-20000,'generation fence');end if;
  delta_:=doom_unified_actor_prepare(chase_session_,lineage_,1,
    '11111111111111111111111111111111','CHASE',tic_+1,seq_,rng_,next_mobj_,next_event_);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then raise_application_error(-20000,'frontier fence');end if;
  request_:='22222222222222222222222222222222';before_:=actor_image(chase_session_);
  delta_:=doom_unified_actor_prepare(chase_session_,lineage_,1,request_,'CHASE',
    tic_,seq_,rng_,next_mobj_,next_event_);after_:=actor_image(chase_session_);
  if dbms_lob.compare(before_,after_)<>0 then raise_application_error(-20000,'CHASE prepare mutated rows');end if;
  unchanged(chase_session_,mobj_rows_,kill_);
  if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000200' or
     utl_raw.length(delta_)<>12+8+actors_*58 or int_(delta_,9)<>8+actors_*58 or
     rawtohex(utl_raw.substr(delta_,13,6))<>'444D43480100' then
    raise_application_error(-20000,'unified CHASE compact delta '||doom_unified_actor_last_error);end if;
  doom_monsters.advance(chase_session_,tic_);
  idx_:=0;
  for r in (select m.mobj_id,m.x,m.y,m.sector_id,m.move_direction from mobjs m
    join doom_monster_def d on d.thing_type=m.thing_type where m.session_token=chase_session_
    order by m.mobj_id) loop
    child_:=21+idx_*58;eq(int_(delta_,child_),r.mobj_id,'chase id');
    len_:=to_number(rawtohex(utl_raw.substr(delta_,child_+4,1)),'xx');
    eq(utl_raw.cast_to_number(utl_raw.substr(delta_,child_+5,len_)),r.x,'chase x');
    len_:=to_number(rawtohex(utl_raw.substr(delta_,child_+27,1)),'xx');
    eq(utl_raw.cast_to_number(utl_raw.substr(delta_,child_+28,len_)),r.y,'chase y');
    eq(int_(delta_,child_+50),r.sector_id,'chase sector');
    eq(int_(delta_,child_+54),r.move_direction,'chase direction');idx_:=idx_+1;
  end loop;
  eq(idx_,actors_,'chase rows');
  result_:=doom_unified_actor_discard(chase_session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,'unified chase discard '||result_);end if;
  select json_arrayagg(json_array(x,y,(select sector_id from table(doom_bsp_locate(x,y))
      where rownum=1) returning varchar2) order by ordinal returning clob) into targets_
    from (select x,y,row_number() over(order by x,y,thing_id) ordinal from doom_map_thing)
    where ordinal in(1,15,30,45);
  result_:=doom_unified_actor_benchmark(chase_session_,lineage_,1,'CHASE',tic_,seq_,rng_,
    next_mobj_,next_event_,targets_,300);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'unified chase benchmark '||result_);end if;
  dbms_output.put_line('unified_chase_prepare_discard_ns='||result_);

  -- Fresh death/drop is prepared by the same retained owner and accepted only
  -- after SQL persistence. Every actor mutation is compared; spawn/event counts
  -- and compact exact length fence the variable portions of the delta.
  doom_api.new_game(3,death_session_,payload_);
  select save_lineage into lineage_ from game_sessions where session_token=death_session_;
  delete from game_events where session_token=death_session_;
  update mobjs m set health=0,monster_health_seen=77,attack_cooldown=2,awake=1,
      death_processed=0,flags=7,target_mobj_id=(select current_player_id from game_sessions
      where session_token=death_session_),move_direction=3,sector_id=(select sector_id
      from table(doom_bsp_locate(m.x,m.y)) where rownum=1)
    where m.session_token=death_session_ and exists(
      select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  select count(*),count(d.drop_thing_type) into actors_,drops_ from mobjs m
    join doom_monster_def d on d.thing_type=m.thing_type where m.session_token=death_session_;
  events_:=actors_+drops_;select count(*) into mobj_rows_ from mobjs where session_token=death_session_;
  select p.kill_count into kill_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id
    where g.session_token=death_session_;
  frontiers(death_session_);result_:=doom_unified_actor_load(death_session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'unified death load '||result_);end if;
  request_:='33333333333333333333333333333333';before_:=actor_image(death_session_);
  delta_:=doom_unified_actor_prepare(death_session_,lineage_,1,request_,'DEATH',
    tic_,seq_,rng_,next_mobj_,next_event_);after_:=actor_image(death_session_);
  if dbms_lob.compare(before_,after_)<>0 then raise_application_error(-20000,'DEATH prepare mutated rows');end if;
  unchanged(death_session_,mobj_rows_,kill_);
  if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000100' or
     rawtohex(utl_raw.substr(delta_,13,6))<>'444446540100' or
     int_(delta_,9)<>24+actors_*40+drops_*92+events_*20 or
     utl_raw.length(delta_)<>12+24+actors_*40+drops_*92+events_*20 then
    raise_application_error(-20000,'unified DEATH compact delta '||doom_unified_actor_last_error);end if;
  eq(uint16_(delta_,19),actors_,'death actors');eq(uint16_(delta_,21),drops_,'death drops');
  eq(uint16_(delta_,23),events_,'death events');
  doom_monsters.advance(death_session_,tic_);idx_:=0;off_:=37;
  for r in (with si as (select state_id,row_number() over(order by state_id)-1 n from doom_state_def)
    select m.mobj_id,m.monster_health_seen,m.attack_cooldown,si.n,m.state_tics,m.death_processed,
      m.awake,m.flags,m.target_mobj_id,m.move_direction from mobjs m join doom_monster_def d
      on d.thing_type=m.thing_type join si on si.state_id=m.state_id
      where m.session_token=death_session_ and m.death_processed=1 order by m.mobj_id) loop
    eq(int_(delta_,off_+idx_*40),r.mobj_id,'death id');
    eq(int_(delta_,off_+idx_*40+4),r.monster_health_seen,'death seen');
    eq(int_(delta_,off_+idx_*40+8),r.attack_cooldown,'death cooldown');
    eq(int_(delta_,off_+idx_*40+12),r.n,'death state');
    eq(int_(delta_,off_+idx_*40+16),r.state_tics,'death tics');
    eq(int_(delta_,off_+idx_*40+20),r.death_processed,'death processed');
    eq(int_(delta_,off_+idx_*40+24),r.awake,'death awake');
    eq(int_(delta_,off_+idx_*40+28),r.flags,'death flags');
    eq(int_(delta_,off_+idx_*40+32),coalesce(r.target_mobj_id,-1),'death target');
    eq(int_(delta_,off_+idx_*40+36),r.move_direction,'death direction');idx_:=idx_+1;
  end loop;
  eq(idx_,actors_,'death rows');
  select count(*) into idx_ from mobjs where session_token=death_session_ and mobj_id>=next_mobj_;
  eq(idx_,drops_,'drop rows');select count(*) into idx_ from game_events
    where session_token=death_session_ and tic=tic_ and event_ordinal>=next_event_;
  eq(idx_,events_,'event rows');
  result_:=doom_unified_actor_accept(death_session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,'unified death accept '||result_);end if;
  delta_:=doom_unified_actor_prepare(death_session_,lineage_,1,
    '44444444444444444444444444444444','DEATH',tic_,seq_,rng_,next_mobj_+drops_,next_event_+events_);
  if rawtohex(utl_raw.substr(delta_,6,1))<>'01' then raise_application_error(-20000,'death replay accepted');end if;
  dbms_output.put_line('UNIFIED_ACTOR_STATE_PARITY_OK chase='||chase_actors_||' death='||actors_
    ||' drops='||drops_||' events='||events_);
  dbms_output.put_line('unified_actor_state_fences=PASS');
  rollback;
end;
/
