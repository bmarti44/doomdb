-- Strict durable applier for the committed DUOP/DTIC v1 worker result.
-- This package owns no commit.  It validates the complete buffer and all
-- relational frontiers before the first mutation, and rolls its own work back
-- on every exception so a malformed worker result cannot partially land.
create or replace package doom_unified_delta_apply authid definer as
  procedure apply_tic(
    p_session_token in varchar2,
    p_save_lineage in varchar2,
    p_expected_tic in number,
    p_expected_command_seq in number,
    p_delta in raw,
    p_committed_tic out number,
    p_committed_command_seq out number,
    p_delta_version out number,
    p_delta_count out number,
    p_delta_sha out varchar2
  );
end doom_unified_delta_apply;
/

create or replace package body doom_unified_delta_apply as
  c_duop_header constant pls_integer:=12;
  c_dtic_header constant pls_integer:=60;
  c_actor_bytes constant pls_integer:=90;
  c_spawn_bytes constant pls_integer:=238;
  c_event_bytes constant pls_integer:=42;

  type actor_rec is record(
    id number,health_seen number,cooldown number,state_index number,
    state_tics number,death_processed number,awake number,flags number,
    target_id number,move_direction number,x number,y number,sector_id number);
  type actor_tab is table of actor_rec index by pls_integer;
  type spawn_rec is record(
    id number,thing_type number,state_index number,state_tics number,
    x number,y number,z number,mx number,my number,mz number,
    radius number,height number,health number,flags number,target_id number,
    tracer_id number,reaction_time number,spawn_thing_id number,
    owner_id number,exploded number,sector_id number,projectile_kind varchar2(4000));
  type spawn_tab is table of spawn_rec index by pls_integer;
  type event_rec is record(
    ordinal number,type_code number,event_name varchar2(32),actor_id number,target_id number,
    number_value number,text_value varchar2(4000));
  type event_tab is table of event_rec index by pls_integer;

  g_delta raw(32767);
  g_length pls_integer;

  procedure fail(p_message varchar2) is
  begin
    raise_application_error(-20840,'DTIC v1: '||p_message);
  end;

  procedure need(p_position pls_integer,p_bytes pls_integer,p_label varchar2) is
  begin
    if p_position<1 or p_bytes<0 or p_position+p_bytes-1>g_length then
      fail('truncated '||p_label);
    end if;
  end;

  function byte_at(p_position pls_integer,p_label varchar2) return pls_integer is
  begin
    need(p_position,1,p_label);
    return to_number(rawtohex(utl_raw.substr(g_delta,p_position,1)),'XX');
  end;

  function u16_at(p_position pls_integer,p_label varchar2) return pls_integer is
  begin
    need(p_position,2,p_label);
    return to_number(rawtohex(utl_raw.substr(g_delta,p_position,2)),'XXXX');
  end;

  function i32_at(p_position pls_integer,p_label varchar2) return number is
  begin
    need(p_position,4,p_label);
    return utl_raw.cast_to_binary_integer(
      utl_raw.substr(g_delta,p_position,4),utl_raw.big_endian);
  end;

  function u32_at(p_position pls_integer,p_label varchar2) return number is
  begin
    need(p_position,4,p_label);
    return to_number(rawtohex(utl_raw.substr(g_delta,p_position,4)),
                     'XXXXXXXX');
  end;

  function u64_at(p_position pls_integer,p_label varchar2) return number is
    l_value number;
  begin
    l_value:=u32_at(p_position,p_label||' high')*4294967296+
             u32_at(p_position+4,p_label||' low');
    if l_value>999999999999 then fail(p_label||' exceeds NUMBER(12)');end if;
    return l_value;
  end;

  function number_at(p_position pls_integer,p_label varchar2) return number is
    l_bytes pls_integer;l_raw raw(22);l_value number;l_padding raw(22);
  begin
    need(p_position,23,p_label);
    l_bytes:=byte_at(p_position,p_label||' length');
    if l_bytes<1 or l_bytes>22 then fail(p_label||' NUMBER length');end if;
    l_raw:=utl_raw.substr(g_delta,p_position+1,l_bytes);
    if l_bytes<22 then
      l_padding:=utl_raw.substr(g_delta,p_position+1+l_bytes,22-l_bytes);
      if rawtohex(l_padding)<>rpad('0',(22-l_bytes)*2,'0') then
        fail(p_label||' NUMBER padding');
      end if;
    end if;
    begin l_value:=utl_raw.cast_to_number(l_raw);
    exception when others then fail(p_label||' NUMBER bytes');end;
    if utl_raw.compare(l_raw,utl_raw.cast_from_number(l_value))<>0 then
      fail(p_label||' noncanonical NUMBER');
    end if;
    return l_value;
  end;

  function text_at(
    p_position in out nocopy pls_integer,p_label varchar2
  ) return varchar2 is
    l_bytes pls_integer;l_raw raw(32767);l_text varchar2(32767);
  begin
    l_bytes:=u16_at(p_position,p_label||' length');p_position:=p_position+2;
    if l_bytes=65535 then return null;end if;
    -- Oracle folds an empty VARCHAR2 to NULL, so accepting a zero-byte string
    -- would make the durable row differ from the encoded worker value.
    if l_bytes=0 then fail(p_label||' empty text is not relationally lossless');end if;
    need(p_position,l_bytes,p_label);
    l_raw:=utl_raw.substr(g_delta,p_position,l_bytes);
    begin l_text:=utl_i18n.raw_to_char(l_raw,'AL32UTF8');
    exception when others then fail(p_label||' UTF-8');end;
    if utl_raw.compare(l_raw,utl_i18n.string_to_raw(l_text,'AL32UTF8'))<>0 then
      fail(p_label||' noncanonical UTF-8');
    end if;
    p_position:=p_position+l_bytes;
    return l_text;
  end;

  function nullable_id(p_value number,p_label varchar2) return number is
  begin
    if p_value=-1 then return null;end if;
    if p_value<0 then fail(p_label||' invalid null sentinel');end if;
    return p_value;
  end;

  function event_type(p_code number) return varchar2 is
  begin
    return case p_code
      when 1 then 'MONSTER_HIT' when 2 then 'MONSTER_MISS'
      when 3 then 'MONSTER_PAIN' when 4 then 'MONSTER_DEATH'
      when 5 then 'MONSTER_DROP' when 6 then 'MONSTER_WAKE'
      when 7 then 'MONSTER_PROJECTILE' end;
  end;

  procedure apply_tic(
    p_session_token in varchar2,
    p_save_lineage in varchar2,
    p_expected_tic in number,
    p_expected_command_seq in number,
    p_delta in raw,
    p_committed_tic out number,
    p_committed_command_seq out number,
    p_delta_version out number,
    p_delta_count out number,
    p_delta_sha out varchar2
  ) is
    l_position pls_integer;l_child_length number;
    l_actor_count pls_integer;l_spawn_count pls_integer;l_event_count pls_integer;
    l_rng_draws pls_integer;l_final_rng number;l_player_health number;
    l_player_armor number;l_player_alive number;l_player_kills number;
    l_next_mobj number;l_next_event number;l_next_tic number;l_next_seq number;
    l_current_tic number;l_current_seq number;l_current_rng number;
    l_lineage varchar2(64);l_player_id number;l_state_count number;
    l_expected_actors number;l_initial_mobj number;l_initial_event number;
    l_count number;l_present pls_integer;l_slot raw(23);l_value number;
    l_actors actor_tab;l_spawns spawn_tab;l_events event_tab;
  begin
    savepoint doom_unified_delta_apply_start;
    p_committed_tic:=null;p_committed_command_seq:=null;
    p_delta_version:=null;p_delta_count:=null;p_delta_sha:=null;
    if not regexp_like(p_session_token,'^[0-9a-f]{32}$') then fail('session token');end if;
    if not regexp_like(p_save_lineage,'^[0-9a-f]{64}$') then fail('save lineage');end if;
    if p_expected_tic<0 or p_expected_tic<>trunc(p_expected_tic) then fail('expected tic');end if;
    if p_expected_command_seq<0 or p_expected_command_seq<>trunc(p_expected_command_seq) then
      fail('expected command sequence');
    end if;
    if p_delta is null then fail('null delta');end if;
    g_delta:=p_delta;g_length:=utl_raw.length(g_delta);
    if g_length<c_duop_header+c_dtic_header then fail('short envelope');end if;
    if rawtohex(utl_raw.substr(g_delta,1,4))<>'44554F50' then fail('DUOP magic');end if;
    if byte_at(5,'DUOP version')<>1 or byte_at(6,'DUOP status')<>0 or
       byte_at(7,'DUOP mode')<>4 or byte_at(8,'DUOP reserved')<>0 then
      fail('DUOP header');
    end if;
    l_child_length:=u32_at(9,'DUOP child length');
    if l_child_length<>g_length-c_duop_header then fail('DUOP exact length');end if;
    if rawtohex(utl_raw.substr(g_delta,13,4))<>'44544943' then fail('DTIC magic');end if;
    if byte_at(17,'DTIC version')<>1 or byte_at(18,'DTIC status')<>0 then fail('DTIC header');end if;
    l_actor_count:=u16_at(19,'actor count');l_spawn_count:=u16_at(21,'spawn count');
    l_event_count:=u16_at(23,'event count');l_rng_draws:=u16_at(25,'RNG draws');
    if u16_at(27,'DTIC reserved')<>0 then fail('DTIC reserved');end if;
    l_final_rng:=i32_at(29,'RNG frontier');
    l_player_health:=i32_at(33,'player health');
    l_player_armor:=i32_at(37,'player armor');l_player_alive:=i32_at(41,'player alive');
    l_player_kills:=i32_at(45,'player kills');l_next_mobj:=i32_at(49,'mobj frontier');
    l_next_event:=i32_at(53,'event frontier');l_next_tic:=u64_at(57,'tic frontier');
    l_next_seq:=u64_at(65,'command frontier');
    if l_final_rng<0 or l_final_rng>255 or l_player_health<0 or l_player_armor<0 or
       l_player_alive not in(0,1) or l_player_kills<0 or l_next_mobj<0 or l_next_event<0 then
      fail('header value range');
    end if;

    select current_tic,last_command_seq,rng_cursor,save_lineage,current_player_id
      into l_current_tic,l_current_seq,l_current_rng,l_lineage,l_player_id
      from game_sessions where session_token=p_session_token for update;
    if l_lineage<>p_save_lineage then fail('lineage fence');end if;
    if l_current_tic<>p_expected_tic or l_current_seq<>p_expected_command_seq then
      fail('stale frontier');
    end if;
    if l_next_tic<>p_expected_tic+1 or l_next_seq<>p_expected_command_seq+1 then
      fail('non-unit frontier');
    end if;
    if l_final_rng<>mod(l_current_rng+l_rng_draws,256) then fail('RNG draw frontier');end if;
    select count(*) into l_state_count from doom_state_def;
    -- DTIC actor_count is deliberately the behavior-bound monster subset
    -- (currently 53 on E1M1), not the owner's complete all-MOBJ world image
    -- (currently 280).  Non-monster rows remain unchanged; newly emitted drop
    -- and projectile records are appended below with the same defaults as the
    -- SQL oracle and the Java WorldMobjs.append path.
    select count(*) into l_expected_actors from mobjs m
      where m.session_token=p_session_token and
        exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type);
    if l_actor_count<>l_expected_actors then fail('actor count');end if;
    select coalesce(max(mobj_id),0)+1 into l_initial_mobj from mobjs
      where session_token=p_session_token;
    if l_next_mobj<>l_initial_mobj+l_spawn_count then fail('mobj frontier');end if;
    select coalesce(max(event_ordinal)+1,0) into l_initial_event from game_events
      where session_token=p_session_token and tic=p_expected_tic;
    if l_next_event<>l_initial_event+l_event_count then fail('event frontier');end if;

    l_position:=73;
    for i in 1..l_actor_count loop
      l_actors(i).id:=i32_at(l_position,'actor id');
      l_actors(i).health_seen:=i32_at(l_position+4,'actor health seen');
      l_actors(i).cooldown:=i32_at(l_position+8,'actor cooldown');
      l_actors(i).state_index:=i32_at(l_position+12,'actor state');
      l_actors(i).state_tics:=i32_at(l_position+16,'actor state tics');
      l_actors(i).death_processed:=i32_at(l_position+20,'actor death flag');
      l_actors(i).awake:=i32_at(l_position+24,'actor awake');
      l_actors(i).flags:=i32_at(l_position+28,'actor flags');
      l_actors(i).target_id:=nullable_id(i32_at(l_position+32,'actor target'),'actor target');
      l_actors(i).move_direction:=i32_at(l_position+36,'actor direction');
      l_actors(i).x:=number_at(l_position+40,'actor x');
      l_actors(i).y:=number_at(l_position+63,'actor y');
      l_actors(i).sector_id:=i32_at(l_position+86,'actor sector');
      if l_actors(i).id<0 or l_actors(i).health_seen<0 or l_actors(i).cooldown<0 or
         l_actors(i).state_index<0 or l_actors(i).state_index>=l_state_count or
         l_actors(i).state_tics< -1 or l_actors(i).death_processed not in(0,1) or
         l_actors(i).awake not in(0,1) or l_actors(i).flags<0 or
         l_actors(i).move_direction< -1 or l_actors(i).move_direction>7 or
         l_actors(i).sector_id<0 then fail('actor value range');end if;
      l_position:=l_position+c_actor_bytes;
    end loop;

    for i in 1..l_spawn_count loop
      l_spawns(i).id:=i32_at(l_position,'spawn id');
      l_spawns(i).thing_type:=i32_at(l_position+4,'spawn thing');
      l_spawns(i).state_index:=i32_at(l_position+8,'spawn state');
      l_spawns(i).state_tics:=i32_at(l_position+12,'spawn state tics');
      l_spawns(i).x:=number_at(l_position+16,'spawn x');l_spawns(i).y:=number_at(l_position+39,'spawn y');
      l_spawns(i).z:=number_at(l_position+62,'spawn z');l_spawns(i).mx:=number_at(l_position+85,'spawn mx');
      l_spawns(i).my:=number_at(l_position+108,'spawn my');l_spawns(i).mz:=number_at(l_position+131,'spawn mz');
      l_spawns(i).radius:=number_at(l_position+154,'spawn radius');
      l_spawns(i).height:=number_at(l_position+177,'spawn height');
      l_spawns(i).health:=i32_at(l_position+200,'spawn health');
      l_spawns(i).flags:=i32_at(l_position+204,'spawn flags');
      l_spawns(i).target_id:=nullable_id(i32_at(l_position+208,'spawn target'),'spawn target');
      l_spawns(i).tracer_id:=nullable_id(i32_at(l_position+212,'spawn tracer'),'spawn tracer');
      l_spawns(i).reaction_time:=i32_at(l_position+216,'spawn reaction');
      l_spawns(i).spawn_thing_id:=nullable_id(i32_at(l_position+220,'spawn source'),'spawn source');
      l_spawns(i).owner_id:=nullable_id(i32_at(l_position+224,'spawn owner'),'spawn owner');
      l_spawns(i).exploded:=i32_at(l_position+228,'spawn exploded');
      l_spawns(i).sector_id:=i32_at(l_position+232,'spawn sector');
      l_position:=l_position+236;
      l_spawns(i).projectile_kind:=text_at(l_position,'spawn projectile kind');
      if l_spawns(i).id<>l_initial_mobj+i-1 or l_spawns(i).thing_type<0 or
         l_spawns(i).state_index<0 or l_spawns(i).state_index>=l_state_count or
         l_spawns(i).state_tics< -1 or l_spawns(i).radius<0 or l_spawns(i).height<0 or
         l_spawns(i).health<0 or l_spawns(i).flags<0 or l_spawns(i).reaction_time<0 or
         l_spawns(i).exploded not in(0,1) or l_spawns(i).sector_id<0 then
        fail('spawn value range or ID sequence');
      end if;
    end loop;

    for i in 1..l_event_count loop
      l_events(i).ordinal:=i32_at(l_position,'event ordinal');
      l_events(i).type_code:=i32_at(l_position+4,'event type');
      l_events(i).actor_id:=nullable_id(i32_at(l_position+8,'event actor'),'event actor');
      l_events(i).target_id:=nullable_id(i32_at(l_position+12,'event target'),'event target');
      l_present:=byte_at(l_position+16,'event NUMBER presence');
      if l_present=0 then
        l_slot:=utl_raw.substr(g_delta,l_position+17,23);
        if rawtohex(l_slot)<>rpad('0',46,'0') then fail('null event NUMBER bytes');end if;
        l_events(i).number_value:=null;
      elsif l_present=1 then
        l_events(i).number_value:=number_at(l_position+17,'event NUMBER');
      else fail('event NUMBER presence');end if;
      l_position:=l_position+40;
      l_events(i).text_value:=text_at(l_position,'event text');
      if l_events(i).ordinal<>l_initial_event+i-1 or
         l_events(i).type_code<1 or l_events(i).type_code>7 or
         l_events(i).actor_id is null then fail('event value or ordinal');end if;
      l_events(i).event_name:=event_type(l_events(i).type_code);
    end loop;
    if l_position<>g_length+1 then fail('trailing bytes');end if;

    -- Actor records must be a duplicate-free, exact ordered image of the
    -- current monster set.  This also rejects omission and ID substitution.
    l_count:=0;
    for r in (select m.mobj_id from mobjs m where m.session_token=p_session_token
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type)
      order by m.mobj_id) loop
      l_count:=l_count+1;
      if l_actors(l_count).id<>r.mobj_id then fail('actor ID set');end if;
    end loop;
    -- Validate referenced catalog and world IDs before any write.
    for i in 1..l_actor_count loop
      select count(*) into l_count from doom_map_sector where sector_id=l_actors(i).sector_id;
      if l_count<>1 then fail('actor sector ID');end if;
      if l_actors(i).target_id is not null then
        select count(*) into l_count from mobjs where session_token=p_session_token
          and mobj_id=l_actors(i).target_id;
        if l_count<>1 then fail('actor target ID');end if;
      end if;
    end loop;
    for i in 1..l_spawn_count loop
      select count(*) into l_count from doom_thing_type_def where thing_type=l_spawns(i).thing_type;
      if l_count<>1 then fail('spawn thing ID');end if;
      select count(*) into l_count from doom_map_sector where sector_id=l_spawns(i).sector_id;
      if l_count<>1 then fail('spawn sector ID');end if;
      if l_spawns(i).projectile_kind is not null then
        select count(*) into l_count from doom_projectile_def where projectile_kind=l_spawns(i).projectile_kind
          and thing_type=l_spawns(i).thing_type;
        if l_count<>1 then fail('spawn projectile identity');end if;
      end if;
      if l_spawns(i).spawn_thing_id is not null then
        select count(*) into l_count from doom_map_thing where thing_id=l_spawns(i).spawn_thing_id;
        if l_count<>1 then fail('spawn source ID');end if;
      end if;
      for j in 1..3 loop
        l_value:=case j when 1 then l_spawns(i).target_id when 2 then l_spawns(i).tracer_id else l_spawns(i).owner_id end;
        if l_value is not null then
          select count(*) into l_count from mobjs where session_token=p_session_token and mobj_id=l_value;
          if l_count=0 and (l_value<l_initial_mobj or l_value>=l_next_mobj) then
            fail('spawn referenced mobj ID');
          end if;
        end if;
      end loop;
    end loop;
    for i in 1..l_event_count loop
      select count(*) into l_count from mobjs where session_token=p_session_token
        and mobj_id=l_events(i).actor_id;
      if l_count=0 and (l_events(i).actor_id<l_initial_mobj or l_events(i).actor_id>=l_next_mobj) then
        fail('event actor ID');
      end if;
      if l_events(i).target_id is not null then
        select count(*) into l_count from mobjs where session_token=p_session_token
          and mobj_id=l_events(i).target_id;
        if l_count=0 and (l_events(i).target_id<l_initial_mobj or l_events(i).target_id>=l_next_mobj) then
          fail('event target ID');
        end if;
      end if;
    end loop;

    for i in 1..l_actor_count loop
      update mobjs set
        monster_health_seen=l_actors(i).health_seen,
        attack_cooldown=l_actors(i).cooldown,
        state_id=(select state_id from (select state_id,row_number() over(order by state_id)-1 state_index
          from doom_state_def) where state_index=l_actors(i).state_index),
        state_tics=l_actors(i).state_tics,death_processed=l_actors(i).death_processed,
        awake=l_actors(i).awake,flags=l_actors(i).flags,target_mobj_id=l_actors(i).target_id,
        move_direction=l_actors(i).move_direction,x=l_actors(i).x,y=l_actors(i).y,
        sector_id=l_actors(i).sector_id
      where session_token=p_session_token and mobj_id=l_actors(i).id;
      if sql%rowcount<>1 then fail('actor update race');end if;
    end loop;
    for i in 1..l_spawn_count loop
      insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
        momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
        target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
        projectile_kind,exploded,sector_id,move_direction,awake,attack_cooldown,
        monster_health_seen,death_processed)
      values(p_session_token,l_spawns(i).id,l_spawns(i).thing_type,
        (select state_id from (select state_id,row_number() over(order by state_id)-1 state_index
          from doom_state_def) where state_index=l_spawns(i).state_index),
        l_spawns(i).state_tics,l_spawns(i).x,l_spawns(i).y,l_spawns(i).z,
        l_spawns(i).mx,l_spawns(i).my,l_spawns(i).mz,0,l_spawns(i).radius,
        l_spawns(i).height,l_spawns(i).health,l_spawns(i).flags,l_spawns(i).target_id,
        l_spawns(i).tracer_id,l_spawns(i).reaction_time,l_spawns(i).spawn_thing_id,
        l_spawns(i).owner_id,l_spawns(i).projectile_kind,l_spawns(i).exploded,
        l_spawns(i).sector_id,-1,0,0,null,0);
    end loop;
    for i in 1..l_event_count loop
      insert into game_events(session_token,tic,event_ordinal,event_type,
        actor_mobj_id,target_mobj_id,number_value,text_value)
      values(p_session_token,p_expected_tic,l_events(i).ordinal,
        l_events(i).event_name,l_events(i).actor_id,l_events(i).target_id,
        l_events(i).number_value,l_events(i).text_value);
    end loop;
    update players set health=l_player_health,armor=l_player_armor,
      alive=l_player_alive,kill_count=l_player_kills
      where session_token=p_session_token and player_id=l_player_id;
    if sql%rowcount<>1 then fail('current player row');end if;
    update game_sessions set current_tic=l_next_tic,last_command_seq=l_next_seq,
      rng_cursor=l_final_rng where session_token=p_session_token;
    if sql%rowcount<>1 then fail('session update race');end if;

    p_committed_tic:=l_next_tic;p_committed_command_seq:=l_next_seq;
    p_delta_version:=1;p_delta_count:=1;
    p_delta_sha:=lower(rawtohex(dbms_crypto.hash(g_delta,dbms_crypto.hash_sh256)));
  exception
    when no_data_found then
      rollback to doom_unified_delta_apply_start;
      raise_application_error(-20841,'DTIC v1: missing fenced relational row');
    when others then
      rollback to doom_unified_delta_apply_start;
      raise;
  end;
end doom_unified_delta_apply;
/
