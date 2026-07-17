whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace procedure doom_perf_unified_attack_cases(
  p_start in pls_integer,p_end in pls_integer) authid current_user is
  session_ varchar2(32);lineage_ varchar2(64);payload_ blob;map_clob_ clob;map_blob_ blob;
  map_sha_ varchar2(64);result_ varchar2(4000);delta_ raw(32767);request_ varchar2(32);
  tic_ number;seq_ number;rng_ number;next_mobj_ number;next_event_ number;actor_ number;
  actors_ pls_integer;events_ pls_integer;draws_ pls_integer;off_ pls_integer;idx_ pls_integer;
  player_health_ number;player_armor_ number;player_alive_ number;case_count_ pls_integer:=0;
  event_idx_ pls_integer;text_len_ pls_integer;number_len_ pls_integer;actual_number_ number;
  source_x_ number;source_y_ number;target_x_ number;target_y_ number;pain_ number;
  dest_ integer:=1;src_ integer:=1;context_ integer:=0;warning_ integer;

  function int_(p raw,o pls_integer) return binary_integer is
  begin return utl_raw.cast_to_binary_integer(utl_raw.substr(p,o,4),utl_raw.big_endian);end;
  function u16(p raw,o pls_integer) return pls_integer is
  begin return to_number(rawtohex(utl_raw.substr(p,o,2)),'xxxx');end;
  procedure eq(a number,e number,m varchar2) is
  begin if (a is null and e is not null) or (a is not null and e is null) or a<>e then
    raise_application_error(-20000,m||' actual='||a||' expected='||e);end if;end;
