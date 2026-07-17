-- Strict durable applier for the committed DUOP/DTIC v1 worker result.
-- This package owns no commit.  It validates the complete buffer and all
-- relational frontiers before the first mutation, and rolls its own work back
-- on every exception so a malformed worker result cannot partially land.
create or replace package doom_unified_delta_apply authid definer as
  function trusted_event_insert return number;
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
  procedure apply_command_tic(
    p_session_token in varchar2,
    p_save_lineage in varchar2,
    p_expected_tic in number,
    p_expected_command_seq in number,
    p_command in raw,
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
  c_dtic_v2_header constant pls_integer:=108;
  c_actor_bytes constant pls_integer:=90;
  c_world_op_bytes constant pls_integer:=62;
  c_spawn_bytes constant pls_integer:=238;
  c_event_bytes constant pls_integer:=42;

  type actor_rec is record(
    id number,health_seen number,cooldown number,state_index number,
    state_tics number,death_processed number,awake number,flags number,
    target_id number,move_direction number,x number,y number,sector_id number,
    state_id varchar2(64));
  type actor_tab is table of actor_rec index by pls_integer;
  type spawn_rec is record(
    id number,thing_type number,state_index number,state_tics number,
    x number,y number,z number,mx number,my number,mz number,
    radius number,height number,health number,flags number,target_id number,
    tracer_id number,reaction_time number,spawn_thing_id number,
    owner_id number,exploded number,sector_id number,projectile_kind varchar2(4000),
    state_id varchar2(64));
  type spawn_tab is table of spawn_rec index by pls_integer;
  type world_op_rec is record(
    operation number,field_mask number,id number,x number,y number,
    health number,exploded number);
  type world_op_tab is table of world_op_rec index by pls_integer;
  type event_rec is record(
    ordinal number,type_code number,event_name varchar2(32),actor_id number,target_id number,
    number_value number,text_value varchar2(4000),previous_sha varchar2(64),event_sha varchar2(64));
  type event_tab is table of event_rec index by pls_integer;
  type id_set is table of boolean index by binary_integer;
  type presence_map is table of pls_integer index by binary_integer;
  type ordered_id_tab is table of number;
  type state_id_map is table of varchar2(64) index by binary_integer;
  type weapon_id_map is table of varchar2(32) index by binary_integer;
  type integer_map is table of pls_integer index by binary_integer;
  type text_set is table of boolean index by varchar2(4000);

  g_delta raw(32767);
  g_length pls_integer;
  g_catalog_signature varchar2(4000);
  g_state_ids state_id_map;
  g_weapon_ids weapon_id_map;
  g_weapon_bits integer_map;
  g_weapon_mask_all pls_integer:=0;
  g_sector_ids id_set;
  g_thing_type_ids id_set;
  g_spawn_thing_ids id_set;
  g_projectile_ids text_set;
  g_trusted_event_insert boolean:=false;

  function trusted_event_insert return number is
  begin return case when g_trusted_event_insert then 1 else 0 end;end;

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

  -- Fixed-layout DTIC/DCTC regions are bounded once by their enclosing block.
  -- These hot readers retain the exact canonical primitive checks without
  -- rebuilding diagnostic labels and repeating a bounds branch per field.
  function fixed_i32_at(p_position pls_integer) return number is
  begin
    return utl_raw.cast_to_binary_integer(
      utl_raw.substr(g_delta,p_position,4),utl_raw.big_endian);
  end;

  function fixed_number_at(p_position pls_integer) return number is
    l_bytes pls_integer;l_raw raw(22);l_value number;l_padding raw(22);
  begin
    l_bytes:=to_number(rawtohex(utl_raw.substr(g_delta,p_position,1)),'XX');
    if l_bytes<1 or l_bytes>22 then fail('fixed NUMBER length');end if;
    l_raw:=utl_raw.substr(g_delta,p_position+1,l_bytes);
    if l_bytes<22 then
      l_padding:=utl_raw.substr(g_delta,p_position+1+l_bytes,22-l_bytes);
      if rawtohex(l_padding)<>rpad('0',(22-l_bytes)*2,'0') then
        fail('fixed NUMBER padding');
      end if;
    end if;
    begin l_value:=utl_raw.cast_to_number(l_raw);
    exception when others then fail('fixed NUMBER bytes');end;
    if utl_raw.compare(l_raw,utl_raw.cast_from_number(l_value))<>0 then
      fail('fixed noncanonical NUMBER');
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

  function signed_byte_at(p_position pls_integer,p_label varchar2) return pls_integer is
    l_value pls_integer:=byte_at(p_position,p_label);
  begin
    return case when l_value>=128 then l_value-256 else l_value end;
  end;

  function event_type(p_code number) return varchar2 is
  begin
    return case p_code
      when 1 then 'MONSTER_HIT' when 2 then 'MONSTER_MISS'
      when 3 then 'MONSTER_PAIN' when 4 then 'MONSTER_DEATH'
      when 5 then 'MONSTER_DROP' when 6 then 'MONSTER_WAKE'
      when 7 then 'MONSTER_PROJECTILE' when 8 then 'DAMAGE'
      when 9 then 'BARREL_EXPLODE' when 10 then 'PROJECTILE_IMPACT'
      when 11 then 'PLAYER_DAMAGE' when 12 then 'WEAPON_LOWER'
      when 13 then 'WEAPON_RAISE' when 14 then 'HITSCAN_HIT'
      when 15 then 'HITSCAN_MISS' when 16 then 'DRY_FIRE'
      when 17 then 'PROJECTILE_SPAWN' end;
  end;

  procedure retain_catalogs is
    l_signature varchar2(4000);
  begin
    select
      (select count(*)||':'||coalesce(max(ora_rowscn),0) from doom_state_def)||'|'||
      (select count(*)||':'||coalesce(max(ora_rowscn),0) from doom_map_sector)||'|'||
      (select count(*)||':'||coalesce(max(ora_rowscn),0) from doom_thing_type_def)||'|'||
      (select count(*)||':'||coalesce(max(ora_rowscn),0) from doom_map_thing)||'|'||
      (select count(*)||':'||coalesce(max(ora_rowscn),0) from doom_projectile_def)||'|'||
      (select count(*)||':'||coalesce(max(ora_rowscn),0) from doom_weapon_def)
      into l_signature from dual;
    if l_signature=g_catalog_signature then return;end if;
    g_state_ids.delete;g_weapon_ids.delete;g_weapon_bits.delete;
    g_weapon_mask_all:=0;g_sector_ids.delete;g_thing_type_ids.delete;
    g_spawn_thing_ids.delete;g_projectile_ids.delete;
    declare l_index binary_integer:=0;begin
      for r in (select state_id from doom_state_def order by state_id) loop
        g_state_ids(l_index):=r.state_id;l_index:=l_index+1;
      end loop;
    end;
    declare l_index binary_integer:=0;begin
      for r in (select weapon_id,slot_number from doom_weapon_def order by slot_number) loop
        g_weapon_ids(l_index):=r.weapon_id;
        g_weapon_bits(l_index):=power(2,r.slot_number-1);
        g_weapon_mask_all:=g_weapon_mask_all+g_weapon_bits(l_index);
        l_index:=l_index+1;
      end loop;
    end;
    for r in (select sector_id from doom_map_sector) loop g_sector_ids(r.sector_id):=true;end loop;
    for r in (select thing_type from doom_thing_type_def) loop g_thing_type_ids(r.thing_type):=true;end loop;
    for r in (select thing_id from doom_map_thing) loop g_spawn_thing_ids(r.thing_id):=true;end loop;
    for r in (select thing_type,projectile_kind from doom_projectile_def) loop
      g_projectile_ids(to_char(r.thing_type,'TM9','NLS_NUMERIC_CHARACTERS=''.,''')||':'||
        r.projectile_kind):=true;
    end loop;
    g_catalog_signature:=l_signature;
  end;

  function world_id_exists(
    p_session_token varchar2,p_id number,p_cache in out nocopy presence_map
  ) return boolean is
    l_count pls_integer;
  begin
    if not p_cache.exists(p_id) then
      select count(*) into l_count from mobjs
        where session_token=p_session_token and mobj_id=p_id;
      p_cache(p_id):=case when l_count=1 then 1 else 0 end;
    end if;
    return p_cache(p_id)=1;
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
    l_dtic_version pls_integer;l_dtic_header pls_integer;
    l_world_op_count pls_integer;
    l_rng_draws pls_integer;l_final_rng number;l_player_health number;
    l_player_armor number;l_player_alive number;l_player_kills number;
    l_ammo_bullets number;l_ammo_shells number;l_ammo_rockets number;l_ammo_cells number;
    l_weapon_mask number;l_selected_weapon_index number;l_pending_weapon_index number;
    l_weapon_state_index number;l_weapon_state_tics number;l_flash_state_index number;
    l_flash_state_tics number;l_refire number;
    l_selected_weapon varchar2(32);l_pending_weapon varchar2(32);
    l_weapon_state varchar2(64);l_flash_state varchar2(64);
    l_next_mobj number;l_next_event number;l_next_tic number;l_next_seq number;
    l_current_tic number;l_current_seq number;l_current_rng number;
    l_lineage varchar2(64);l_player_id number;l_state_count number;
    l_expected_actors number;l_initial_mobj number;l_spawn_base number;l_initial_event number;
    l_present pls_integer;l_slot raw(23);l_value number;
    l_event_head varchar2(64);l_event_document clob;
    l_actors actor_tab;l_spawns spawn_tab;l_events event_tab;l_world_ops world_op_tab;
    l_removed id_set;
    l_world_presence presence_map;l_actor_ids ordered_id_tab;l_actor_presence id_set;
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
    l_dtic_version:=byte_at(17,'DTIC version');
    if l_dtic_version not in(1,2) or byte_at(18,'DTIC status')<>0 then fail('DTIC header');end if;
    l_dtic_header:=case l_dtic_version when 1 then c_dtic_header else c_dtic_v2_header end;
    if g_length<c_duop_header+l_dtic_header then fail('short DTIC versioned header');end if;
    l_actor_count:=u16_at(19,'actor count');l_spawn_count:=u16_at(21,'spawn count');
    l_event_count:=u16_at(23,'event count');l_rng_draws:=u16_at(25,'RNG draws');
    l_world_op_count:=u16_at(27,'world operation count');
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
    -- Retain the immutable catalogs and fenced world ID set for this call.  All
    -- decoded references are checked against these maps before the first DML;
    -- this avoids issuing one validation SELECT for every actor/reference.
    retain_catalogs;
    l_state_count:=g_state_ids.count;
    if l_dtic_version=2 then
      l_ammo_bullets:=i32_at(73,'ammo bullets');
      l_ammo_shells:=i32_at(77,'ammo shells');
      l_ammo_rockets:=i32_at(81,'ammo rockets');
      l_ammo_cells:=i32_at(85,'ammo cells');
      l_weapon_mask:=i32_at(89,'weapon mask');
      l_selected_weapon_index:=i32_at(93,'selected weapon');
      l_pending_weapon_index:=i32_at(97,'pending weapon');
      l_weapon_state_index:=i32_at(101,'weapon state');
      l_weapon_state_tics:=i32_at(105,'weapon state tics');
      l_flash_state_index:=i32_at(109,'flash state');
      l_flash_state_tics:=i32_at(113,'flash state tics');
      l_refire:=i32_at(117,'refire');
      if l_ammo_bullets<0 or l_ammo_shells<0 or l_ammo_rockets<0 or
         l_ammo_cells<0 or l_weapon_mask<0 or
         bitand(l_weapon_mask,g_weapon_mask_all)<>l_weapon_mask or
         l_selected_weapon_index<0 or l_selected_weapon_index>=g_weapon_ids.count or
         l_pending_weapon_index< -1 or l_pending_weapon_index>=g_weapon_ids.count or
         l_weapon_state_index<0 or l_weapon_state_index>=l_state_count or
         l_weapon_state_tics<0 or
         l_flash_state_index< -1 or l_flash_state_index>=l_state_count or
         l_flash_state_tics<0 or l_refire<0 then
        fail('weapon block value range');
      end if;
      if bitand(l_weapon_mask,g_weapon_bits(l_selected_weapon_index))=0 or
         (l_pending_weapon_index>=0 and
           bitand(l_weapon_mask,g_weapon_bits(l_pending_weapon_index))=0) then
        fail('weapon block ownership');
      end if;
      l_selected_weapon:=g_weapon_ids(l_selected_weapon_index);
      l_pending_weapon:=case when l_pending_weapon_index=-1 then null
        else g_weapon_ids(l_pending_weapon_index) end;
      l_weapon_state:=g_state_ids(l_weapon_state_index);
      l_flash_state:=case when l_flash_state_index=-1 then null
        else g_state_ids(l_flash_state_index) end;
    end if;
    -- DTIC actor_count is deliberately the behavior-bound monster subset
    -- (currently 53 on E1M1), not the owner's complete all-MOBJ world image
    -- (currently 280).  Non-monster rows remain unchanged; newly emitted drop
    -- and projectile records are appended below with the same defaults as the
    -- SQL oracle and the Java WorldMobjs.append path.
    select m.mobj_id bulk collect into l_actor_ids from mobjs m
      where m.session_token=p_session_token
      and exists(select 1 from doom_monster_def d where d.thing_type=m.thing_type)
      order by m.mobj_id;
    l_expected_actors:=l_actor_ids.count;
    for i in 1..l_expected_actors loop l_actor_presence(l_actor_ids(i)):=true;end loop;
    if l_actor_count>l_expected_actors then fail('actor count');end if;
    select coalesce(max(mobj_id),0)+1 into l_initial_mobj from mobjs
      where session_token=p_session_token;
    -- A prepared tic advances EXPECTED_TIC to NEXT_TIC.  Its events belong to
    -- that resulting logical tic, matching DOOM_TIC_TX.APPLY_BATCH(l_tic+ord).
    -- The retained owner starts NEXT_EVENT at zero for each new tic; deriving
    -- the relational frontier here also preserves exact append semantics when
    -- a prior subsystem has already emitted an event for the resulting tic.
    select coalesce(max(event_ordinal)+1,0) into l_initial_event from game_events
      where session_token=p_session_token and tic=l_next_tic;
    if l_next_event<>l_initial_event+l_event_count then fail('event frontier');end if;

    l_position:=case l_dtic_version when 1 then 73 else 121 end;
    need(l_position,l_actor_count*c_actor_bytes,'actor block');
    for i in 1..l_actor_count loop
      l_actors(i).id:=fixed_i32_at(l_position);
      l_actors(i).health_seen:=fixed_i32_at(l_position+4);
      l_actors(i).cooldown:=fixed_i32_at(l_position+8);
      l_actors(i).state_index:=fixed_i32_at(l_position+12);
      l_actors(i).state_tics:=fixed_i32_at(l_position+16);
      l_actors(i).death_processed:=fixed_i32_at(l_position+20);
      l_actors(i).awake:=fixed_i32_at(l_position+24);
      l_actors(i).flags:=fixed_i32_at(l_position+28);
      l_actors(i).target_id:=nullable_id(fixed_i32_at(l_position+32),'actor target');
      l_actors(i).move_direction:=fixed_i32_at(l_position+36);
      l_actors(i).x:=fixed_number_at(l_position+40);
      l_actors(i).y:=fixed_number_at(l_position+63);
      l_actors(i).sector_id:=fixed_i32_at(l_position+86);
      if l_actors(i).id<0 or l_actors(i).health_seen<0 or l_actors(i).cooldown<0 or
         l_actors(i).state_index<0 or l_actors(i).state_index>=l_state_count or
         l_actors(i).state_tics< -1 or l_actors(i).death_processed not in(0,1) or
         l_actors(i).awake not in(0,1) or l_actors(i).flags<0 or
         l_actors(i).move_direction< -1 or l_actors(i).move_direction>7 or
         l_actors(i).sector_id<0 then fail('actor value range');end if;
      l_actors(i).state_id:=g_state_ids(l_actors(i).state_index);
      l_position:=l_position+c_actor_bytes;
    end loop;

    need(l_position,l_world_op_count*c_world_op_bytes,'world operation block');
    for i in 1..l_world_op_count loop
      l_world_ops(i).operation:=byte_at(l_position,'world operation');
      l_world_ops(i).field_mask:=byte_at(l_position+1,'world operation mask');
      if u16_at(l_position+2,'world operation reserved')<>0 then fail('world operation reserved');end if;
      l_world_ops(i).id:=fixed_i32_at(l_position+4);
      if i>1 and l_world_ops(i).id<=l_world_ops(i-1).id then fail('world operation order');end if;
      if l_world_ops(i).operation=1 then
        if l_world_ops(i).field_mask<1 or l_world_ops(i).field_mask>15 then fail('world update mask');end if;
        if bitand(l_world_ops(i).field_mask,1)=1 then l_world_ops(i).x:=fixed_number_at(l_position+8);
        elsif rawtohex(utl_raw.substr(g_delta,l_position+8,23))<>rpad('0',46,'0') then fail('world x padding');end if;
        if bitand(l_world_ops(i).field_mask,2)=2 then l_world_ops(i).y:=fixed_number_at(l_position+31);
        elsif rawtohex(utl_raw.substr(g_delta,l_position+31,23))<>rpad('0',46,'0') then fail('world y padding');end if;
        l_world_ops(i).health:=fixed_i32_at(l_position+54);
        l_world_ops(i).exploded:=fixed_i32_at(l_position+58);
        if l_world_ops(i).health<0 or l_world_ops(i).exploded not in(0,1) then fail('world update value');end if;
      elsif l_world_ops(i).operation=2 then
        if l_world_ops(i).field_mask<>0 or
           rawtohex(utl_raw.substr(g_delta,l_position+8,46))<>rpad('0',92,'0') or
           fixed_i32_at(l_position+54)<>0 or fixed_i32_at(l_position+58)<>0 then
          fail('world removal payload');
        end if;
        l_removed(l_world_ops(i).id):=true;
      else fail('world operation code');end if;
      if l_world_ops(i).id<0 or
         not world_id_exists(p_session_token,l_world_ops(i).id,l_world_presence) then
        fail('world operation ID');
      end if;
      l_position:=l_position+c_world_op_bytes;
    end loop;
    l_spawn_base:=l_initial_mobj;
    while l_spawn_base>0 loop
      if l_removed.exists(l_spawn_base-1) then l_spawn_base:=l_spawn_base-1;
      elsif world_id_exists(p_session_token,l_spawn_base-1,l_world_presence) then exit;
      else l_spawn_base:=l_spawn_base-1;end if;
    end loop;
    if l_next_mobj<>l_spawn_base+l_spawn_count then fail('mobj frontier');end if;

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
      if l_spawns(i).id<>l_spawn_base+i-1 or l_spawns(i).thing_type<0 or
         l_spawns(i).state_index<0 or l_spawns(i).state_index>=l_state_count or
         l_spawns(i).state_tics< -1 or l_spawns(i).radius<0 or l_spawns(i).height<0 or
         l_spawns(i).health<0 or l_spawns(i).flags<0 or l_spawns(i).reaction_time<0 or
         l_spawns(i).exploded not in(0,1) or l_spawns(i).sector_id<0 then
        fail('spawn value range or ID sequence');
      end if;
      l_spawns(i).state_id:=g_state_ids(l_spawns(i).state_index);
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
         l_events(i).type_code<1 or l_events(i).type_code>17 or
         (l_dtic_version=1 and l_events(i).type_code>11) or
         (l_events(i).type_code in(1,2,3,4,5,6,7,10,11,17) and
           l_events(i).actor_id is null) or
         (l_events(i).type_code in(12,13,14,15,16) and l_events(i).actor_id is not null) or
         (l_events(i).type_code in(12,13,15,16) and l_events(i).target_id is not null) or
         (l_events(i).type_code=14 and l_events(i).target_id is null) then
        fail('event value or ordinal');
      end if;
      l_events(i).event_name:=event_type(l_events(i).type_code);
    end loop;
    if l_position<>g_length+1 then fail('trailing bytes');end if;

    -- Actor records are an ordered changed subset.  The full resident owner is
    -- independently parity-checked; every transmitted ID must still be a
    -- current behavior-bound monster and duplicates are rejected by ordering.
    for i in 1..l_actor_count loop
      if not l_actor_presence.exists(l_actors(i).id) or
         (i>1 and l_actors(i).id<=l_actors(i-1).id) then fail('actor ID set');end if;
    end loop;
    -- Validate referenced catalog and world IDs before any write.
    for i in 1..l_actor_count loop
      if not g_sector_ids.exists(l_actors(i).sector_id) then fail('actor sector ID');end if;
      if l_actors(i).target_id is not null and
         not world_id_exists(p_session_token,l_actors(i).target_id,l_world_presence) then
        fail('actor target ID');
      end if;
    end loop;
    for i in 1..l_spawn_count loop
      if not g_thing_type_ids.exists(l_spawns(i).thing_type) then fail('spawn thing ID');end if;
      if not g_sector_ids.exists(l_spawns(i).sector_id) then fail('spawn sector ID');end if;
      if l_spawns(i).projectile_kind is not null and
         not g_projectile_ids.exists(to_char(l_spawns(i).thing_type,'TM9',
           'NLS_NUMERIC_CHARACTERS=''.,''')||':'||l_spawns(i).projectile_kind) then
        fail('spawn projectile identity');
      end if;
      if l_spawns(i).spawn_thing_id is not null and
         not g_spawn_thing_ids.exists(l_spawns(i).spawn_thing_id) then
        fail('spawn source ID');
      end if;
      for j in 1..3 loop
        l_value:=case j when 1 then l_spawns(i).target_id when 2 then l_spawns(i).tracer_id else l_spawns(i).owner_id end;
        if l_value is not null then
          if not world_id_exists(p_session_token,l_value,l_world_presence) and
             (l_value<l_spawn_base or l_value>=l_next_mobj) then
            fail('spawn referenced mobj ID');
          end if;
        end if;
      end loop;
    end loop;
    for i in 1..l_event_count loop
      if l_events(i).actor_id is not null then
        if not world_id_exists(p_session_token,l_events(i).actor_id,l_world_presence) and
           (l_events(i).actor_id<l_spawn_base or l_events(i).actor_id>=l_next_mobj) then
          fail('event actor ID');
        end if;
      end if;
      if l_events(i).target_id is not null then
        if not world_id_exists(p_session_token,l_events(i).target_id,l_world_presence) and
           (l_events(i).target_id<l_spawn_base or l_events(i).target_id>=l_next_mobj) then
          fail('event target ID');
        end if;
      end if;
    end loop;

    if l_world_op_count>0 then
      forall i in 1..l_world_op_count
        merge into mobjs target using (
          select l_world_ops(i).operation operation,l_world_ops(i).field_mask field_mask,
            l_world_ops(i).id id,l_world_ops(i).x x,l_world_ops(i).y y,
            l_world_ops(i).health health,l_world_ops(i).exploded exploded from dual
        ) change on(target.session_token=p_session_token and target.mobj_id=change.id)
        when matched then update set
          target.x=case when bitand(change.field_mask,1)=1 then change.x else target.x end,
          target.y=case when bitand(change.field_mask,2)=2 then change.y else target.y end,
          target.health=case when bitand(change.field_mask,4)=4 then change.health else target.health end,
          target.exploded=case when bitand(change.field_mask,8)=8 then change.exploded else target.exploded end
        delete where change.operation=2;
      for i in 1..l_world_op_count loop
        if sql%bulk_rowcount(i)<>1 then fail('world operation race');end if;
      end loop;
    end if;
    if l_actor_count>0 then
      forall i in 1..l_actor_count
        update mobjs set
          monster_health_seen=l_actors(i).health_seen,
          health=l_actors(i).health_seen,
          attack_cooldown=l_actors(i).cooldown,
          state_id=l_actors(i).state_id,
          state_tics=l_actors(i).state_tics,death_processed=l_actors(i).death_processed,
          awake=l_actors(i).awake,flags=l_actors(i).flags,target_mobj_id=l_actors(i).target_id,
          move_direction=l_actors(i).move_direction,x=l_actors(i).x,y=l_actors(i).y,
          sector_id=l_actors(i).sector_id
        where session_token=p_session_token and mobj_id=l_actors(i).id and (
          coalesce(monster_health_seen,-1)<>l_actors(i).health_seen or
          health<>l_actors(i).health_seen or
          attack_cooldown<>l_actors(i).cooldown or state_id<>l_actors(i).state_id or
          state_tics<>l_actors(i).state_tics or death_processed<>l_actors(i).death_processed or
          awake<>l_actors(i).awake or flags<>l_actors(i).flags or
          coalesce(target_mobj_id,-1)<>coalesce(l_actors(i).target_id,-1) or
          move_direction<>l_actors(i).move_direction or x<>l_actors(i).x or
          y<>l_actors(i).y or sector_id<>l_actors(i).sector_id);
      -- The ordered actor-ID image was locked and validated above; zero-row
      -- bulk entries here are intentionally unchanged actors, not omissions.
    end if;
    if l_spawn_count>0 then
      forall i in 1..l_spawn_count
        insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
          momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
          target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,owner_mobj_id,
          projectile_kind,exploded,sector_id,move_direction,awake,attack_cooldown,
          monster_health_seen,death_processed)
        values(p_session_token,l_spawns(i).id,l_spawns(i).thing_type,l_spawns(i).state_id,
          l_spawns(i).state_tics,l_spawns(i).x,l_spawns(i).y,l_spawns(i).z,
          l_spawns(i).mx,l_spawns(i).my,l_spawns(i).mz,0,l_spawns(i).radius,
          l_spawns(i).height,l_spawns(i).health,l_spawns(i).flags,l_spawns(i).target_id,
          l_spawns(i).tracer_id,l_spawns(i).reaction_time,l_spawns(i).spawn_thing_id,
          l_spawns(i).owner_id,l_spawns(i).projectile_kind,l_spawns(i).exploded,
          l_spawns(i).sector_id,-1,0,0,null,0);
    end if;
    if l_event_count>0 then
      begin
        select event_sha into l_event_head from history_heads
          where session_token=p_session_token and lineage=p_save_lineage for update;
      exception when no_data_found then
        l_event_head:=rpad('0',64,'0');
        insert into history_heads(session_token,lineage,command_sha,event_sha)
        values(p_session_token,p_save_lineage,rpad('0',64,'0'),l_event_head);
      end;
      for i in 1..l_event_count loop
        l_events(i).previous_sha:=l_event_head;
        select json_object('lineage' value p_save_lineage,'tic' value l_next_tic,
          'ordinal' value l_events(i).ordinal,'type' value l_events(i).event_name,
          'actor' value l_events(i).actor_id,'target' value l_events(i).target_id,
          'number' value l_events(i).number_value,'text' value l_events(i).text_value,
          'previous_event_sha' value l_events(i).previous_sha returning clob)
          into l_event_document from dual;
        l_events(i).event_sha:=lower(rawtohex(
          dbms_crypto.hash(l_event_document,dbms_crypto.hash_sh256)));
        l_event_head:=l_events(i).event_sha;
      end loop;
      g_trusted_event_insert:=true;
      forall i in 1..l_event_count
        insert into game_events(session_token,lineage,tic,event_ordinal,event_type,
          actor_mobj_id,target_mobj_id,number_value,text_value,
          previous_event_sha,event_sha)
        values(p_session_token,p_save_lineage,l_next_tic,l_events(i).ordinal,
          l_events(i).event_name,l_events(i).actor_id,l_events(i).target_id,
          l_events(i).number_value,l_events(i).text_value,
          l_events(i).previous_sha,l_events(i).event_sha);
      g_trusted_event_insert:=false;
      update history_heads set event_sha=l_event_head
        where session_token=p_session_token and lineage=p_save_lineage;
      if sql%rowcount<>1 then fail('event history head');end if;
    end if;
    if l_dtic_version=1 then
      update players set health=l_player_health,armor=l_player_armor,
        alive=l_player_alive,kill_count=l_player_kills
        where session_token=p_session_token and player_id=l_player_id;
    else
      update players set health=l_player_health,armor=l_player_armor,
        alive=l_player_alive,kill_count=l_player_kills,
        ammo_bullets=l_ammo_bullets,ammo_shells=l_ammo_shells,
        ammo_rockets=l_ammo_rockets,ammo_cells=l_ammo_cells,
        weapon_mask=l_weapon_mask,selected_weapon=l_selected_weapon,
        pending_weapon=l_pending_weapon,weapon_state=l_weapon_state,
        weapon_state_tics=l_weapon_state_tics,flash_state=l_flash_state,
        flash_state_tics=l_flash_state_tics,refire=l_refire
        where session_token=p_session_token and player_id=l_player_id;
    end if;
    if sql%rowcount<>1 then fail('current player row');end if;
    update game_sessions set current_tic=l_next_tic,last_command_seq=l_next_seq,
      rng_cursor=l_final_rng where session_token=p_session_token;
    if sql%rowcount<>1 then fail('session update race');end if;

    p_committed_tic:=l_next_tic;p_committed_command_seq:=l_next_seq;
    p_delta_version:=l_dtic_version;p_delta_count:=1;
    p_delta_sha:=lower(rawtohex(dbms_crypto.hash(g_delta,dbms_crypto.hash_sh256)));
  exception
    when no_data_found then
      g_trusted_event_insert:=false;
      rollback to doom_unified_delta_apply_start;
      raise_application_error(-20841,'DTIC v1: missing fenced relational row');
    when others then
      g_trusted_event_insert:=false;
      rollback to doom_unified_delta_apply_start;
      raise;
  end;

  procedure apply_command_tic(
    p_session_token in varchar2,
    p_save_lineage in varchar2,
    p_expected_tic in number,
    p_expected_command_seq in number,
    p_command in raw,
    p_delta in raw,
    p_committed_tic out number,
    p_committed_command_seq out number,
    p_delta_version out number,
    p_delta_count out number,
    p_delta_sha out varchar2
  ) is
    c_command_bytes constant pls_integer:=24;
    c_dctc_header constant pls_integer:=105;
    l_command_version pls_integer;l_expected_dtic_version pls_integer;
    l_expected_dtic_header pls_integer;
    l_command_seq number;l_outer_seq number;l_outer_tic number;
    l_turn pls_integer;l_forward pls_integer;l_strafe pls_integer;l_run pls_integer;
    l_fire pls_integer;l_use pls_integer;l_weapon pls_integer;l_reserved pls_integer;
    l_child_length number;l_angle_index number;l_x number;l_y number;l_z number;
    l_sector number;l_derived_sector number;l_nested_length number;
    l_nested raw(32767);l_wrapped raw(32767);l_inner_tic number;l_inner_seq number;
    l_inner_version number;l_inner_count number;l_inner_sha varchar2(64);
  begin
    savepoint doom_unified_command_apply_start;
    p_committed_tic:=null;p_committed_command_seq:=null;
    p_delta_version:=null;p_delta_count:=null;p_delta_sha:=null;

    if p_command is null or utl_raw.length(p_command)<>c_command_bytes then
      fail('DMSC/v2 exact length');
    end if;
    g_delta:=p_command;g_length:=c_command_bytes;
    l_command_version:=byte_at(5,'DMSC version');
    if rawtohex(utl_raw.substr(g_delta,1,4))<>'444D5343' or
       l_command_version not in(2,3) or byte_at(6,'DMSC count')<>1 or
       byte_at(7,'DMSC reserved')<>0 or byte_at(8,'DMSC reserved')<>0 then
      fail('DMSC header');
    end if;
    l_expected_dtic_version:=l_command_version-1;
    l_expected_dtic_header:=case l_expected_dtic_version
      when 1 then c_dtic_header else c_dtic_v2_header end;
    l_command_seq:=u64_at(9,'DMSC sequence');
    if l_command_seq<>p_expected_command_seq+1 then fail('DMSC sequence gap');end if;
    l_turn:=signed_byte_at(17,'DMSC turn');
    l_forward:=signed_byte_at(18,'DMSC forward');
    l_strafe:=signed_byte_at(19,'DMSC strafe');l_run:=byte_at(20,'DMSC run');
    if l_turn not between -1 and 1 or l_forward not between -1 and 1 or
       l_strafe not between -1 and 1 or l_run not in(0,1) then
      fail('DMSC movement domain');
    end if;
    l_fire:=byte_at(21,'DMSC fire');l_use:=byte_at(22,'DMSC use');
    l_weapon:=byte_at(23,'DMSC weapon');l_reserved:=byte_at(24,'DMSC reserved');
    if l_command_version=2 then
      if l_fire<>0 or l_use<>0 or l_weapon<>0 or l_reserved<>0 then
        fail('DMSC/v2 unsupported action/reserved');
      end if;
    elsif l_fire not in(0,1) or l_use<>0 or l_weapon<0 or l_weapon>9 or l_reserved<>0 then
      fail('DMSC/v3 unsupported use/action domain');
    end if;

    if p_delta is null then fail('null DCTC delta');end if;
    g_delta:=p_delta;g_length:=utl_raw.length(g_delta);
    if g_length<12+c_dctc_header+60 then fail('short DCTC envelope');end if;
    if rawtohex(utl_raw.substr(g_delta,1,4))<>'44554F50' or
       byte_at(5,'DCTC DUOP version')<>1 or byte_at(6,'DCTC DUOP status')<>0 or
       byte_at(7,'DCTC DUOP mode')<>5 or byte_at(8,'DCTC DUOP reserved')<>0 then
      fail('DCTC DUOP header');
    end if;
    l_child_length:=u32_at(9,'DCTC child length');
    if l_child_length<>g_length-12 then fail('DCTC DUOP exact length');end if;
    if rawtohex(utl_raw.substr(g_delta,13,4))<>'44435443' or
       byte_at(17,'DCTC version')<>1 or byte_at(18,'DCTC status')<>0 or
       byte_at(19,'DCTC reserved')<>0 or byte_at(20,'DCTC command bytes')<>c_command_bytes then
      fail('DCTC header');
    end if;
    l_outer_seq:=u64_at(21,'DCTC command frontier');
    l_outer_tic:=u64_at(29,'DCTC tic frontier');
    if l_outer_seq<>l_command_seq or l_outer_seq<>p_expected_command_seq+1 or
       l_outer_tic<>p_expected_tic+1 then fail('DCTC outer frontier');end if;
    -- The minimum exact DCTC envelope check above covers this fixed 105-byte
    -- header, including all three canonical NUMBER slots.
    l_angle_index:=fixed_i32_at(37);
    if l_angle_index<0 or l_angle_index>63 then fail('DCTC angle index');end if;
    l_x:=fixed_number_at(41);l_y:=fixed_number_at(64);
    l_z:=fixed_number_at(87);l_sector:=fixed_i32_at(110);
    if l_sector<0 then fail('DCTC player sector');end if;
    begin
      select sector_id into l_derived_sector from table(doom_bsp_locate(l_x,l_y))
        where rownum=1;
    exception when no_data_found then fail('DCTC player sector lookup');end;
    if l_sector<>l_derived_sector then fail('DCTC player sector mismatch');end if;
    l_nested_length:=fixed_i32_at(114);
    if l_nested_length<l_expected_dtic_header or l_nested_length<>g_length-117 or
       l_child_length<>c_dctc_header+l_nested_length then
      fail('DCTC nested exact length');
    end if;
    l_nested:=utl_raw.substr(g_delta,118,l_nested_length);
    l_wrapped:=utl_raw.concat(hextoraw('44554F5001000400'),
      utl_raw.cast_from_binary_integer(l_nested_length,utl_raw.big_endian),l_nested);
    -- Cross-lock the two independently versioned frontiers before either the
    -- nested relational apply or the outer player movement can mutate state.
    g_delta:=l_wrapped;g_length:=utl_raw.length(l_wrapped);
    if rawtohex(utl_raw.substr(g_delta,13,4))<>'44544943' or
       byte_at(17,'nested DTIC version')<>l_expected_dtic_version or
       byte_at(18,'nested DTIC status')<>0 or
       u64_at(57,'nested DTIC tic frontier')<>l_outer_tic or
       u64_at(65,'nested DTIC command frontier')<>l_outer_seq then
      fail('DCTC nested DTIC frontier/header');
    end if;

    doom_unified_delta_apply.apply_tic(p_session_token,p_save_lineage,
      p_expected_tic,p_expected_command_seq,l_wrapped,l_inner_tic,l_inner_seq,
      l_inner_version,l_inner_count,l_inner_sha);
    if l_inner_tic<>l_outer_tic or l_inner_seq<>l_outer_seq or
       l_inner_version<>l_expected_dtic_version or l_inner_count<>1 then
      fail('DCTC nested apply metadata');
    end if;
    update players set x=l_x,y=l_y,z=l_z,angle=l_angle_index*5625/1000
      where session_token=p_session_token and player_id=(
        select current_player_id from game_sessions where session_token=p_session_token);
    if sql%rowcount<>1 then fail('DCTC current player row');end if;

    p_committed_tic:=l_outer_tic;p_committed_command_seq:=l_outer_seq;
    p_delta_version:=l_inner_version;p_delta_count:=1;
    p_delta_sha:=lower(rawtohex(dbms_crypto.hash(p_delta,dbms_crypto.hash_sh256)));
  exception
    when others then
      rollback to doom_unified_command_apply_start;
      raise;
  end;
end doom_unified_delta_apply;
/
