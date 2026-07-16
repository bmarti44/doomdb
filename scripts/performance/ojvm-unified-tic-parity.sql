whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);delta_ raw(32767);request_ varchar2(32);
  command_ raw(24);move_ clob;angle_ number;expected_x_ number;expected_y_ number;expected_z_ number;
  tic_ number;seq_ number;rng_ number;next_mobj_ number;next_event_ number;actors_ pls_integer;
  spawns_ pls_integer;events_ pls_integer;draws_ pls_integer;off_ pls_integer;idx_ pls_integer;
  pain_id_ number;death_id_ number;corpse_id_ number;melee_id_ number;hitscan_id_ number;
  projectile_id_ number;wake_id_ number;px_ number;py_ number;pz_ number;pain_ number;
  len_ pls_integer;event_idx_ pls_integer;spawn_idx_ pls_integer;actual_ number;
  before_ clob;after_ clob;restart_ blob;dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;
  function int_(p raw,o pls_integer) return binary_integer is
  begin return utl_raw.cast_to_binary_integer(utl_raw.substr(p,o,4),utl_raw.big_endian);end;
  function u16(p raw,o pls_integer) return pls_integer is
  begin return to_number(rawtohex(utl_raw.substr(p,o,2)),'xxxx');end;
  function num_(p raw,o pls_integer) return number is n pls_integer;
  begin n:=to_number(rawtohex(utl_raw.substr(p,o,1)),'xx');return utl_raw.cast_to_number(utl_raw.substr(p,o+1,n));end;
  procedure eq(a number,e number,m varchar2) is
  begin if (a is null and e is not null) or (a is not null and e is null) or a<>e then
    raise_application_error(-20000,m||' actual='||a||' expected='||e);end if;end;
