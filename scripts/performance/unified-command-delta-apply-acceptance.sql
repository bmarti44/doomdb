whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  apply_session_ varchar2(32);oracle_session_ varchar2(32);lineage_ varchar2(64);
  payload_ blob;map_clob_ clob;map_blob_ blob;map_sha_ varchar2(64);result_ varchar2(4000);
  command_ raw(24);delta_ raw(32767);bad_ raw(32767);request_ varchar2(32);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;
  committed_tic_ number;committed_seq_ number;version_ number;count_ number;sha_ varchar2(64);
  before_ clob;move_ clob;dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;

  procedure cleanup_sessions is begin
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

  function world_doc(p_session varchar2) return clob is d_ clob;begin
    select json_arrayagg(json_array(mobj_id,thing_type,state_id,state_tics,x,y,z,momentum_x,
      momentum_y,momentum_z,angle,radius,height,health,flags,target_mobj_id,tracer_mobj_id,
      reaction_time,spawn_thing_id,owner_mobj_id,projectile_kind,exploded,sector_id,
      move_direction,awake,attack_cooldown,monster_health_seen,death_processed null on null
      returning varchar2) order by mobj_id returning clob) into d_ from mobjs where session_token=p_session;
    return d_;
  end;
  function player_doc(p_session varchar2) return clob is d_ clob;begin
    select json_array(x,y,z,angle,health,armor,alive,kill_count returning clob) into d_
      from players p join game_sessions g on g.session_token=p.session_token
      and g.current_player_id=p.player_id where g.session_token=p_session;return d_;
  end;
  function event_doc(p_session varchar2) return clob is d_ clob;begin
    select coalesce(json_arrayagg(json_array(event_ordinal,event_type,actor_mobj_id,target_mobj_id,
      number_value,text_value null on null returning varchar2) order by event_ordinal returning clob),
      to_clob('[]')) into d_ from game_events where session_token=p_session and tic=tic_+1;return d_;
  end;
  procedure same(a clob,e clob,m varchar2) is begin
    if dbms_lob.compare(a,e)<>0 then raise_application_error(-20000,m);end if;end;
  function replace_bytes(p raw,o pls_integer,n pls_integer,v raw) return raw is begin
    return utl_raw.concat(utl_raw.substr(p,1,o-1),v,utl_raw.substr(p,o+n));end;

  procedure expect_reject(p_command raw,p_delta raw,p_label varchar2) is
    rejected_ boolean:=false;w_ clob;p_ clob;e_ clob;t_ number;s_ number;r_ number;
  begin
    w_:=world_doc(apply_session_);p_:=player_doc(apply_session_);e_:=event_doc(apply_session_);
    select current_tic,last_command_seq,rng_cursor into t_,s_,r_ from game_sessions where session_token=apply_session_;
    begin doom_unified_delta_apply.apply_command_tic(apply_session_,lineage_,tic_,seq_,
      p_command,p_delta,committed_tic_,committed_seq_,version_,count_,sha_);
    exception when others then if sqlcode in(-20840,-20841) then rejected_:=true;else raise;end if;end;
    if not rejected_ then raise_application_error(-20000,p_label||' accepted');end if;
    same(world_doc(apply_session_),w_,p_label||' mobj atomicity');
    same(player_doc(apply_session_),p_,p_label||' player atomicity');
    same(event_doc(apply_session_),e_,p_label||' event atomicity');
    for q in (select current_tic,last_command_seq,rng_cursor from game_sessions
      where session_token=apply_session_) loop
      if q.current_tic<>t_ or q.last_command_seq<>s_ or q.rng_cursor<>r_ then
        raise_application_error(-20000,p_label||' frontier atomicity');end if;
    end loop;
  end;

  procedure advance_oracle is
    angle_ number;x_ number;y_ number;dx_ number;dy_ number;
  begin
    select p.angle into angle_ from players p join game_sessions g on g.session_token=p.session_token
      and g.current_player_id=p.player_id where g.session_token=oracle_session_;
    angle_:=mod(angle_+5.625+360,360);dx_:=cos(angle_*acos(-1)/180)*16;
    dy_:=sin(angle_*acos(-1)/180)*16;
    move_:=doom_player_move_payload(oracle_session_,dx_,dy_);
    x_:=json_value(move_,'$.dest_x' returning number);y_:=json_value(move_,'$.dest_y' returning number);
    update players set x=x_,y=y_,z=json_value(move_,'$.dest_z' returning number),angle=angle_
      where session_token=oracle_session_ and player_id=(select current_player_id from game_sessions
        where session_token=oracle_session_);
    doom_monsters.advance(oracle_session_,tic_+1);
    update game_sessions set current_tic=tic_+1,last_command_seq=seq_+1 where session_token=oracle_session_;
  end;

  procedure assert_parity is
    a_ clob;e_ clob;
  begin
    same(world_doc(apply_session_),world_doc(oracle_session_),'DCTC mobj parity');
    same(player_doc(apply_session_),player_doc(oracle_session_),'DCTC player parity');
    same(event_doc(apply_session_),event_doc(oracle_session_),'DCTC event parity');
    select json_array(current_tic,last_command_seq,rng_cursor returning clob) into a_
      from game_sessions where session_token=apply_session_;
    select json_array(current_tic,last_command_seq,rng_cursor returning clob) into e_
      from game_sessions where session_token=oracle_session_;same(a_,e_,'DCTC frontier parity');
  end;
