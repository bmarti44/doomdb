-- Compact, passive retained-world lighting delta.  Building this pack is
-- deliberately read-only: RNG reads are simulated from the session frontier
-- and the unified delta applier remains the sole owner of that frontier.
create or replace package doom_retained_world_pack authid definer as
  procedure build(
    p_session_token in varchar2,
    p_tic in number,
    p_pack out raw
  );
  procedure apply(
    p_session_token in varchar2,
    p_tic in number,
    p_pack in raw,
    p_expected_start_rng in number,
    p_expected_draws in number
  );
  procedure build_geometry(
    p_session_token in varchar2,
    p_pack out raw
  );
end doom_retained_world_pack;
/

create or replace package body doom_retained_world_pack as
  c_header_bytes constant pls_integer:=12;
  c_row_bytes constant pls_integer:=12;
  c_max_rows constant pls_integer:=floor((32767-c_header_bytes)/c_row_bytes);

  type number_tab is table of number index by pls_integer;

  procedure fail(p_message varchar2) is
  begin
    raise_application_error(-20850,'DMWP v1: '||p_message);
  end;

  procedure append_raw(p_pack in out nocopy raw,p_value raw) is
  begin
    if p_value is not null then p_pack:=utl_raw.concat(p_pack,p_value);end if;
  end;

  procedure append_i32(p_pack in out nocopy raw,p_value number) is
  begin
    if p_value<>trunc(p_value) or p_value<-2147483648 or p_value>2147483647 then
      fail('i32 range');
    end if;
    append_raw(p_pack,utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian));
  end;

  procedure append_u16(p_pack in out nocopy raw,p_value number) is
  begin
    if p_value<>trunc(p_value) or p_value<0 or p_value>65535 then
      fail('u16 range');
    end if;
    append_raw(p_pack,utl_raw.substr(
      utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian),3,2));
  end;

  procedure append_number(p_pack in out nocopy raw,p_value number) is
    l_raw raw(22):=utl_raw.cast_from_number(p_value);l_length pls_integer:=utl_raw.length(l_raw);
  begin
    if l_length<1 or l_length>22 then fail('NUMBER length');end if;
    append_raw(p_pack,utl_raw.substr(utl_raw.cast_from_binary_integer(l_length,
      utl_raw.big_endian),4,1));append_raw(p_pack,l_raw);
    if l_length<22 then append_raw(p_pack,hextoraw(rpad('00',2*(22-l_length),'00')));end if;
  end;

  function byte_at(p_pack raw,p_position pls_integer,p_label varchar2)
    return pls_integer is
  begin
    if p_position<1 or p_position>utl_raw.length(p_pack) then
      fail('truncated '||p_label);
    end if;
    return to_number(rawtohex(utl_raw.substr(p_pack,p_position,1)),'XX');
  end;

  function u16_at(p_pack raw,p_position pls_integer,p_label varchar2)
    return pls_integer is
  begin
    if p_position<1 or p_position+1>utl_raw.length(p_pack) then
      fail('truncated '||p_label);
    end if;
    return to_number(rawtohex(utl_raw.substr(p_pack,p_position,2)),'XXXX');
  end;

  function i32_at(p_pack raw,p_position pls_integer,p_label varchar2)
    return number is
  begin
    if p_position<1 or p_position+3>utl_raw.length(p_pack) then
      fail('truncated '||p_label);
    end if;
    return utl_raw.cast_to_binary_integer(
      utl_raw.substr(p_pack,p_position,4),utl_raw.big_endian);
  end;

  procedure check_frontier(
    p_session_token varchar2,p_tic number,p_lock boolean,
    p_current_tic out number,p_start_rng out number
  ) is
  begin
    if p_tic is null or p_tic<>trunc(p_tic) or p_tic<1 then
      fail('invalid effect tic');
    end if;
    if p_lock then
      select current_tic,rng_cursor into p_current_tic,p_start_rng
        from game_sessions where session_token=p_session_token for update;
    else
      select current_tic,rng_cursor into p_current_tic,p_start_rng
        from game_sessions where session_token=p_session_token;
    end if;
    if p_current_tic<>p_tic-1 then fail('start tic frontier');end if;
  exception
    when no_data_found then fail('missing session');
  end;

  procedure validate_catalog(p_session_token varchar2) is
    l_rows number;l_catalog_rows number;
  begin
    select count(*) into l_rows
      from sector_state ss join doom_map_sector ms on ms.sector_id=ss.sector_id
     where ss.session_token=p_session_token and ms.special in(1,12);
    select count(*) into l_catalog_rows
      from sector_state ss
      join doom_map_sector ms on ms.sector_id=ss.sector_id
      join doom_sector_special_def d on d.special_id=ms.special
      join doom_sector_runtime_static rt on rt.sector_id=ss.sector_id
     where ss.session_token=p_session_token and ms.special in(1,12);
    if l_rows<>l_catalog_rows then fail('lighting catalog coverage');end if;
    if l_rows>c_max_rows then fail('pack exceeds RAW limit');end if;
  end;

  procedure build(
    p_session_token in varchar2,
    p_tic in number,
    p_pack out raw
  ) is
    l_current_tic number;l_start_rng number;l_cursor number;l_rng number;
    l_bright number;l_dark number;l_light number;l_timer number;
    l_count pls_integer:=0;l_draws pls_integer:=0;
    l_ids number_tab;l_lights number_tab;l_timers number_tab;
  begin
    check_frontier(p_session_token,p_tic,false,l_current_tic,l_start_rng);
    validate_catalog(p_session_token);
    select number_value into l_bright from doom_config
      where config_key='WORLD_STROBE_BRIGHT';
    select number_value into l_dark from doom_config
      where config_key='WORLD_STROBE_DARK';
    if l_bright is null or l_dark is null or
       l_bright<>trunc(l_bright) or l_dark<>trunc(l_dark) or
       l_bright<1 or l_dark<1 then fail('strobe configuration');end if;
    l_cursor:=l_start_rng;

    for s in (
      select ss.sector_id,ms.special,ss.light_level,ss.light_timer,
             ms.light_level base_light,rt.min_neighbor_light min_light
        from sector_state ss
        join doom_map_sector ms on ms.sector_id=ss.sector_id
        join doom_sector_special_def d on d.special_id=ms.special
        join doom_sector_runtime_static rt on rt.sector_id=ss.sector_id
       where ss.session_token=p_session_token and ms.special in(1,12)
       order by ss.sector_id
    ) loop
      l_light:=s.light_level;l_timer:=s.light_timer;
      if s.special=12 then
        l_light:=case
          when mod(p_tic-1,l_bright+l_dark)<l_bright
          then s.base_light else s.min_light end;
      else
        l_timer:=coalesce(s.light_timer,1)-1;
        if l_timer<=0 then
          select rng_value into l_rng from doom_rng_value
            where rng_index=mod(l_cursor,256);
          l_cursor:=mod(l_cursor+1,256);l_draws:=l_draws+1;
          if s.light_level=s.base_light then
            l_timer:=bitand(l_rng,7)+1;l_light:=s.min_light;
          else
            l_timer:=bitand(l_rng,64)+1;l_light:=s.base_light;
          end if;
        end if;
      end if;
      if l_light<>s.light_level or
         (l_timer<>s.light_timer or l_timer is null and s.light_timer is not null or
          l_timer is not null and s.light_timer is null) then
        l_count:=l_count+1;
        if l_count>c_max_rows then fail('pack exceeds RAW limit');end if;
        l_ids(l_count):=s.sector_id;l_lights(l_count):=l_light;
        l_timers(l_count):=coalesce(l_timer,-1);
      end if;
    end loop;
    if l_draws>65535 then fail('RNG draw count');end if;

    -- DMWP/v1: magic, version, reserved, count, starting RNG and logical
    -- draws, followed by ordered (sector, light, nullable timer) i32 triples.
    p_pack:=hextoraw('444D57500100');
    append_u16(p_pack,l_count);append_u16(p_pack,l_start_rng);
    append_u16(p_pack,l_draws);
    for i in 1..l_count loop
      append_i32(p_pack,l_ids(i));append_i32(p_pack,l_lights(i));
      append_i32(p_pack,l_timers(i));
    end loop;
    if utl_raw.length(p_pack)<>c_header_bytes+c_row_bytes*l_count or
       utl_raw.length(p_pack)>32767 then fail('pack length');end if;
  exception
    when no_data_found then fail('missing configuration or RNG catalog row');
  end build;

  procedure apply(
    p_session_token in varchar2,
    p_tic in number,
    p_pack in raw,
    p_expected_start_rng in number,
    p_expected_draws in number
  ) is
    l_current_tic number;l_start_rng number;l_light number;
    l_count pls_integer;
    l_position pls_integer;l_id number;l_encoded_timer number;
    l_ids number_tab;l_lights number_tab;l_timers number_tab;
  begin
    savepoint doom_retained_world_pack_start;
    if p_pack is null or utl_raw.length(p_pack)<c_header_bytes then
      fail('truncated header');
    end if;
    if rawtohex(utl_raw.substr(p_pack,1,4))<>'444D5750' then fail('magic');end if;
    if byte_at(p_pack,5,'version')<>1 then fail('version');end if;
    if byte_at(p_pack,6,'reserved')<>0 then fail('reserved byte');end if;
    l_count:=u16_at(p_pack,7,'row count');
    if l_count>c_max_rows or utl_raw.length(p_pack)<>c_header_bytes+c_row_bytes*l_count then
      fail('length');
    end if;
    if p_expected_start_rng is null or p_expected_start_rng<>trunc(p_expected_start_rng)
       or p_expected_start_rng<0 or p_expected_start_rng>255 then
      fail('expected starting RNG');
    end if;
    if p_expected_draws is null or p_expected_draws<>trunc(p_expected_draws)
       or p_expected_draws<0 or p_expected_draws>65535 then
      fail('expected RNG draws');
    end if;
    if u16_at(p_pack,9,'starting RNG')<>p_expected_start_rng or
       u16_at(p_pack,11,'RNG draws')<>p_expected_draws then
      fail('caller/pack RNG fence');
    end if;
    check_frontier(p_session_token,p_tic,true,l_current_tic,l_start_rng);
    if l_start_rng<>p_expected_start_rng then fail('session RNG frontier');end if;
    l_position:=c_header_bytes+1;
    for i in 1..l_count loop
      l_id:=i32_at(p_pack,l_position,'sector id');l_position:=l_position+4;
      l_light:=i32_at(p_pack,l_position,'light level');l_position:=l_position+4;
      l_encoded_timer:=i32_at(p_pack,l_position,'light timer');l_position:=l_position+4;
      if l_id<0 or (i>1 and l_id<=l_ids(i-1)) then fail('sector order');end if;
      if l_light<0 or l_light>255 then fail('light level');end if;
      if l_encoded_timer<-1 then fail('light timer');end if;
      l_ids(i):=l_id;l_lights(i):=l_light;l_timers(i):=l_encoded_timer;
    end loop;

    -- BUILD is the sole producer and this pack never crosses the AutoREST
    -- trust boundary. Java independently validates and consumes the exact
    -- bytes before APPLY. Avoid evaluating every world machine a second time
    -- here; lock the frontier above, then validate that every encoded target
    -- is still a catalogued passive-light sector as it is updated.
    if l_count>0 then
      forall i in 1..l_count
        update sector_state
           set light_level=l_lights(i),
               light_timer=case when l_timers(i)=-1 then null else l_timers(i) end
         where session_token=p_session_token and sector_id=l_ids(i)
           and exists(select 1 from doom_map_sector ms
             where ms.sector_id=l_ids(i) and ms.special in(1,12));
      if sql%rowcount<>l_count then fail('sector update race');end if;
    end if;
    -- game_sessions.rng_cursor is intentionally untouched.
  exception
    when no_data_found then
      rollback to doom_retained_world_pack_start;
      fail('missing relational row');
    when others then
      rollback to doom_retained_world_pack_start;
      raise;
  end apply;

  procedure build_geometry(
    p_session_token in varchar2,
    p_pack out raw
  ) is
    l_count pls_integer:=0;l_mobj_count pls_integer:=0;l_complete pls_integer;
    l_player_z number;l_health number;l_alive number;l_secrets number;
    l_rng number;l_next_event number;l_lineage varchar2(64);l_tic number;
    l_sector_ids number_tab;l_floors number_tab;l_ceilings number_tab;
    l_lights number_tab;l_light_timers number_tab;
    l_mobj_ids number_tab;l_mobj_z number_tab;
    l_chunk raw(32767);l_row raw(32767);
  begin
    -- DMWG/v4 carries an ordered sector delta plus a complete MOBJ-Z image.
    -- Active/reached mover sectors and passive lighting-special sectors are
    -- the only sector rows that can change in this transaction. Complete Z
    -- remains conservative for lift carry and blocking.
    p_pack:=hextoraw('444D57470401');
    select sector_id,floor_height,ceiling_height,light_level,coalesce(light_timer,-1)
      bulk collect into l_sector_ids,l_floors,l_ceilings,l_lights,l_light_timers
      from sector_state ss where ss.session_token=p_session_token and (
        exists(select 1 from doom_map_sector ms where ms.sector_id=ss.sector_id
          and ms.special in(1,12)) or
        exists(select 1 from active_movers am where am.session_token=ss.session_token
          and am.sector_id=ss.sector_id) or
        exists(select 1 from game_events e join game_sessions g
          on g.session_token=e.session_token and g.save_lineage=e.lineage
          where e.session_token=ss.session_token and e.tic=g.current_tic+1
            and e.event_type in('MOVER_REACHED','MOVER_RESUME','DOOR_REOPEN','LIFT_BLOCKED')
            and e.number_value=ss.sector_id)) order by ss.sector_id;
    l_count:=l_sector_ids.count;
    if l_count>c_max_rows then fail('geometry pack exceeds RAW limit');end if;
    select mobj_id,z bulk collect into l_mobj_ids,l_mobj_z from mobjs
      where session_token=p_session_token order by mobj_id;
    l_mobj_count:=l_mobj_ids.count;
    if l_mobj_count>65535 or 55+20*l_count+27*l_mobj_count>32767 then
      fail('geometry pack exceeds RAW capacity');end if;
    select case when map_status='COMPLETED' then 1 else 0 end,
      save_lineage,current_tic+1 into l_complete,l_lineage,l_tic
      from game_sessions where session_token=p_session_token;
    select p.z,p.health,p.alive,p.secret_count
      into l_player_z,l_health,l_alive,l_secrets
      from players p join game_sessions g on g.session_token=p.session_token
       and g.current_player_id=p.player_id where g.session_token=p_session_token;
    select rng_cursor into l_rng from game_sessions where session_token=p_session_token;
    select coalesce(max(event_ordinal)+1,0) into l_next_event from game_events
      where session_token=p_session_token and lineage=l_lineage and tic=l_tic;
    append_u16(p_pack,l_count);append_u16(p_pack,l_mobj_count);
    append_raw(p_pack,hextoraw(case when l_complete=1 then '01' else '00' end||'00'));
    append_number(p_pack,l_player_z);append_i32(p_pack,l_health);
    append_i32(p_pack,l_alive);append_i32(p_pack,l_secrets);
    append_i32(p_pack,l_rng);append_i32(p_pack,l_next_event);
    l_chunk:=null;
    for i in 1..l_count loop
      l_row:=null;append_i32(l_row,l_sector_ids(i));append_i32(l_row,l_floors(i));
      append_i32(l_row,l_ceilings(i));append_i32(l_row,l_lights(i));
      append_i32(l_row,l_light_timers(i));append_raw(l_chunk,l_row);
      if mod(i,64)=0 then append_raw(p_pack,l_chunk);l_chunk:=null;end if;
    end loop;
    append_raw(p_pack,l_chunk);l_chunk:=null;
    for i in 1..l_mobj_count loop
      l_row:=null;append_i32(l_row,l_mobj_ids(i));append_number(l_row,l_mobj_z(i));
      append_raw(l_chunk,l_row);
      if mod(i,64)=0 then append_raw(p_pack,l_chunk);l_chunk:=null;end if;
    end loop;
    append_raw(p_pack,l_chunk);
    if utl_raw.length(p_pack)<>c_header_bytes+43+20*l_count+27*l_mobj_count or
       utl_raw.length(p_pack)>32767 then
      fail('geometry pack length');
    end if;
  exception when no_data_found then fail('missing geometry row');
  end build_geometry;
end doom_retained_world_pack;
/