begin
  update doom_config set number_value=greatest(number_value,256)
    where config_key='MAX_ACTIVE_SESSIONS';
  select json_arrayagg(json_array(state_id,tics,next_state_id,action_name,sprite_prefix,
    sprite_frame,rotations null on null returning varchar2) order by state_id returning clob)
    into map_clob_ from doom_state_def;
  dbms_lob.createtemporary(map_blob_,true,dbms_lob.call);
  dbms_lob.converttoblob(map_blob_,map_clob_,dbms_lob.lobmaxsize,dest_,src_,
    nls_charset_id('AL32UTF8'),context_,warning_);
  map_sha_:=lower(rawtohex(dbms_crypto.hash(map_blob_,dbms_crypto.hash_sh256)));

  for case_ in p_start..p_end loop
    doom_api.new_game(3,session_,payload_);
    select save_lineage,current_tic,last_command_seq,rng_cursor into lineage_,tic_,seq_,rng_
      from game_sessions where session_token=session_;
    -- The unified owner models the next resulting tic, whose event ordinal
    -- frontier is always zero.  Keep the standalone SQL oracle on that same
    -- empty resulting-tic frontier instead of seeding a prior-tic sentinel.
    delete from game_events where session_token=session_;
    update mobjs m set awake=0,attack_cooldown=0,health=0,monster_health_seen=0,
      death_processed=1,state_tics=0,sector_id=coalesce(sector_id,(select sector_id from
      table(doom_bsp_locate(m.x,m.y)) where rownum=1)) where session_token=session_ and exists(
      select 1 from doom_monster_def d where d.thing_type=m.thing_type);

    if case_ in(1,2,3,4,8,9,10,12,13) then
      select min(m.mobj_id) into actor_ from mobjs m join doom_monster_def d
        on d.thing_type=m.thing_type where m.session_token=session_ and d.attack_kind='MELEE';
      update mobjs m set awake=1,health=100,monster_health_seen=100,death_processed=0,
        state_id=(select d.melee_state_id from doom_monster_def d
        where d.thing_type=m.thing_type) where session_token=session_ and mobj_id=actor_;
    else
      select min(m.mobj_id) into actor_ from mobjs m join doom_monster_def d
        on d.thing_type=m.thing_type where m.session_token=session_ and d.attack_kind='HITSCAN';
      update mobjs m set awake=1,health=100,monster_health_seen=100,death_processed=0,
        state_id=(select d.missile_state_id from doom_monster_def d
        where d.thing_type=m.thing_type) where session_token=session_ and mobj_id=actor_;
    end if;
    select x,y into source_x_,source_y_ from mobjs where session_token=session_ and mobj_id=actor_;
    target_x_:=source_x_;target_y_:=source_y_;
    if case_=9 then
      update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d
        where d.thing_type=m.thing_type),attack_cooldown=0
        where session_token=session_ and mobj_id=actor_;
    elsif case_=10 then
      update mobjs m set awake=1,health=100,monster_health_seen=100,death_processed=0,
        x=source_x_,y=source_y_,sector_id=(select sector_id from table(
          doom_bsp_locate(source_x_,source_y_)) where rownum=1),
        state_id=(select d.melee_state_id from doom_monster_def d where d.thing_type=m.thing_type)
        where session_token=session_ and mobj_id=(select min(m2.mobj_id) from mobjs m2
          join doom_monster_def d2 on d2.thing_type=m2.thing_type
          where m2.session_token=session_ and d2.attack_kind='MELEE' and m2.mobj_id<>actor_);
    end if;

    if case_=4 then
      select x,y into target_x_,target_y_ from (select x,y from doom_map_thing
        where sqrt(power(x-source_x_,2)+power(y-source_y_,2))>256 order by thing_id) where rownum=1;
    elsif case_ in(6,7,11) then
      -- Same-sector points give the miss case an open long ray; a reject-table
      -- pair proves the hidden case without running an unbounded ray search.
      if case_=6 then
        select ax,ay,tx,ty into source_x_,source_y_,target_x_,target_y_ from (
          select a.x ax,a.y ay,b.x tx,b.y ty from mobjs a join mobjs b
            on b.session_token=a.session_token and b.sector_id=a.sector_id and b.mobj_id>a.mobj_id
          where a.session_token=session_ and
            sqrt(power(a.x-b.x,2)+power(a.y-b.y,2))>128
          order by sqrt(power(a.x-b.x,2)+power(a.y-b.y,2)) desc) where rownum=1;
      else
        select ax,ay,tx,ty into source_x_,source_y_,target_x_,target_y_ from (
          select a.x ax,a.y ay,b.x tx,b.y ty from mobjs a join mobjs b
            on b.session_token=a.session_token and b.mobj_id<>a.mobj_id
          join doom_sector_reject r on r.source_sector_id=a.sector_id
            and r.target_sector_id=b.sector_id and r.rejected=1
          where a.session_token=session_ order by a.mobj_id,b.mobj_id)
          where rownum=1;
      end if;
      update mobjs set x=source_x_,y=source_y_,sector_id=(select sector_id
        from table(doom_bsp_locate(source_x_,source_y_)) where rownum=1)
        where session_token=session_ and mobj_id=actor_;
    end if;
    if case_=11 then
      update mobjs m set state_id=(select d.chase_state_id from doom_monster_def d
        where d.thing_type=m.thing_type),attack_cooldown=0
        where session_token=session_ and mobj_id=actor_;
    end if;
    update players set x=target_x_,y=target_y_,health=100,armor=case when case_<=3 then 80 else 0 end,
      armor_type=case when case_<=3 then case_-1 else 0 end,alive=1 where session_token=session_
      and player_id=(select current_player_id from game_sessions where session_token=session_);

    if case_=6 then
      -- Maximize spread so the long visible ray is a deterministic MISS.
      select rng_index into rng_ from (select a.rng_index from doom_rng_value a join doom_rng_value b
        on b.rng_index=mod(a.rng_index+1,256) order by abs(a.rng_value-b.rng_value) desc)
        where rownum=1;
      update game_sessions set rng_cursor=rng_ where session_token=session_;
    elsif case_=8 then
      select d.pain_chance into pain_ from mobjs m join doom_monster_def d
        on d.thing_type=m.thing_type where m.session_token=session_ and m.mobj_id=actor_;
      select rng_index into rng_ from doom_rng_value where rng_value>=pain_ order by rng_index fetch first 1 row only;
      update game_sessions set rng_cursor=rng_ where session_token=session_;
      update mobjs set health=health-1,monster_health_seen=health where session_token=session_ and mobj_id=actor_;
    elsif case_=12 then
      select d.pain_chance into pain_ from mobjs m join doom_monster_def d
        on d.thing_type=m.thing_type where m.session_token=session_ and m.mobj_id=actor_;
      select rng_index into rng_ from doom_rng_value where rng_value<pain_ order by rng_index fetch first 1 row only;
      update game_sessions set rng_cursor=rng_ where session_token=session_;
      update mobjs set health=health-1,monster_health_seen=health,awake=0
        where session_token=session_ and mobj_id=actor_;
    elsif case_=13 then
      update players set health=1,armor=0,armor_type=0 where session_token=session_
        and player_id=(select current_player_id from game_sessions where session_token=session_);
    end if;

    select count(*) into actors_ from mobjs m join doom_monster_def d on d.thing_type=m.thing_type
      where m.session_token=session_;
    select coalesce(max(mobj_id),0)+1 into next_mobj_ from mobjs where session_token=session_;
    next_event_:=0;
    request_:=lower(rawtohex(sys_guid()));
    result_:=doom_unified_actor_load(session_,lineage_,1,map_sha_);
    if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'attack load '||result_);end if;
    delta_:=doom_unified_actor_prepare(session_,lineage_,1,request_,'ATTACK',
      tic_,seq_,rng_,next_mobj_,next_event_);
    if rawtohex(utl_raw.substr(delta_,1,8))<>'44554F5001000300' or
       rawtohex(utl_raw.substr(delta_,13,6))<>'4441544B0100' or int_(delta_,9)<>utl_raw.length(delta_)-12 then
      raise_application_error(-20000,'attack compact delta '||doom_unified_actor_last_error);end if;
    events_:=u16(delta_,21);draws_:=u16(delta_,23);
    doom_monsters.advance(session_,tic_);
    select health,armor,alive into player_health_,player_armor_,player_alive_ from players
      where session_token=session_ and player_id=(select current_player_id from game_sessions where session_token=session_);
    eq(int_(delta_,29),player_health_,'player health case '||case_);
    eq(int_(delta_,33),player_armor_,'player armor case '||case_);
    eq(int_(delta_,37),player_alive_,'player alive case '||case_);
    select rng_cursor into off_ from game_sessions where session_token=session_;
    eq(int_(delta_,25),off_,'RNG frontier case '||case_);
    eq(draws_,mod(off_-rng_+256,256),'RNG draws case '||case_);
    idx_:=0;off_:=45;
    for r in (with si as (select state_id,row_number() over(order by state_id)-1 n from doom_state_def)
      select m.mobj_id,m.monster_health_seen,m.attack_cooldown,si.n,m.state_tics,m.awake from mobjs m
      join doom_monster_def d on d.thing_type=m.thing_type join si on si.state_id=m.state_id
      where m.session_token=session_ order by m.mobj_id) loop
      eq(int_(delta_,off_+idx_*24),r.mobj_id,'actor id');
      eq(int_(delta_,off_+idx_*24+4),r.monster_health_seen,'actor seen');
      eq(int_(delta_,off_+idx_*24+8),r.attack_cooldown,'actor cooldown');
      eq(int_(delta_,off_+idx_*24+12),r.n,'actor state case='||case_||' id='||r.mobj_id);
      eq(int_(delta_,off_+idx_*24+16),r.state_tics,'actor tics case='||case_||' id='||r.mobj_id);
      eq(int_(delta_,off_+idx_*24+20),r.awake,'actor awake case='||case_||' id='||r.mobj_id);idx_:=idx_+1;
    end loop;
    eq(idx_,actors_,'actor rows');off_:=45+actors_*24;event_idx_:=0;
    for e in (select event_ordinal,event_type,actor_mobj_id,target_mobj_id,number_value,text_value
      from game_events where session_token=session_ and tic=tic_ and event_ordinal>=next_event_
      order by event_ordinal) loop
      eq(int_(delta_,off_),e.event_ordinal,'event ordinal');
      eq(int_(delta_,off_+4),case e.event_type when 'MONSTER_HIT' then 1
        when 'MONSTER_MISS' then 2 when 'MONSTER_PAIN' then 3 end,'event type');
      eq(int_(delta_,off_+8),e.actor_mobj_id,'event actor');
      eq(int_(delta_,off_+12),coalesce(e.target_mobj_id,-1),'event target');
      number_len_:=to_number(rawtohex(utl_raw.substr(delta_,off_+16,1)),'xx');
      actual_number_:=utl_raw.cast_to_number(utl_raw.substr(delta_,off_+17,number_len_));
      eq(actual_number_,e.number_value,'event number');text_len_:=u16(delta_,off_+39);
      if e.text_value is null then eq(text_len_,65535,'event null text');off_:=off_+41;
      else
        eq(text_len_,lengthb(e.text_value),'event text length');
        if utl_raw.cast_to_varchar2(utl_raw.substr(delta_,off_+41,text_len_))<>e.text_value then
          raise_application_error(-20000,'event text');end if;off_:=off_+41+text_len_;
      end if;event_idx_:=event_idx_+1;
    end loop;
    eq(event_idx_,events_,'event rows');eq(off_,utl_raw.length(delta_)+1,'exact attack length');
    if case_<=3 and events_<>1 then raise_application_error(-20000,'armor hit missing');end if;
    if case_=4 and (events_<>0 or draws_<>0) then raise_application_error(-20000,'melee range-before-LOS');end if;
    if case_=6 and events_<>1 then raise_application_error(-20000,'hitscan miss missing');end if;
    if case_=7 and (events_<>0 or draws_<>0) then raise_application_error(-20000,'invisible hitscan drew RNG');end if;
    if case_=8 and draws_<>2 then raise_application_error(-20000,'pain-fail continuation draws='||draws_);end if;
    if case_=9 and (events_<>1 or draws_<>1) then raise_application_error(-20000,'old cooldown attack selection');end if;
    if case_=10 and (events_<>2 or draws_<>2) then raise_application_error(-20000,'sequential player mutation');end if;
    if case_=11 and (events_<>0 or draws_<>0) then raise_application_error(-20000,'invisible CHASE gate');end if;
    if case_=12 and (events_<>1 or draws_<>1) then raise_application_error(-20000,'pain success gate');end if;
    if case_=13 and player_alive_<>0 then raise_application_error(-20000,'lethal hit gate');end if;
    result_:=doom_unified_actor_accept(session_,lineage_,1,request_);
    if result_<>'OK' then raise_application_error(-20000,'attack accept '||result_);end if;
    if case_=5 then
      select rng_cursor into rng_ from game_sessions where session_token=session_;
      result_:=doom_unified_actor_benchmark(session_,lineage_,1,'ATTACK',tic_,seq_,rng_,
        next_mobj_,next_event_+events_,cast(null as clob),300);
      if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,'attack benchmark '||result_);end if;
      dbms_output.put_line('unified_attack_prepare_discard_ns='||result_);
    end if;
    case_count_:=case_count_+1;rollback;
  end loop;
  dbms_output.put_line('unified_actor_attack_case_range='||p_start||'-'||p_end||
    ' count='||case_count_||' PASS');
