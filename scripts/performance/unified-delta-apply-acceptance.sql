whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  apply_session_ varchar2(32);oracle_session_ varchar2(32);
  lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);delta_ raw(32767);bad_ raw(32767);
  request_ varchar2(32);tic_ number;seq_ number;rng_ number;next_mobj_ number;
  committed_tic_ number;committed_seq_ number;version_ number;count_ number;sha_ varchar2(64);
  before_ clob;after_ clob;dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;

  procedure cleanup_sessions is
  begin
    if apply_session_ is not null then delete from game_sessions where session_token=apply_session_;end if;
    if oracle_session_ is not null then delete from game_sessions where session_token=oracle_session_;end if;
    commit;
  end;

  procedure setup_mixed(p_session varchar2) is
    pain_id_ number;death_id_ number;corpse_id_ number;melee_id_ number;
    hitscan_id_ number;projectile_id_ number;wake_id_ number;
    px_ number;py_ number;pz_ number;pain_ number;rng_index_ number;
  begin
    select p.x,p.y,p.z into px_,py_,pz_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id
      where g.session_token=p_session;
    delete from game_events where session_token=p_session;
    update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d where d.thing_type=m.thing_type),
      state_tics=0,awake=1,attack_cooldown=1,health=greatest(10,health),
      monster_health_seen=greatest(10,health),death_processed=0
      where session_token=p_session and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    select min(m.mobj_id) into pain_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and d.pain_chance>0;
    select min(m.mobj_id) into death_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and d.drop_thing_type is not null and m.mobj_id<>pain_id_;
    select min(m.mobj_id) into corpse_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and m.mobj_id not in(pain_id_,death_id_);
    select min(m.mobj_id) into melee_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and d.attack_kind='MELEE' and m.mobj_id not in(pain_id_,death_id_,corpse_id_);
    select min(m.mobj_id) into hitscan_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and d.attack_kind='HITSCAN' and m.mobj_id not in(pain_id_,death_id_,corpse_id_);
    select min(m.mobj_id) into projectile_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and d.attack_kind='PROJECTILE' and m.mobj_id not in(pain_id_,death_id_,corpse_id_);
    select min(m.mobj_id) into wake_id_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and m.mobj_id not in(pain_id_,death_id_,corpse_id_,melee_id_,hitscan_id_,projectile_id_);
    update mobjs set health=health-1,monster_health_seen=health where session_token=p_session and mobj_id=pain_id_;
    select d.pain_chance into pain_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=p_session and m.mobj_id=pain_id_;
    select rng_index into rng_index_ from doom_rng_value where rng_value<pain_
      order by rng_index fetch first 1 row only;
    update game_sessions set rng_cursor=rng_index_ where session_token=p_session;
    update mobjs set health=0,death_processed=0 where session_token=p_session and mobj_id=death_id_;
    update mobjs m set health=0,death_processed=1,state_id=(select d.death_state_id from doom_monster_def d
      where d.thing_type=m.thing_type),state_tics=2 where session_token=p_session and mobj_id=corpse_id_;
    update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_)) where rownum=1),
      state_id=(select d.melee_state_id from doom_monster_def d where d.thing_type=m.thing_type),state_tics=0
      where session_token=p_session and mobj_id=melee_id_;
    update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_)) where rownum=1),
      state_id=(select d.missile_state_id from doom_monster_def d where d.thing_type=m.thing_type),state_tics=0
      where session_token=p_session and mobj_id in(hitscan_id_,projectile_id_);
    update mobjs m set x=px_,y=py_,sector_id=(select sector_id from table(doom_bsp_locate(px_,py_)) where rownum=1),
      awake=0 where session_token=p_session and mobj_id=wake_id_;
  end;

  function world_doc(p_session varchar2) return clob is l_doc clob;
  begin
    select json_arrayagg(json_array(mobj_id,thing_type,state_id,state_tics,x,y,z,
      momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
      target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
      projectile_kind,exploded,sector_id,move_direction,awake,attack_cooldown,
      monster_health_seen,death_processed null on null returning varchar2)
      order by mobj_id returning clob) into l_doc from mobjs where session_token=p_session;
    return l_doc;
  end;

  procedure assert_equal(a clob,e clob,m varchar2) is
  begin
    if dbms_lob.compare(a,e)<>0 then raise_application_error(-20000,m);end if;
  end;

  procedure assert_parity is
    a_ clob;e_ clob;
  begin
    assert_equal(world_doc(apply_session_),world_doc(oracle_session_),'applied mobj parity');
    select json_array(health,armor,alive,kill_count returning clob) into a_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id where g.session_token=apply_session_;
    select json_array(health,armor,alive,kill_count returning clob) into e_ from players p join game_sessions g
      on g.session_token=p.session_token and g.current_player_id=p.player_id where g.session_token=oracle_session_;
    assert_equal(a_,e_,'applied player parity');
    select json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
      number_value,text_value null on null returning varchar2) order by event_ordinal returning clob)
      into a_ from game_events where session_token=apply_session_ and tic=tic_;
    select json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
      number_value,text_value null on null returning varchar2) order by event_ordinal returning clob)
      into e_ from game_events where session_token=oracle_session_ and tic=tic_;
    assert_equal(a_,e_,'applied event parity');
    select json_array(current_tic,last_command_seq,rng_cursor returning clob) into a_
      from game_sessions where session_token=apply_session_;
    select json_array(current_tic,last_command_seq,rng_cursor returning clob) into e_
      from game_sessions where session_token=oracle_session_;
    assert_equal(a_,e_,'applied frontier parity');
  end;

  function replace_bytes(p_raw raw,p_position pls_integer,p_bytes pls_integer,p_value raw) return raw is
  begin
    return utl_raw.concat(utl_raw.substr(p_raw,1,p_position-1),p_value,
      utl_raw.substr(p_raw,p_position+p_bytes));
  end;

  procedure expect_reject(p_bad raw,p_label varchar2) is
    rejected_ boolean:=false;world_before_ clob;player_before_ clob;session_before_ clob;
    player_after_ clob;session_after_ clob;events_before_ number;events_after_ number;
  begin
    world_before_:=world_doc(apply_session_);
    select json_array(health,armor,alive,kill_count returning clob) into player_before_
      from players p join game_sessions g on g.session_token=p.session_token
      and g.current_player_id=p.player_id where g.session_token=apply_session_;
    select json_array(current_tic,last_command_seq,rng_cursor returning clob) into session_before_
      from game_sessions where session_token=apply_session_;
    select count(*) into events_before_ from game_events where session_token=apply_session_;
    begin
      doom_unified_delta_apply.apply_tic(apply_session_,lineage_,tic_,seq_,p_bad,
        committed_tic_,committed_seq_,version_,count_,sha_);
    exception when others then
      if sqlcode in(-20840,-20841) then rejected_:=true;else raise;end if;
    end;
    if not rejected_ then raise_application_error(-20000,p_label||' was accepted');end if;
    assert_equal(world_doc(apply_session_),world_before_,p_label||' partially mutated mobjs');
    select json_array(health,armor,alive,kill_count returning clob) into player_after_
      from players p join game_sessions g on g.session_token=p.session_token
      and g.current_player_id=p.player_id where g.session_token=apply_session_;
    select json_array(current_tic,last_command_seq,rng_cursor returning clob) into session_after_
      from game_sessions where session_token=apply_session_;
    select count(*) into events_after_ from game_events where session_token=apply_session_;
    assert_equal(player_after_,player_before_,p_label||' partially mutated player');
    assert_equal(session_after_,session_before_,p_label||' partially mutated frontier');
    if events_after_<>events_before_ then raise_application_error(-20000,p_label||' partially mutated events');end if;
  end;
