whenever sqlerror exit failure rollback
set define off

-- Session-resident production facade for the pinned TeaVM/MLE simulator.
-- The worker owns the transaction; this package never commits or rolls back.
create or replace package doom_mle_match_runtime authid definer as
  procedure initialize_game(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_state_sha out varchar2);
  procedure step_game(
    p_active_players in number,p_membership_mask in number,p_tic in number,
    p_command_vector in raw,p_state_sha out varchar2);
  procedure presentation_snapshot(
    p_player_slot in number,p_snapshot out raw);
  procedure render_and_publish(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_tic in number);
  procedure render_and_publish_views(
    p_match in varchar2,p_player_mask in number,p_membership_epoch in number,
    p_generation in number,p_tic in number);
  procedure flush_live_frames(
    p_match in varchar2,p_membership_epoch in number,p_generation in number);
  function authority_sha256 return varchar2;
  function memory_status return varchar2;
  function current_status return varchar2;
  procedure save_checkpoint(
    p_checkpoint out blob,p_checkpoint_sha out varchar2,
    p_checkpoint_bytes out number);
  procedure prepare_checkpoint(p_checkpoint_bytes out number);
  procedure export_prepared_checkpoint(
    p_checkpoint_bytes in number,p_checkpoint out blob,
    p_checkpoint_sha out varchar2);
  procedure save_checkpoint_into(
    p_checkpoint in out nocopy blob,p_checkpoint_sha out varchar2,
    p_checkpoint_bytes out number);
  procedure restore_checkpoint(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_tic in number,p_checkpoint in blob,
    p_state_sha out varchar2);
  -- Candidate recovery path for a Scheduler session that has already loaded
  -- the pinned assets and initialized the exact durable match configuration.
  -- Production recovery continues to use RESTORE_CHECKPOINT until the
  -- pre-warmed-standby lifecycle and differential gates pass.
  procedure restore_checkpoint_warm(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_tic in number,p_checkpoint in blob,
    p_state_sha out varchar2);
  -- Retarget an initialized E1M1 pool context from a hash-fenced clean origin.
  procedure prepare_origin_warm(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_state_sha out varchar2);
  procedure release;
end doom_mle_match_runtime;
/