begin
  doom_api.new_game(3,session_,payload_);
  select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
    from game_sessions where session_token=session_;
  select p.x,p.y,p.z into px_,py_,pz_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id where g.session_token=session_;
  delete from game_events where session_token=session_;
  update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d where d.thing_type=m.thing_type),
    state_tics=0,awake=1,attack_cooldown=1,health=greatest(10,health),
    monster_health_seen=greatest(10,health),death_processed=0
    where session_token=session_ and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
  select min(m.mobj_id) into pain_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and d.pain_chance>0;
  select min(m.mobj_id) into death_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and d.drop_thing_type is not null and m.mobj_id<>pain_id_;
  select min(m.mobj_id) into corpse_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and m.mobj_id not in(pain_id_,death_id_);
  select min(m.mobj_id) into melee_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and d.attack_kind='MELEE' and m.mobj_id not in(pain_id_,death_id_,corpse_id_);
  select min(m.mobj_id) into hitscan_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and d.attack_kind='HITSCAN' and m.mobj_id not in(pain_id_,death_id_,corpse_id_);
  select min(m.mobj_id) into projectile_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and d.attack_kind='PROJECTILE' and m.mobj_id not in(pain_id_,death_id_,corpse_id_);
  select min(m.mobj_id) into wake_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and m.mobj_id not in(pain_id_,death_id_,corpse_id_,melee_id_,hitscan_id_,projectile_id_);
  update mobjs set health=health-1,monster_health_seen=health where session_token=session_ and mobj_id=pain_id_;
  select d.pain_chance into pain_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_ and m.mobj_id=pain_id_;
  select rng_index into rng_ from doom_rng_value where rng_value<pain_ order by rng_index fetch first 1 row only;
  update game_sessions set rng_cursor=rng_ where session_token=session_;
  update mobjs set health=0,death_processed=0 where session_token=session_ and mobj_id=death_id_;
  update mobjs m set health=0,death_processed=1,state_id=(select d.death_state_id from doom_monster_def d
    where d.thing_type=m.thing_type),state_tics=2 where session_token=session_ and mobj_id=corpse_id_;
  update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_)) where rownum=1),
    state_id=(select d.melee_state_id from doom_monster_def d where d.thing_type=m.thing_type),state_tics=0
    where session_token=session_ and mobj_id=melee_id_;
  update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_)) where rownum=1),
    state_id=(select d.missile_state_id from doom_monster_def d where d.thing_type=m.thing_type),state_tics=0
    where session_token=session_ and mobj_id in(hitscan_id_,projectile_id_);
  update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_)) where rownum=1),
    awake=0 where session_token=session_ and mobj_id=wake_id_;
  select count(*) into actors_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
    where m.session_token=session_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;next_event_:=0;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);dbms_lob.converttoblob(map_blob_,map_clob_,
    dbms_lob.lobmaxsize,dest_,src_,nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'TIC load '||result_);end if;
  select json_arrayagg(json_array(mobj_id,state_id,state_tics,x,y,health,flags,target_mobj_id,
    sector_id,move_direction,awake,attack_cooldown,monster_health_seen,death_processed null on null
    returning varchar2) order by mobj_id returning clob) into before_ from mobjs where session_token=session_;
  request_:=lower(rawtohex(sys_guid()));delta_:=doom_unified_actor_prepare(session_,lineage_,1,request_,'TIC',
    tic_,seq_,rng_,next_mobj_,next_event_);
  select json_arrayagg(json_array(mobj_id,state_id,state_tics,x,y,health,flags,target_mobj_id,
    sector_id,move_direction,awake,attack_cooldown,monster_health_seen,death_processed null on null
    returning varchar2) order by mobj_id returning clob) into after_ from mobjs where session_token=session_;
  if dbms_lob.compare(before_,after_)<>0 then raise_application_error(-20000,'TIC prepare mutated rows');end if;
  if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000400' or
    rawtohex(utl_raw.substr(delta_,13,6))<>'445449430100' or int_(delta_,9)<>utl_raw.length(delta_)-12 then
    raise_application_error(-20000,'TIC delta '||doom_unified_actor_last_error);end if;
  eq(u16(delta_,19),actors_,'TIC source actor count');
  spawns_:=u16(delta_,21);events_:=u16(delta_,23);draws_:=u16(delta_,25);
  doom_monsters.advance(session_,tic_+1);
  select rng_cursor into off_ from game_sessions where session_token=session_;eq(int_(delta_,29),off_,'TIC RNG');
  eq(int_(delta_,49),next_mobj_+spawns_,'TIC next mobj frontier');
  eq(int_(delta_,53),next_event_+events_,'TIC next event frontier');
  eq(int_(delta_,61),tic_+1,'TIC next tic');eq(int_(delta_,69),seq_+1,'TIC next seq');
  idx_:=0;off_:=73;
  for r in (with si as(select state_id,row_number() over(order by state_id)-1 n from doom_state_def)
    select m.mobj_id,m.monster_health_seen,m.attack_cooldown,si.n,m.state_tics,m.death_processed,
      m.awake,m.flags,m.target_mobj_id,m.move_direction,m.x,m.y,m.sector_id from mobjs m
      join doom_monster_def d on d.thing_type=m.thing_type join si on si.state_id=m.state_id
      where m.session_token=session_ order by m.mobj_id) loop
    eq(int_(delta_,off_+idx_*90),r.mobj_id,'TIC actor id');
    eq(int_(delta_,off_+idx_*90+4),r.monster_health_seen,'TIC seen');
    eq(int_(delta_,off_+idx_*90+8),r.attack_cooldown,'TIC cooldown');
    eq(int_(delta_,off_+idx_*90+12),r.n,'TIC state');eq(int_(delta_,off_+idx_*90+16),r.state_tics,'TIC tics');
    eq(int_(delta_,off_+idx_*90+20),r.death_processed,'TIC death');eq(int_(delta_,off_+idx_*90+24),r.awake,'TIC awake');
    eq(int_(delta_,off_+idx_*90+28),r.flags,'TIC flags');eq(int_(delta_,off_+idx_*90+32),coalesce(r.target_mobj_id,-1),'TIC target');
    eq(int_(delta_,off_+idx_*90+36),r.move_direction,'TIC direction');eq(num_(delta_,off_+idx_*90+40),r.x,'TIC x');
    eq(num_(delta_,off_+idx_*90+63),r.y,'TIC y');eq(int_(delta_,off_+idx_*90+86),r.sector_id,'TIC sector');idx_:=idx_+1;
  end loop;
  eq(idx_,actors_,'TIC actors');off_:=73+actors_*90;spawn_idx_:=0;
  for r in (with si as(select state_id,row_number() over(order by state_id)-1 n from doom_state_def)
    select m.mobj_id,m.thing_type,si.n,m.state_tics,m.x,m.y,m.z,m.momentum_x,m.momentum_y,m.momentum_z,
      m.radius,m.height,m.health,m.flags,m.target_mobj_id,m.tracer_mobj_id,m.reaction_time,m.spawn_thing_id,
      m.owner_mobj_id,m.exploded,m.sector_id,m.projectile_kind from mobjs m join si on si.state_id=m.state_id
      where m.session_token=session_ and m.mobj_id>=next_mobj_ order by m.mobj_id) loop
    eq(int_(delta_,off_),r.mobj_id,'spawn id');eq(int_(delta_,off_+4),r.thing_type,'spawn thing');
    eq(int_(delta_,off_+8),r.n,'spawn state');eq(int_(delta_,off_+12),r.state_tics,'spawn tics');
    eq(num_(delta_,off_+16),r.x,'spawn x');eq(num_(delta_,off_+39),r.y,'spawn y');eq(num_(delta_,off_+62),r.z,'spawn z');
    eq(num_(delta_,off_+85),r.momentum_x,'spawn mx');eq(num_(delta_,off_+108),r.momentum_y,'spawn my');
    eq(num_(delta_,off_+131),r.momentum_z,'spawn mz');eq(num_(delta_,off_+154),r.radius,'spawn radius');
    eq(num_(delta_,off_+177),r.height,'spawn height');eq(int_(delta_,off_+200),r.health,'spawn health');
    eq(int_(delta_,off_+204),r.flags,'spawn flags');eq(int_(delta_,off_+208),coalesce(r.target_mobj_id,-1),'spawn target');
    eq(int_(delta_,off_+212),coalesce(r.tracer_mobj_id,-1),'spawn tracer');eq(int_(delta_,off_+216),r.reaction_time,'spawn reaction');
    eq(int_(delta_,off_+220),coalesce(r.spawn_thing_id,-1),'spawn source');eq(int_(delta_,off_+224),coalesce(r.owner_mobj_id,-1),'spawn owner');
    eq(int_(delta_,off_+228),r.exploded,'spawn exploded');eq(int_(delta_,off_+232),r.sector_id,'spawn sector');
    len_:=u16(delta_,off_+236);if r.projectile_kind is null then eq(len_,65535,'spawn null kind');off_:=off_+238;
    else eq(len_,lengthb(r.projectile_kind),'spawn kind length');off_:=off_+238+len_;end if;spawn_idx_:=spawn_idx_+1;
  end loop;
  eq(spawn_idx_,spawns_,'TIC spawns');event_idx_:=0;
  for e in (select event_ordinal,event_type,actor_mobj_id,target_mobj_id,number_value,text_value
    from game_events where session_token=session_ and tic=tic_+1 order by event_ordinal) loop
    eq(int_(delta_,off_),e.event_ordinal,'TIC event ordinal');
    eq(int_(delta_,off_+4),case e.event_type when 'MONSTER_HIT' then 1 when 'MONSTER_MISS' then 2
      when 'MONSTER_PAIN' then 3 when 'MONSTER_DEATH' then 4 when 'MONSTER_DROP' then 5
      when 'MONSTER_WAKE' then 6 when 'MONSTER_PROJECTILE' then 7 end,'TIC event type');
    eq(int_(delta_,off_+8),e.actor_mobj_id,'TIC event actor');eq(int_(delta_,off_+12),coalesce(e.target_mobj_id,-1),'TIC event target');
    if e.number_value is null then eq(to_number(rawtohex(utl_raw.substr(delta_,off_+16,1)),'xx'),0,'TIC null number');
    else eq(to_number(rawtohex(utl_raw.substr(delta_,off_+16,1)),'xx'),1,'TIC number presence');
      eq(num_(delta_,off_+17),e.number_value,'TIC event number');end if;len_:=u16(delta_,off_+40);
    if e.text_value is null then eq(len_,65535,'TIC event null text');off_:=off_+42;
    else eq(len_,lengthb(e.text_value),'TIC event text length');off_:=off_+42+len_;end if;event_idx_:=event_idx_+1;
  end loop;
  eq(event_idx_,events_,'TIC events');eq(off_,utl_raw.length(delta_)+1,'TIC exact length');
  result_:=doom_unified_actor_accept(session_,lineage_,1,request_);if result_<>'OK' then raise_application_error(-20000,result_);end if;
  result_:=doom_unified_world_sql_parity(session_,lineage_,1);if result_ not like 'OK|%' then raise_application_error(-20000,'TIC world '||result_);end if;
  dbms_lob.createtemporary(restart_,true,dbms_lob.call);
  result_:=doom_unified_world_checkpoint(session_,lineage_,1,restart_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'TIC restart checkpoint '||result_);end if;
  result_:=doom_unified_world_restore(session_,lineage_,1,restart_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'TIC restart restore '||result_);end if;
  result_:=doom_unified_world_sql_parity(session_,lineage_,1);
  if result_ not like 'OK|%' then raise_application_error(-20000,'TIC restart SQL parity '||result_);end if;
  dbms_output.put_line('UNIFIED_TIC_PARITY_OK actors='||actors_||' spawns='||spawns_||' events='||events_||' draws='||draws_||' bytes='||utl_raw.length(delta_));
  result_:=doom_unified_actor_benchmark(session_,lineage_,1,'TIC',tic_+1,seq_+1,
    int_(delta_,29),int_(delta_,49),0,cast(null as clob),300);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'TIC benchmark '||result_);end if;
  dbms_output.put_line('unified_tic_prepare_discard_ns='||result_);
  -- A second command-driven TIC advances the already-mixed pain/death/wake/attack owner.
  rng_:=int_(delta_,29);next_mobj_:=int_(delta_,49);
  select p.x,p.y,p.z,p.angle into px_,py_,pz_,angle_ from players p join game_sessions g
    on g.session_token=p.session_token and g.current_player_id=p.player_id where g.session_token=session_;
  move_:=doom_player_move_payload(session_,cos(angle_*acos(-1)/180)*8,sin(angle_*acos(-1)/180)*8);
  expected_x_:=json_value(move_,'$.dest_x' returning number);expected_y_:=json_value(move_,'$.dest_y' returning number);
  expected_z_:=json_value(move_,'$.dest_z' returning number);
  command_:=hextoraw('444d53430201000000000000000000020001000000000000');request_:=lower(rawtohex(sys_guid()));
  delta_:=doom_unified_command_tic_prepare(session_,lineage_,1,request_,tic_+1,seq_+1,rng_,next_mobj_,0,command_);
  if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000500' then
    raise_application_error(-20000,'mixed command TIC '||doom_unified_actor_last_error);end if;
  update players set x=expected_x_,y=expected_y_,z=expected_z_ where session_token=session_
    and player_id=(select current_player_id from game_sessions where session_token=session_);
  doom_monsters.advance(session_,tic_+2);
  update game_sessions set current_tic=tic_+2,last_command_seq=seq_+2 where session_token=session_;
  result_:=doom_unified_actor_accept(session_,lineage_,1,request_);if result_<>'OK' then raise_application_error(-20000,result_);end if;
  result_:=doom_unified_owner_sql_parity(session_,lineage_,1);
  if result_ not like 'OK|%' then raise_application_error(-20000,'mixed command owner '||result_);end if;
  result_:=doom_unified_world_checkpoint(session_,lineage_,1,restart_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'mixed command checkpoint '||result_);end if;
  result_:=doom_unified_world_restore(session_,lineage_,1,restart_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'mixed command restore '||result_);end if;
  result_:=doom_unified_owner_sql_parity(session_,lineage_,1);
  if result_ not like 'OK|%' then raise_application_error(-20000,'mixed command restart '||result_);end if;
  dbms_output.put_line('unified_command_tic_mixed_combat=PASS frontier='||(tic_+2)||'|'||(seq_+2));
  doom_api.new_game(3,session_,payload_);select save_lineage into lineage_ from game_sessions where session_token=session_;
  result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'accepted TIC load '||result_);end if;
  result_:=doom_unified_tic_accept_benchmark(session_,lineage_,1,300);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'accepted TIC benchmark '||result_);end if;
  if substr(result_,-8)<>'|320|320' then raise_application_error(-20000,'accepted TIC frontier '||result_);end if;
  dbms_output.put_line('unified_tic_accepted_ns='||result_);
  rollback;
end;
/