begin
  doom_api.new_game(3,apply_session_,payload_);commit;doom_api.new_game(3,oracle_session_,payload_);commit;
  setup_mixed(apply_session_);setup_mixed(oracle_session_);
  select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
    from game_sessions where session_token=apply_session_;
  select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=apply_session_;
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,sprite_frame,
    rotations null on null returning varchar2) order by state_id returning clob) into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);dbms_lob.converttoblob(map_blob_,map_clob_,
    dbms_lob.lobmaxsize,dest_,src_,nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));
  result_:=doom_unified_actor_load(apply_session_,lineage_,1,map_sha_);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'DCTC load '||result_);end if;
  command_:=hextoraw('444D53430201000000000000000000010101000100000000');
  savepoint configured_world;before_:=world_doc(apply_session_);request_:=lower(rawtohex(sys_guid()));
  delta_:=doom_unified_command_tic_prepare(apply_session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
  same(world_doc(apply_session_),before_,'DCTC prepare mutated SQL');
  expect_reject(command_,utl_raw.substr(delta_,1,utl_raw.length(delta_)-1),'truncated DCTC');
  bad_:=replace_bytes(delta_,19,1,hextoraw('01'));expect_reject(command_,bad_,'reserved DCTC');
  bad_:=replace_bytes(command_,21,1,hextoraw('01'));expect_reject(bad_,delta_,'malformed DMSC');
  bad_:=replace_bytes(delta_,268,4,utl_raw.substr(delta_,178,4));expect_reject(command_,bad_,'duplicate nested actor');
  doom_unified_delta_apply.apply_command_tic(apply_session_,lineage_,tic_,seq_,command_,delta_,
    committed_tic_,committed_seq_,version_,count_,sha_);advance_oracle;assert_parity;
  expect_reject(command_,delta_,'stale DCTC');
  rollback to configured_world;result_:=doom_unified_actor_discard(apply_session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,'DCTC discard '||result_);end if;

  request_:=lower(rawtohex(sys_guid()));delta_:=doom_unified_command_tic_prepare(
    apply_session_,lineage_,1,request_,tic_,seq_,rng_,next_mobj_,0,command_);
  doom_unified_delta_apply.apply_command_tic(apply_session_,lineage_,tic_,seq_,command_,delta_,
    committed_tic_,committed_seq_,version_,count_,sha_);advance_oracle;
  result_:=doom_unified_actor_accept(apply_session_,lineage_,1,request_);
  if result_<>'OK' then raise_application_error(-20000,'DCTC accept '||result_);end if;
  assert_parity;
  dbms_output.put_line('UNIFIED_COMMAND_DELTA_APPLY_OK tic='||committed_tic_||' seq='||
    committed_seq_||' bytes='||utl_raw.length(delta_)||' sha='||sha_);
  rollback;cleanup_sessions;
exception when others then rollback;cleanup_sessions;raise;
end;
/