create or replace package body doom_mle_match_runtime as
  c_error constant pls_integer := -20796;
  g_active_players number;
  g_deathmatch number;
  g_skill number;
  g_episode number;
  g_map number;
  g_renderer_assets_loaded boolean:=false;

  procedure clear_match_config is
  begin
    g_active_players:=null;
    g_deathmatch:=null;
    g_skill:=null;
    g_episode:=null;
    g_map:=null;
  end;

  function status_field(p_status varchar2,p_name varchar2) return varchar2 is
    l_marker varchar2(128) := p_name||'=';
    l_start pls_integer;
    l_finish pls_integer;
  begin
    l_start := instr(p_status,l_marker);
    if l_start=0 then
      raise_application_error(c_error,'MLE state identity missing '||p_name);
    end if;
    l_start := l_start+length(l_marker);
    l_finish := instr(p_status,'|',l_start);
    if l_finish=0 then l_finish := length(p_status)+1;end if;
    return substr(p_status,l_start,l_finish-l_start);
  end;

  function authority_sha256 return varchar2 is
    l_sha varchar2(64);
  begin
    -- Bind durable checkpoint selection to the authority bytes actually
    -- staged with this renderer deployment. Promotion and rollback therefore
    -- cannot retain a stale source-code literal that selects the wrong bank.
    select source_.authority_sha256 into l_sha
      from doom_mle_live_frame_source source_ where source_.artifact_id=1;
    if not regexp_like(l_sha,'^[0-9a-f]{64}$') then
      raise_application_error(c_error,'invalid live-frame authority SHA');
    end if;
    return l_sha;
  end;

  -- This inexpensive identity is SHA-256 over the complete retained canonical
  -- digest record (serialized-byte count, thinker count, and four independent
  -- 32-bit digest lanes). Full native SHA-256 material is retained at the
  -- checkpoint/audit boundary and in differential evidence, not exported each
  -- tic until the canonical-stage benchmark proves that affordable.
  function state_identity return varchar2 is
    l_status varchar2(32767) := doom_mle_live_canonical_state;
    l_canonical varchar2(32);
    l_identity varchar2(64);
  begin
    l_canonical := status_field(l_status,'canonicalState');
    if not regexp_like(l_canonical,'^[0-9a-f]{32}$') then
      raise_application_error(c_error,'invalid MLE canonical identity');
    end if;
    select lower(standard_hash(l_status,'SHA256')) into l_identity from dual;
    return l_identity;
  end;

  procedure load_blob(
    p_blob blob,p_allocate varchar2,p_load varchar2
  ) is
    l_length pls_integer := dbms_lob.getlength(p_blob);
    l_offset pls_integer := 0;
    l_chunk raw(32767);
    l_loaded number;
  begin
    if p_allocate='IWAD' then
      l_loaded := doom_mle_live_iwad_allocate(l_length);
    elsif p_allocate='TABLES' then
      l_loaded := doom_mle_live_table_allocate(l_length);
    elsif p_allocate='WORLD_PACK' then
      l_loaded := doom_mle_live_world_pack_allocate(l_length);
    elsif p_allocate='COMPOSITOR_PACK' then
      l_loaded := doom_mle_live_compositor_pack_allocate(l_length);
    elsif p_allocate='WALL' then
      l_loaded := doom_mle_live_wall_allocate(l_length);
    elsif p_allocate='FLAT' then
      l_loaded := doom_mle_live_flat_allocate(l_length);
    elsif p_allocate='SPRITE' then
      l_loaded := doom_mle_live_sprite_allocate(l_length);
    elsif p_allocate='UI' then
      l_loaded := doom_mle_live_ui_allocate(l_length);
    else
      raise_application_error(c_error,'unknown MLE asset kind');
    end if;
    if l_loaded<>l_length then
      raise_application_error(c_error,'MLE asset allocation mismatch');
    end if;
    while l_offset<l_length loop
      l_chunk := dbms_lob.substr(
        p_blob,least(32767,l_length-l_offset),l_offset+1);
      if p_load='IWAD' then
        l_loaded := doom_mle_live_iwad_load(l_offset,l_chunk);
      elsif p_load='TABLES' then
        l_loaded := doom_mle_live_table_load(l_offset,l_chunk);
      elsif p_load='WORLD_PACK' then
        l_loaded := doom_mle_live_world_pack_load(l_offset,l_chunk);
      elsif p_load='COMPOSITOR_PACK' then
        l_loaded := doom_mle_live_compositor_pack_load(l_offset,l_chunk);
      elsif p_load='WALL' then
        l_loaded := doom_mle_live_wall_load(l_offset,l_chunk);
      elsif p_load='FLAT' then
        l_loaded := doom_mle_live_flat_load(l_offset,l_chunk);
      elsif p_load='SPRITE' then
        l_loaded := doom_mle_live_sprite_load(l_offset,l_chunk);
      else
        l_loaded := doom_mle_live_ui_load(l_offset,l_chunk);
      end if;
      l_offset := l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(c_error,'MLE asset transfer mismatch');
      end if;
    end loop;
    if p_load='WORLD_PACK' then
      l_loaded:=doom_mle_live_world_pack_finalize;
    elsif p_load='COMPOSITOR_PACK' then
      l_loaded:=doom_mle_live_compositor_pack_finalize;
    elsif p_load='WALL' then
      l_loaded:=doom_mle_live_wall_finalize;
    elsif p_load='FLAT' then
      l_loaded:=doom_mle_live_flat_finalize;
    elsif p_load='SPRITE' then
      l_loaded:=doom_mle_live_sprite_finalize;
    elsif p_load='UI' then
      l_loaded:=doom_mle_live_ui_finalize;
    else
      return;
    end if;
    if l_loaded<>l_length then
      raise_application_error(c_error,'MLE renderer asset finalize mismatch');
    end if;
  end;

  procedure load_renderer_assets is
    l_world blob;l_compositor blob;l_asset blob;l_flat blob;l_sprite blob;
    l_ui blob;
  begin
    if g_renderer_assets_loaded then return;end if;
    dbms_application_info.set_action('MLE_RENDER_ASSET_LOAD');
    select world_pack,compositor_pack,wall_asset,flat_asset,
      sprite_asset,ui_asset
      into l_world,l_compositor,l_asset,l_flat,l_sprite,l_ui
      from doom_mle_live_frame_source where artifact_id=1;
    load_blob(l_world,'WORLD_PACK','WORLD_PACK');
    load_blob(l_compositor,'COMPOSITOR_PACK','COMPOSITOR_PACK');
    load_blob(l_asset,'WALL','WALL');
    load_blob(l_flat,'FLAT','FLAT');
    load_blob(l_sprite,'SPRITE','SPRITE');
    load_blob(l_ui,'UI','UI');
    g_renderer_assets_loaded:=true;
  end;

  procedure load_assets is
    l_wad blob;
    l_tables blob;
  begin
    dbms_application_info.set_action('MLE_ASSET_LOAD');
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    select table_pack_blob into l_tables from doom_teavm_sim_source;
    load_blob(l_wad,'IWAD','IWAD');
    load_blob(l_tables,'TABLES','TABLES');
    load_renderer_assets;
  end;

  procedure initialize_game(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_state_sha out varchar2
  ) is
    l_status varchar2(32767);
    l_prewarmed number;
  begin
    clear_match_config;
    doom_mle_live_release;
    load_assets;
    dbms_application_info.set_action('MLE_GAME_INIT');
    l_status := doom_mle_live_init_game(
      p_active_players,p_deathmatch,p_skill,p_episode,p_map);
    if l_status not like 'state=multiplayer-initialized|gametic=0|%' then
      raise_application_error(c_error,'MLE multiplayer initialization failed');
    end if;
    -- ADB's supported async compilation tier needs a real raster plateau.
    -- Prepay it in retained cloud slots before READY; the local interpreted
    -- Free container skips work that cannot improve its generated code.
    if sys_context('USERENV','CLOUD_SERVICE') is not null then
      dbms_application_info.set_action('MLE_RENDER_PREWARM');
      l_prewarmed:=doom_mle_live_frame_prewarm(600);
      if l_prewarmed<>600 then
        raise_application_error(c_error,'MLE renderer prewarm mismatch');
      end if;
    end if;
    p_state_sha := state_identity;
    -- Package state is session-local, just like the retained MLE context.
    -- Publish the configuration fence only after the complete initialization
    -- and canonical identity read have succeeded.
    g_active_players:=p_active_players;
    g_deathmatch:=p_deathmatch;
    g_skill:=p_skill;
    g_episode:=p_episode;
    g_map:=p_map;
  exception when others then
    clear_match_config;
    begin doom_mle_live_release;exception when others then null;end;
    raise;
  end;

  procedure step_game(
    p_active_players in number,p_membership_mask in number,p_tic in number,
    p_command_vector in raw,p_state_sha out varchar2
  ) is
    l_tic number;
  begin
    if p_command_vector is null or utl_raw.length(p_command_vector)<>32 then
      raise_application_error(c_error,'MLE authoritative vector length');
    end if;
    l_tic := doom_mle_live_step(
      p_active_players,p_membership_mask,p_command_vector);
    if l_tic<>p_tic then
      raise_application_error(c_error,
        'MLE worker tic mismatch expected='||p_tic||' actual='||l_tic);
    end if;
    -- Full canonical serialization costs ~583 ms in interpreted MLE. The live
    -- worker owns a cryptographic replay-identity chain instead; full canonical
    -- material remains a differential/audit operation.
    p_state_sha := null;
  end;

  procedure presentation_snapshot(
    p_player_slot in number,p_snapshot out raw
  ) is
    l_length number;
  begin
    if g_active_players is null or p_player_slot<0
       or p_player_slot>=g_active_players then
      raise_application_error(c_error,'MLE presentation player slot');
    end if;
    l_length:=doom_mle_live_world_length(p_player_slot);
    if l_length<208 or l_length>32767 then
      raise_application_error(c_error,'MLE DVL2 presentation length');
    end if;
    p_snapshot:=doom_mle_live_world_chunk(0,l_length);
    if utl_raw.length(p_snapshot)<>l_length
       or lower(rawtohex(utl_raw.substr(p_snapshot,1,8)))
          <>'44564c3202000000' then
      raise_application_error(c_error,'MLE DVL2 presentation payload');
    end if;
  end;

  procedure render_and_publish(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_tic in number
  ) is
    l_bytes number;
  begin
    if g_active_players is null or p_player_slot<0
       or p_player_slot>=g_active_players then
      raise_application_error(c_error,'MLE live-frame player slot');
    end if;
    l_bytes:=doom_mle_live_render_publish(
      p_match,p_player_slot,p_membership_epoch,p_generation,p_tic);
    if l_bytes<>64000 then
      raise_application_error(c_error,'MLE live-frame publication length');
    end if;
  end;

  procedure render_and_publish_views(
    p_match in varchar2,p_player_mask in number,p_membership_epoch in number,
    p_generation in number,p_tic in number
  ) is
    l_bytes number;
    l_players number;
  begin
    if g_active_players is null or p_player_mask not in(1,3)
       or bitand(p_player_mask,power(2,g_active_players)-1)<>p_player_mask then
      raise_application_error(c_error,'MLE shared-view player mask');
    end if;
    l_players:=case p_player_mask when 1 then 1 when 3 then 2 end;
    l_bytes:=doom_mle_live_render_publish_views(
      p_match,p_player_mask,p_membership_epoch,p_generation,p_tic);
    if l_bytes<>16+l_players*64000 then
      raise_application_error(c_error,'MLE shared-view publication length');
    end if;
  end;

  procedure flush_live_frames(
    p_match in varchar2,p_membership_epoch in number,p_generation in number
  ) is
    l_flushed number;
  begin
    l_flushed:=doom_mle_live_frame_flush(
      p_match,p_membership_epoch,p_generation);
    if l_flushed not between 0 and 2 then
      raise_application_error(c_error,'MLE live-frame flush count');
    end if;
  end;

  function memory_status return varchar2 is
  begin
    return doom_mle_live_memory;
  end;

  function current_status return varchar2 is
  begin
    return doom_mle_live_state;
  end;

  procedure save_checkpoint_into(
    p_checkpoint in out nocopy blob,p_checkpoint_sha out varchar2,
    p_checkpoint_bytes out number
  ) is
    l_offset pls_integer := 0;
    l_chunk raw(32767);
  begin
    if p_checkpoint is null or dbms_lob.getlength(p_checkpoint)<>0 then
      raise_application_error(c_error,'checkpoint target locator is not empty');
    end if;
    p_checkpoint_bytes := doom_mle_live_checkpoint_length;
    while l_offset<p_checkpoint_bytes loop
      l_chunk := doom_mle_live_checkpoint_chunk(
        l_offset,least(32767,p_checkpoint_bytes-l_offset));
      dbms_lob.writeappend(p_checkpoint,utl_raw.length(l_chunk),l_chunk);
      l_offset := l_offset+utl_raw.length(l_chunk);
    end loop;
    if dbms_lob.getlength(p_checkpoint)<>p_checkpoint_bytes then
      raise_application_error(c_error,'MLE checkpoint export mismatch');
    end if;
    p_checkpoint_sha := lower(rawtohex(
      dbms_crypto.hash(p_checkpoint,dbms_crypto.hash_sh256)));
  end;

  procedure prepare_checkpoint(p_checkpoint_bytes out number) is
  begin
    p_checkpoint_bytes:=doom_mle_live_checkpoint_length;
    if p_checkpoint_bytes<64 or p_checkpoint_bytes>16*1024*1024 then
      raise_application_error(c_error,'MLE checkpoint prepared length');
    end if;
  end;

  procedure export_prepared_checkpoint(
    p_checkpoint_bytes in number,p_checkpoint out blob,
    p_checkpoint_sha out varchar2
  ) is
    l_offset pls_integer:=0;
    l_chunk raw(32767);
  begin
    if p_checkpoint_bytes<64 or p_checkpoint_bytes>16*1024*1024 then
      raise_application_error(c_error,'MLE checkpoint export length');
    end if;
    dbms_lob.createtemporary(p_checkpoint,true,dbms_lob.call);
    while l_offset<p_checkpoint_bytes loop
      l_chunk:=doom_mle_live_checkpoint_chunk(
        l_offset,least(32767,p_checkpoint_bytes-l_offset));
      dbms_lob.writeappend(p_checkpoint,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    if dbms_lob.getlength(p_checkpoint)<>p_checkpoint_bytes then
      raise_application_error(c_error,'MLE prepared checkpoint export mismatch');
    end if;
    p_checkpoint_sha:=lower(rawtohex(
      dbms_crypto.hash(p_checkpoint,dbms_crypto.hash_sh256)));
  exception when others then
    if dbms_lob.istemporary(p_checkpoint)=1 then
      dbms_lob.freetemporary(p_checkpoint);
    end if;
    raise;
  end;

  procedure save_checkpoint(
    p_checkpoint out blob,p_checkpoint_sha out varchar2,
    p_checkpoint_bytes out number
  ) is
  begin
    prepare_checkpoint(p_checkpoint_bytes);
    export_prepared_checkpoint(
      p_checkpoint_bytes,p_checkpoint,p_checkpoint_sha);
  exception when others then
    if dbms_lob.istemporary(p_checkpoint)=1 then
      dbms_lob.freetemporary(p_checkpoint);
    end if;
    raise;
  end;

  procedure restore_loaded_checkpoint(
    p_tic in number,p_checkpoint in blob,p_state_sha out varchar2,
    p_warm_origin in boolean default false
  ) is
    l_length pls_integer := dbms_lob.getlength(p_checkpoint);
    l_offset pls_integer := 0;
    l_loaded number;
    l_chunk raw(32767);
    l_status varchar2(32767);
  begin
    dbms_application_info.set_action('MLE_CHECKPOINT_LOAD');
    l_loaded := doom_mle_live_restore_allocate(l_length);
    if l_loaded<>l_length then
      raise_application_error(c_error,'MLE checkpoint allocation mismatch');
    end if;
    while l_offset<l_length loop
      l_chunk := dbms_lob.substr(
        p_checkpoint,least(32767,l_length-l_offset),l_offset+1);
      l_loaded := doom_mle_live_restore_load(l_offset,l_chunk);
      l_offset := l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(c_error,'MLE checkpoint transfer mismatch');
      end if;
    end loop;
    dbms_application_info.set_action('MLE_CHECKPOINT_RESTORE');
    if p_warm_origin then
      l_status := doom_mle_live_restore_warm(p_tic);
    else
      l_status := doom_mle_live_restore(p_tic);
    end if;
    if l_status not like 'state=restored|gametic='||to_char(p_tic)||'|%' then
      raise_application_error(c_error,'MLE checkpoint restore mismatch');
    end if;
    p_state_sha := state_identity;
  end;

  procedure restore_checkpoint(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_tic in number,p_checkpoint in blob,
    p_state_sha out varchar2
  ) is
    l_ignored varchar2(64);
  begin
    initialize_game(p_active_players,p_deathmatch,p_skill,p_episode,p_map,l_ignored);
    restore_loaded_checkpoint(p_tic,p_checkpoint,p_state_sha);
  exception when others then
    clear_match_config;
    begin doom_mle_live_release;exception when others then null;end;
    raise;
  end;

  procedure restore_checkpoint_warm(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_tic in number,p_checkpoint in blob,
    p_state_sha out varchar2
  ) is
    l_status varchar2(32767);
  begin
    if g_active_players is null or g_active_players<>p_active_players
       or g_deathmatch<>p_deathmatch or g_skill<>p_skill
       or g_episode<>p_episode or g_map<>p_map then
      raise_application_error(c_error,
        'warm MLE context durable match configuration mismatch');
    end if;
    l_status:=doom_mle_live_state;
    if l_status not like 'state=current|gametic=0|%'
       or status_field(l_status,'episode')<>to_char(p_episode)
       or status_field(l_status,'map')<>to_char(p_map) then
      raise_application_error(c_error,
        'warm MLE context is not initialized at the durable match origin');
    end if;
    restore_loaded_checkpoint(p_tic,p_checkpoint,p_state_sha,true);
  exception when others then
    clear_match_config;
    begin doom_mle_live_release;exception when others then null;end;
    raise;
  end;

  procedure prepare_origin_warm(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_state_sha out varchar2
  ) is
    l_checkpoint blob;l_expected_state varchar2(64);l_expected_sha varchar2(64);
    l_actual_sha varchar2(64);l_mode varchar2(16);l_status varchar2(32767);
    l_authority_sha varchar2(64);l_same_origin boolean;
  begin
    if g_active_players is null or g_active_players<>p_active_players
       or g_episode<>p_episode or g_map<>p_map then
      raise_application_error(c_error,
        'warm MLE pool map/player configuration mismatch');
    end if;
    l_mode:=case p_deathmatch when 0 then 'COOP' else 'DEATHMATCH' end;
    l_authority_sha:=authority_sha256;
    select checkpoint_blob,state_sha256,checkpoint_sha256
      into l_checkpoint,l_expected_state,l_expected_sha
      from doom_mle_tic0_checkpoint
      where game_mode=l_mode and skill=p_skill and episode=p_episode
        and map=p_map and active_players=p_active_players
        and authority_sha256=l_authority_sha;
    l_actual_sha:=lower(rawtohex(
      dbms_crypto.hash(l_checkpoint,dbms_crypto.hash_sh256)));
    if l_actual_sha<>l_expected_sha then
      raise_application_error(c_error,'warm MLE origin checkpoint SHA mismatch');
    end if;
    l_status:=doom_mle_live_state;
    l_same_origin:=g_deathmatch=p_deathmatch and g_skill=p_skill
      and l_status like 'state=current|gametic=0|%'
      and status_field(l_status,'episode')=to_char(p_episode)
      and status_field(l_status,'map')=to_char(p_map);
    restore_loaded_checkpoint(0,l_checkpoint,p_state_sha,l_same_origin);
    if p_state_sha<>l_expected_state then
      raise_application_error(c_error,'warm MLE origin state mismatch');
    end if;
    g_deathmatch:=p_deathmatch;
    g_skill:=p_skill;
  exception when others then
    clear_match_config;
    begin doom_mle_live_release;exception when others then null;end;
    raise;
  end;

  procedure release is
  begin
    clear_match_config;
    doom_mle_live_release;
  end;
end doom_mle_match_runtime;
/