end;
/
-- Keep each fixture in its own PL/SQL call.  doom_api.new_game returns a BLOB
-- locator, and retaining seven locators in one activation can terminate the
-- OJVM-backed session under the Free container's memory ceiling before the
-- Java catch-all can report a useful error.
begin doom_perf_unified_attack_cases(1,1);end;
/
begin doom_perf_unified_attack_cases(2,2);end;
/
begin doom_perf_unified_attack_cases(3,3);end;
/
begin doom_perf_unified_attack_cases(4,4);end;
/
begin doom_perf_unified_attack_cases(5,5);end;
/
begin doom_perf_unified_attack_cases(6,6);end;
/
begin doom_perf_unified_attack_cases(7,7);end;
/
begin doom_perf_unified_attack_cases(8,8);end;
/
begin doom_perf_unified_attack_cases(9,9);end;
/
begin doom_perf_unified_attack_cases(10,10);end;
/
begin doom_perf_unified_attack_cases(11,11);end;
/
begin doom_perf_unified_attack_cases(12,12);end;
/
begin doom_perf_unified_attack_cases(13,13);end;
/
begin
  dbms_output.put_line('UNIFIED_ACTOR_ATTACK_PARITY_OK cases=13 armor=3 melee_range=1'||
    ' hitscan_hit=1 hitscan_miss=1 invisible=1 pain_fail=1 old_cooldown=1'||
    ' sequential=1 chase_invisible=1 pain_success=1 lethal=1');
end;
/
drop procedure doom_perf_unified_attack_cases;