begin
  select count(*) into count_ from user_tab_columns where table_name='DOOM_WORKER_RESULT'
    and column_name in('STATE_SHA','FRAME_SHA','RESPONSE_BYTES','RESPONSE_SHA')
    and nullable='N';
  if count_<>4 then raise_application_error(-20000,'worker result metadata bootstrap');end if;
  -- Separate setup transactions prevent NEW_GAME's bounded expired-session
  -- cleanup in one fixture session from retaining locks during the second.
  doom_api.new_game(3,apply_session_,payload_);commit;
  doom_api.new_game(3,oracle_session_,payload_);commit;
  setup_mixed(apply_session_);setup_mixed(oracle_session_);
  select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
    from game_sessions where session_token=apply_session_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=apply_session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);dbms_lob.converttoblob(map_blob_,map_clob_,
    dbms_lob.lobmaxsize,dest_,src_,nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  result_:=doom_unified_actor_load(apply_session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'load '||result_);end if;

  savepoint configured_world;
  before_:=world_doc(apply_session_);request_:=lower(rawtohex(sys_guid()));
  delta_:=doom_unified_actor_prepare(apply_session_,lineage_,1,request_,'TIC',
    tic_,seq_,rng_,next_mobj_,0);
  assert_equal(world_doc(apply_session_),before_,'prepare mutated SQL rows');
  expect_reject(utl_raw.substr(delta_,1,utl_raw.length(delta_)-1),'truncated delta');
  bad_:=replace_bytes(delta_,27,2,hextoraw('0001'));expect_reject(bad_,'malformed delta');
  bad_:=replace_bytes(delta_,163,4,utl_raw.substr(delta_,73,4));expect_reject(bad_,'duplicate actor delta');

  doom_unified_delta_apply.apply_tic(apply_session_,lineage_,tic_,seq_,delta_,
    committed_tic_,committed_seq_,version_,count_,sha_);
  doom_monsters.advance(oracle_session_,tic_);
  update game_sessions set current_tic=tic_+1,last_command_seq=seq_+1 where session_token=oracle_session_;
  assert_parity;
  expect_reject(delta_,'stale duplicate delta');
  rollback to configured_world;
  result_:=doom_unified_actor_discard(apply_session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,'discard '||result_);end if;
  assert_equal(world_doc(apply_session_),world_doc(oracle_session_),'rollback/discard SQL semantics');

  request_:=lower(rawtohex(sys_guid()));
  delta_:=doom_unified_actor_prepare(apply_session_,lineage_,1,request_,'TIC',
    tic_,seq_,rng_,next_mobj_,0);
  doom_unified_delta_apply.apply_tic(apply_session_,lineage_,tic_,seq_,delta_,
    committed_tic_,committed_seq_,version_,count_,sha_);
  doom_monsters.advance(oracle_session_,tic_);
  update game_sessions set current_tic=tic_+1,last_command_seq=seq_+1 where session_token=oracle_session_;
  result_:=doom_unified_actor_accept(apply_session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,'accept '||result_);end if;
  assert_parity;
  if committed_tic_<>tic_+1 or committed_seq_<>seq_+1 or version_<>1 or count_<>1 or
     not regexp_like(sha_,'^[0-9a-f]{64}$') then raise_application_error(-20000,'result metadata');end if;
  dbms_output.put_line('UNIFIED_DELTA_APPLY_OK tic='||committed_tic_||' seq='||committed_seq_||
    ' bytes='||utl_raw.length(delta_)||' sha='||sha_);
  rollback;
  cleanup_sessions;
exception when others then
  rollback;
  cleanup_sessions;
  raise;
end;
/
