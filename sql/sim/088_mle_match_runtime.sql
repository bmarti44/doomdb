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
  procedure save_checkpoint(
    p_checkpoint out blob,p_checkpoint_sha out varchar2,
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

  -- This inexpensive identity is SHA-256 over the complete retained canonical
  -- digest record (serialized-byte count, thinker count, and four independent
  -- 32-bit digest lanes). Full native SHA-256 material is retained at the
  -- checkpoint/audit boundary and in differential evidence, not exported each
  -- tic until the canonical-stage benchmark proves that affordable.
  function state_identity return varchar2 is
    l_status varchar2(32767) := doom_teavm_sim_canonical_state;
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
      l_loaded := doom_teavm_sim_allocate(l_length);
    elsif p_allocate='TABLES' then
      l_loaded := doom_teavm_sim_table_allocate(l_length);
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
        l_loaded := doom_teavm_sim_load(l_offset,l_chunk);
      else
        l_loaded := doom_teavm_sim_table_load(l_offset,l_chunk);
      end if;
      l_offset := l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(c_error,'MLE asset transfer mismatch');
      end if;
    end loop;
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
  end;

  procedure initialize_game(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_state_sha out varchar2
  ) is
    l_status varchar2(32767);
  begin
    clear_match_config;
    doom_teavm_sim_release;
    load_assets;
    dbms_application_info.set_action('MLE_GAME_INIT');
    l_status := doom_teavm_sim_multi_init_game(
      p_active_players,p_deathmatch,p_skill,p_episode,p_map);
    if l_status not like 'state=multiplayer-initialized|gametic=0|%' then
      raise_application_error(c_error,'MLE multiplayer initialization failed');
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
    begin doom_teavm_sim_release;exception when others then null;end;
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
    l_tic := doom_teavm_sim_authority_step(
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

  procedure save_checkpoint(
    p_checkpoint out blob,p_checkpoint_sha out varchar2,
    p_checkpoint_bytes out number
  ) is
    l_offset pls_integer := 0;
    l_chunk raw(32767);
  begin
    p_checkpoint_bytes := doom_teavm_sim_checkpoint_length;
    dbms_lob.createtemporary(p_checkpoint,true,dbms_lob.call);
    while l_offset<p_checkpoint_bytes loop
      l_chunk := doom_teavm_sim_checkpoint_chunk(
        l_offset,least(32767,p_checkpoint_bytes-l_offset));
      dbms_lob.writeappend(p_checkpoint,utl_raw.length(l_chunk),l_chunk);
      l_offset := l_offset+utl_raw.length(l_chunk);
    end loop;
    if dbms_lob.getlength(p_checkpoint)<>p_checkpoint_bytes then
      raise_application_error(c_error,'MLE checkpoint export mismatch');
    end if;
    p_checkpoint_sha := lower(rawtohex(
      dbms_crypto.hash(p_checkpoint,dbms_crypto.hash_sh256)));
  exception when others then
    if dbms_lob.istemporary(p_checkpoint)=1 then
      dbms_lob.freetemporary(p_checkpoint);
    end if;
    raise;
  end;

  procedure restore_loaded_checkpoint(
    p_tic in number,p_checkpoint in blob,p_state_sha out varchar2
  ) is
    l_length pls_integer := dbms_lob.getlength(p_checkpoint);
    l_offset pls_integer := 0;
    l_loaded number;
    l_chunk raw(32767);
    l_status varchar2(32767);
  begin
    dbms_application_info.set_action('MLE_CHECKPOINT_LOAD');
    l_loaded := doom_teavm_sim_restore_allocate(l_length);
    if l_loaded<>l_length then
      raise_application_error(c_error,'MLE checkpoint allocation mismatch');
    end if;
    while l_offset<l_length loop
      l_chunk := dbms_lob.substr(
        p_checkpoint,least(32767,l_length-l_offset),l_offset+1);
      l_loaded := doom_teavm_sim_restore_load(l_offset,l_chunk);
      l_offset := l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(c_error,'MLE checkpoint transfer mismatch');
      end if;
    end loop;
    dbms_application_info.set_action('MLE_CHECKPOINT_RESTORE');
    l_status := doom_teavm_sim_restore(p_tic);
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
    begin doom_teavm_sim_release;exception when others then null;end;
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
    l_status:=doom_teavm_sim_state;
    if l_status not like 'state=current|gametic=0|%'
       or status_field(l_status,'episode')<>to_char(p_episode)
       or status_field(l_status,'map')<>to_char(p_map) then
      raise_application_error(c_error,
        'warm MLE context is not initialized at the durable match origin');
    end if;
    restore_loaded_checkpoint(p_tic,p_checkpoint,p_state_sha);
  exception when others then
    clear_match_config;
    begin doom_teavm_sim_release;exception when others then null;end;
    raise;
  end;

  procedure prepare_origin_warm(
    p_active_players in number,p_deathmatch in number,p_skill in number,
    p_episode in number,p_map in number,p_state_sha out varchar2
  ) is
    l_checkpoint blob;l_expected_state varchar2(64);l_expected_sha varchar2(64);
    l_actual_sha varchar2(64);l_mode varchar2(16);
  begin
    if g_active_players is null or g_active_players<>p_active_players
       or g_episode<>p_episode or g_map<>p_map then
      raise_application_error(c_error,
        'warm MLE pool map/player configuration mismatch');
    end if;
    l_mode:=case p_deathmatch when 0 then 'COOP' else 'DEATHMATCH' end;
    select checkpoint_blob,state_sha256,checkpoint_sha256
      into l_checkpoint,l_expected_state,l_expected_sha
      from doom_mle_tic0_checkpoint
      where game_mode=l_mode and skill=p_skill and episode=p_episode
        and map=p_map and active_players=p_active_players
        and authority_sha256=
          'a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2';
    l_actual_sha:=lower(rawtohex(
      dbms_crypto.hash(l_checkpoint,dbms_crypto.hash_sh256)));
    if l_actual_sha<>l_expected_sha then
      raise_application_error(c_error,'warm MLE origin checkpoint SHA mismatch');
    end if;
    restore_loaded_checkpoint(0,l_checkpoint,p_state_sha);
    if p_state_sha<>l_expected_state then
      raise_application_error(c_error,'warm MLE origin state mismatch');
    end if;
    g_deathmatch:=p_deathmatch;
    g_skill:=p_skill;
  exception when others then
    clear_match_config;
    begin doom_teavm_sim_release;exception when others then null;end;
    raise;
  end;

  procedure release is
  begin
    clear_match_config;
    doom_teavm_sim_release;
  end;
end doom_mle_match_runtime;
/
