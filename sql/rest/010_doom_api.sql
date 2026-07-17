whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

-- DOOM_API is deliberately the whole dynamic HTTP surface.  Helpers remain in
-- the body because object AutoREST publishes every member of the specification.
create or replace package doom_api authid definer as
  procedure new_game(
    p_skill       in  number,
    p_session     out varchar2,
    p_payload     out blob);

  procedure step(
    p_session     in  varchar2,
    p_commands    in  clob,
    p_payload     out blob);

  procedure save_game(
    p_session     in  varchar2,
    p_slot        in  number,
    p_state_sha   out varchar2);

  procedure load_game(
    p_session     in  varchar2,
    p_slot        in  number,
    p_payload     out blob);

  procedure start_replay(
    p_session     in  varchar2,
    p_from_tic    in  number,
    p_to_tic      in  number,
    p_replay_id   out varchar2);

  procedure step_replay(
    p_replay_id   in  varchar2,
    p_payload     out blob);

  procedure get_asset(
    p_asset_name  in  varchar2,
    p_payload     out blob,
    p_media_type  out varchar2);
end doom_api;
/

create or replace package body doom_api as
  c_bad_request constant pls_integer := -20701;
  c_capacity    constant pls_integer := -20702;
  c_session     constant pls_integer := -20703;
  c_asset       constant pls_integer := -20704;

  procedure fail(p_code pls_integer, p_message varchar2) is
  begin
    raise_application_error(p_code,p_message);
  end;

  function utc_now return timestamp with time zone is
  begin
    return localtimestamp at time zone 'UTC';
  end;

  function utf8_blob(p_text clob) return blob is
    l_blob blob;
    l_dest binary_integer := 1;
    l_src binary_integer := 1;
    l_context binary_integer := 0;
    l_warning binary_integer;
  begin
    dbms_lob.createtemporary(l_blob,true,dbms_lob.call);
    dbms_lob.converttoblob(l_blob,p_text,dbms_lob.lobmaxsize,l_dest,l_src,
      nls_charset_id('AL32UTF8'),l_context,l_warning);
    if l_warning<>0 then fail(c_bad_request,'UTF-8 conversion failed');end if;
    return l_blob;
  end;

  function blob_text(p_blob blob) return clob is
    l_text clob;
    l_dest binary_integer := 1;
    l_src binary_integer := 1;
    l_context binary_integer := 0;
    l_warning binary_integer;
  begin
    dbms_lob.createtemporary(l_text,true,dbms_lob.call);
    dbms_lob.converttoclob(l_text,p_blob,dbms_lob.lobmaxsize,l_dest,l_src,
      nls_charset_id('AL32UTF8'),l_context,l_warning);
    if l_warning<>0 then fail(c_bad_request,'UTF-8 conversion failed');end if;
    return l_text;
  end;

  -- This bounded transport loop converts four or fewer SQL-aggregated chunks;
  -- it never performs game, wall, object, or pixel decisions.
  function hex_blob(p_hex clob) return blob is
    l_blob blob;
    l_offset pls_integer := 1;
    l_piece varchar2(32000);
    l_raw raw(16000);
  begin
    dbms_lob.createtemporary(l_blob,true,dbms_lob.call);
    while l_offset<=dbms_lob.getlength(p_hex) loop
      l_piece:=dbms_lob.substr(p_hex,32000,l_offset);
      l_raw:=hextoraw(l_piece);
      dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);
      l_offset:=l_offset+length(l_piece);
    end loop;
    return l_blob;
  end;

  function sha256(p_blob blob) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.hash(p_blob,dbms_crypto.hash_sh256)));
  end;

  procedure require_session(p_session varchar2) is
    l_expiry timestamp with time zone;
  begin
    if p_session is null or not regexp_like(p_session,'^[0-9a-f]{32}$') then
      fail(c_session,'unknown or expired session');
    end if;
    select expires_at into l_expiry from game_sessions
      where session_token=p_session;
    if l_expiry<=utc_now then fail(c_session,'unknown or expired session');end if;
  exception when no_data_found then fail(c_session,'unknown or expired session');
  end;

  procedure copy_blob(p_source blob,p_target out blob) is
  begin
    dbms_lob.createtemporary(p_target,true,dbms_lob.call);
    dbms_lob.copy(p_target,p_source,dbms_lob.getlength(p_source));
  end;

  function config_number(p_key varchar2,p_default number) return number is
    l_value number;
  begin
    select number_value into l_value from doom_config where config_key=p_key;
    return l_value;
  exception when no_data_found then return p_default;
  end;

  function byte_hex(p_value number) return varchar2 is
  begin
    if p_value not in(-1,0,1) then fail(c_bad_request,'invalid movement command');end if;
    return case p_value when -1 then 'FF' when 0 then '00' else '01' end;
  end;

  function u64_hex(p_value number) return varchar2 is
  begin
    if p_value is null or p_value<>trunc(p_value) or
       p_value not between 0 and 999999999999 then
      fail(c_bad_request,'invalid command sequence');
    end if;
    return lpad(to_char(floor(p_value/4294967296),'fmxxxxxxxx'),8,'0')||
      lpad(to_char(mod(p_value,4294967296),'fmxxxxxxxx'),8,'0');
  end;

  -- Select the retained worker only for the DMSC/v2 surface it currently owns.
  -- Unsupported controls deliberately fall through to the complete SQL oracle.
  procedure worker_step(
    p_session in varchar2,p_commands in clob,p_used out number,p_payload out blob
  ) is
    l_count number;l_seq number;l_turn number;l_forward number;l_strafe number;
    l_run number;l_fire number;l_use number;l_weapon number;l_pause number;
    l_automap number;l_menu varchar2(32);l_cheat varchar2(4000);
    l_lineage varchar2(64);l_tic number;l_expected_seq number;
    l_deadline timestamp with time zone;
    l_generation number;l_ready number;l_map_sha varchar2(64);l_error varchar2(4000);
    l_request varchar2(32);l_command raw(24);l_status varchar2(16);
    l_response_generation number;l_committed_tic number;l_committed_seq number;
    l_delta_version number;l_delta_count number;l_delta_sha varchar2(64);
    l_state_sha varchar2(64);l_frame_sha varchar2(64);l_response_bytes number;
    l_response_sha varchar2(64);l_delta blob;l_worker_payload blob;
  begin
    p_used:=0;p_payload:=null;
    if config_number('UNIFIED_WORKER_ENABLED',0)<>1 then return;end if;
    begin
      select count(*),min(seq),min(turn),min(forward_move),min(strafe),min(run),
        min(fire),min(use_action),min(weapon),min(pause_toggle),min(automap_toggle),
        min(menu_action),min(cheat_json)
        into l_count,l_seq,l_turn,l_forward,l_strafe,l_run,l_fire,l_use,l_weapon,
          l_pause,l_automap,l_menu,l_cheat
        from json_table(p_commands,'$.commands[*]' columns(
          seq number path '$.seq' error on error,
          turn number path '$.turn' error on error,
          forward_move number path '$.forward' error on error,
          strafe number path '$.strafe' error on error,
          run number path '$.run' error on error,
          fire number path '$.fire' error on error,
          use_action number path '$.use' error on error,
          weapon number path '$.weapon' error on error,
          pause_toggle number path '$.pause' error on error,
          automap_toggle number path '$.automap' error on error,
          menu_action varchar2(32) path '$.menu' error on error,
          cheat_json varchar2(4000) path '$.cheat' error on error));
    exception when others then return;
    end;
    if l_count<>1 or l_seq is null or l_turn is null or l_forward is null or
       l_strafe is null or l_run is null or
       l_turn not in(-1,0,1) or l_forward not in(-1,0,1) or
       l_strafe not in(-1,0,1) or l_run not in(0,1) or
       coalesce(l_fire,0)<>0 or coalesce(l_use,0)<>0 or coalesce(l_weapon,0)<>0 or
       coalesce(l_pause,0)<>0 or coalesce(l_automap,0)<>0 or
       coalesce(l_menu,'NONE')<>'NONE' or l_cheat is not null then return;end if;

    select save_lineage,current_tic,last_command_seq
      into l_lineage,l_tic,l_expected_seq from game_sessions
      where session_token=p_session;
    l_command:=hextoraw('444D534302010000'||u64_hex(l_seq)||byte_hex(l_turn)||
      byte_hex(l_forward)||byte_hex(l_strafe)||
      case l_run when 0 then '00' else '01' end||'00000000');
    -- A network retry can arrive after the durable frontier advanced. Return
    -- the immutable committed response without needing the old worker generation.
    begin
      select r.response_blob into l_worker_payload
        from doom_worker_request q join doom_worker_result r
          on r.request_id=q.request_id
        where q.session_token=p_session and q.save_lineage=l_lineage
          and q.command_pack=l_command
          and q.request_status='COMMITTED';
      copy_blob(l_worker_payload,p_payload);p_used:=1;return;
    exception when no_data_found then null;end;
    if l_seq between l_expected_seq+2 and l_expected_seq+5 then
      -- The browser permits four ordered HTTP calls in flight. Earlier
      -- database tics normally commit while ORDS is still serializing their
      -- responses; wait only for those bounded predecessors.
      -- AQ dequeue occasionally crosses a one-second empty-poll boundary even
      -- though the native tic itself remains below budget.  Use the same
      -- bounded worker deadline here so a later correlated HTTP request cannot
      -- fail just before its predecessor commits.
      l_deadline:=systimestamp+numtodsinterval(
        config_number('UNIFIED_WORKER_WAIT_SECONDS',10),'SECOND');
      loop
        select current_tic,last_command_seq into l_tic,l_expected_seq
          from game_sessions where session_token=p_session;
        exit when l_seq=l_expected_seq+1;
        if l_seq<=l_expected_seq or systimestamp>=l_deadline then
          raise_application_error(c_capacity,'pipelined command frontier timeout');
        end if;
        dbms_session.sleep(.005);
      end loop;
    end if;
    if l_seq<>l_expected_seq+1 then return;end if;

    doom_worker_api.claim(p_session,l_generation,l_ready,l_map_sha,l_error);
    if l_ready<>1 or l_error is not null then
      raise_application_error(c_capacity,coalesce(l_error,'worker is not ready'));
    end if;
    l_request:=lower(substr(rawtohex(dbms_crypto.hash(
      utl_i18n.string_to_raw(p_session||'|'||l_lineage||'|'||
        to_char(l_generation,'TM9')||'|'||rawtohex(l_command),'AL32UTF8'),
        dbms_crypto.hash_sh256)),1,32));
    for l_attempt in 1..3 loop
      doom_worker_api.step(p_session,l_lineage,l_generation,l_request,l_tic,
        l_expected_seq,2,1,l_command,
        config_number('UNIFIED_WORKER_WAIT_SECONDS',10),l_status,
        l_response_generation,l_committed_tic,l_committed_seq,l_delta_version,
        l_delta_count,l_delta_sha,l_state_sha,l_frame_sha,l_response_bytes,
        l_response_sha,l_delta,l_worker_payload,l_error);
      exit when l_status in('COMMITTED','ROLLED_BACK','FAILED');
    end loop;
    if l_status<>'COMMITTED' or l_error is not null or
       l_response_generation<>l_generation or l_committed_tic<>l_tic+1 or
       l_committed_seq<>l_seq or l_worker_payload is null then
      raise_application_error(c_bad_request,'worker step failed: '||
        coalesce(l_error,l_status));
    end if;
    copy_blob(l_worker_payload,p_payload);p_used:=1;
  end;

  procedure stop_worker_for_sql_fallback(p_session varchar2) is
    l_active number;l_deadline timestamp with time zone;
  begin
    if config_number('UNIFIED_WORKER_ENABLED',0)<>1 then return;end if;
    begin
      doom_unified_worker.request_stop(p_session);
    exception when others then
      if sqlcode<>-20721 then raise;end if;
      return;
    end;
    l_deadline:=systimestamp+numtodsinterval(
      config_number('UNIFIED_WORKER_WAIT_SECONDS',10),'SECOND');
    loop
      select count(*) into l_active from doom_worker_control
        where target_session=p_session and ready=1;
      exit when l_active=0;
      if systimestamp>=l_deadline then
        raise_application_error(c_capacity,'worker stop timeout for SQL fallback');
      end if;
      dbms_session.sleep(.05);
    end loop;
  end;

  procedure render_payload(
    p_session varchar2,
    p_state_sha varchar2,
    p_payload out blob
  ) is
    l_tic number;
    l_mode varchar2(16);
    l_complete number;
    l_cols clob;
    l_audio clob;
    l_frame_hex clob;
    l_frame blob;
    l_frame_sha varchar2(64);
    l_document clob;
    l_plain blob;
  begin
    select current_tic,lower(game_mode),case when map_status='DONE' then 1 else 0 end
      into l_tic,l_mode,l_complete from game_sessions
      where session_token=p_session;

    -- Materialize shared render relations once. World and masked SQL otherwise
    -- expand the exact R1 hit/portal stream independently inside the combined
    -- presentation statement.
    delete from frame_render_seg_bound;
    insert into frame_render_seg_bound
      select /*+ opt_param('optimizer_adaptive_plans' 'false') */ *
      from doom_r1_staged_segment_bound_rows where session_token=p_session;
    delete from frame_r1_hit;
    insert into frame_r1_hit
      select /*+ opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_use_feedback' 'false') */ *
      from doom_r1_staged_hit_rows where session_token=p_session;
    delete from frame_portal_hit;
    insert into frame_portal_hit
      select /*+ opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_use_feedback' 'false') */ *
      from doom_r2_staged_portal_hit_rows where session_token=p_session;
    delete from frame_sector_interval;
    insert into frame_sector_interval
      select /*+ opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_use_feedback' 'false') */ *
      from doom_r2_staged_sector_interval_rows where session_token=p_session;
    delete from frame_world_pixel;
    insert into frame_world_pixel
      select /*+ opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_use_feedback' 'false') */ *
      from doom_r2_staged_pixel_rows where session_token=p_session;
    delete from frame_masked_pixel;
    insert into frame_masked_pixel(session_token,column_no,row_no,palette_index,
      source_kind,source_id)
      select /*+ opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_use_feedback' 'false') */
        session_token,column_no,row_no,palette_index,source_kind,source_id
      from doom_r2_staged_masked_candidate_rows
      where session_token=p_session and is_selected=1;

    -- Materialize the composed canvas once before downstream RLE and hash
    -- aggregation.
    delete from frame_column;
    insert into frame_column(session_token,column_no)
      select p_session,level-1 from dual connect by level<=320;
    delete from frame_pixel where session_token=p_session;
    if l_mode in ('game','dead') then
      -- GAME/DEAD already owns a complete world raster.  Copy it once, apply
      -- masked pixels inline, then rank only sparse presentation overlays.
      insert into frame_pixel(session_token,column_no,row_no,palette_index,
        layer_ordinal)
      select world.session_token,world.column_no,world.row_no,
        case when world.row_no>=168 then 0
             else coalesce(masked.palette_index,world.palette_index) end,
        case when world.row_no>=168 then 0
             when masked.palette_index is not null then 20 else 10 end
      from frame_world_pixel world
      left join frame_masked_pixel masked
        on masked.session_token=world.session_token
       and masked.column_no=world.column_no and masked.row_no=world.row_no
      where world.session_token=p_session;

      merge into frame_pixel target
      using (
        with state as (
          select session_row.session_token,session_row.paused,
            player.health,player.armor,player.blue_key,player.yellow_key,
            player.red_key,player.ammo_bullets,player.ammo_shells,
            player.ammo_rockets,player.ammo_cells,player.selected_weapon
          from game_sessions session_row
          join players player
            on player.session_token=session_row.session_token
           and player.player_id=session_row.current_player_id
          where session_row.session_token=p_session
        ), weapon as (
          select state.*,
            case selected_weapon when 'FIST' then 'PUNGA0'
              when 'PISTOL' then 'PISGA0' when 'SHOTGUN' then 'SHTGA0'
              when 'CHAINGUN' then 'CHGGA0'
              when 'ROCKET_LAUNCHER' then 'MISGA0'
              when 'PLASMA_RIFLE' then 'PLSGA0'
              when 'CHAINSAW' then 'SAWGA0' else 'PISGA0' end asset_name
          from state
        ), hud_values as (
          select state.session_token,'AMMO' field_name,
            to_char(case selected_weapon when 'SHOTGUN' then ammo_shells
              when 'ROCKET_LAUNCHER' then ammo_rockets
              when 'PLASMA_RIFLE' then ammo_cells else ammo_bullets end,
              'FM000','NLS_NUMERIC_CHARACTERS=''.,''') field_value,
            44 right_edge,171 top_row from state
          union all
          select session_token,'HEALTH',to_char(health,'FM000',
            'NLS_NUMERIC_CHARACTERS=''.,'''),90,171 from state
          union all
          select session_token,'ARMOR',to_char(armor,'FM000',
            'NLS_NUMERIC_CHARACTERS=''.,'''),221,171 from state
        ), hud_chars as (
          select value_row.*,digit.character_ordinal,
            substr(field_value,digit.character_ordinal,1) glyph,
            length(field_value) character_count
          from hud_values value_row
          cross join (select level character_ordinal from dual connect by level<=3) digit
        ), keys as (
          select session_token,0 key_ordinal,blue_key present from state
          union all select session_token,1,yellow_key from state
          union all select session_token,2,red_key from state
        ), candidates as (
          select weapon.session_token,floor((320-asset.width)/2)+texel.x column_no,
            200-asset.height+texel.y row_no,texel.c palette_index,30 layer_ordinal,
            'WEAPON' source_kind,asset.asset_name source_id
          from weapon join doom_asset asset
            on asset.asset_kind='sprite_patch' and asset.asset_name=weapon.asset_name
          join at texel on texel.a=asset.asset_id and texel.c>=0
          union all
          select state.session_token,texel.x,168+texel.y,texel.c,40,
            'HUD_PATCH',asset.asset_name
          from state join doom_asset asset
            on asset.asset_kind='ui_patch' and asset.asset_name='STBAR'
          join at texel on texel.a=asset.asset_id and texel.c>=0
          union all
          select chars.session_token,
            chars.right_edge-(chars.character_count-chars.character_ordinal+1)*13+
              texel.x,chars.top_row+texel.y,texel.c,43,'TEXT',
            chars.field_name||':'||chars.character_ordinal
          from hud_chars chars join doom_asset asset
            on asset.asset_kind='ui_patch' and asset.asset_name='STTNUM'||chars.glyph
          join at texel on texel.a=asset.asset_id and texel.c>=0
          union all
          select state.session_token,239+keys.key_ordinal*10+texel.x,
            171+texel.y,texel.c,44,'HUD_PATCH',asset.asset_name
          from state join keys on keys.session_token=state.session_token
          join doom_asset asset on asset.asset_kind='ui_patch'
           and asset.asset_name='STKEYS'||case keys.key_ordinal
             when 0 then '0' when 1 then '1' else '2' end
          join at texel on texel.a=asset.asset_id and texel.c>=0
          where keys.present=1
          union all
          select state.session_token,floor((320-asset.width)/2)+texel.x,
            4+texel.y,texel.c,50,'PAUSE',asset.asset_name
          from state join doom_asset asset
            on asset.asset_kind='ui_patch' and asset.asset_name='M_PAUSE'
          join at texel on texel.a=asset.asset_id and texel.c>=0
          where state.paused=1
        ), ranked as (
          select candidates.*,
            row_number() over(partition by session_token,column_no,row_no
              order by layer_ordinal desc,source_kind,source_id,palette_index) ordinal
          from candidates
          where column_no between 0 and 319 and row_no between 0 and 199
        )
        select session_token,column_no,row_no,palette_index,layer_ordinal
        from ranked where ordinal=1
      ) overlay
      on (target.session_token=overlay.session_token
        and target.column_no=overlay.column_no and target.row_no=overlay.row_no)
      when matched then update set target.palette_index=overlay.palette_index,
        target.layer_ordinal=overlay.layer_ordinal;
    else
      insert into frame_pixel(session_token,column_no,row_no,palette_index,
        layer_ordinal)
      select /*+ opt_param('optimizer_adaptive_plans' 'false') opt_param('_optimizer_use_feedback' 'false') */
        presentation.session_token,presentation.column_no,
        presentation.row_no,presentation.palette_index,presentation.layer_ordinal
      from doom_api_presentation_rows presentation
      join frame_column selected
        on selected.session_token=presentation.session_token
       and selected.column_no=presentation.column_no;
    end if;

    delete from frame_rle_run where session_token=p_session;
    insert into frame_rle_run(session_token,column_no,y0,run_length,palette_index)
    select p_session,column_no,y0,run_length,palette_index
    from (select column_no,row_no,palette_index from frame_pixel
      where session_token=p_session)
    match_recognize(
      partition by column_no order by row_no
      measures first(row_no) y0,count(*) run_length,
        first(palette_index) palette_index
      one row per match
      pattern(same_color+)
      define same_color as palette_index=first(palette_index)
    );

    select json_arrayagg(column_runs format json order by column_no returning clob)
      into l_cols
      from (
        select column_no,json_arrayagg(
          json_array(y0,run_length,palette_index returning clob)
          order by y0 returning clob) column_runs
        from frame_rle_run where session_token=p_session group by column_no
      );

    select xmlserialize(content xmlagg(xmlelement(e,h) order by chunk_no)
      as clob no indent)
      into l_frame_hex
      from (
        select floor((column_no*200+row_no)/1900) chunk_no,
          listagg(lpad(to_char(palette_index,'FMXX'),2,'0'),'')
            within group(order by column_no,row_no) h
        from frame_pixel where session_token=p_session
        group by floor((column_no*200+row_no)/1900)
      );
    l_frame_hex:=replace(replace(l_frame_hex,'<E>',''),'</E>','');
    l_frame:=hex_blob(l_frame_hex);
    l_frame_sha:=sha256(l_frame);

    select coalesce(json_arrayagg(
      json_array(tic,event_ordinal,asset_name,volume,separation returning clob)
      order by event_ordinal returning clob),to_clob('[]'))
      into l_audio
      from audio_events
      where session_token=p_session and tic=l_tic;

    select json_object(
      'v' value 1,
      'tic' value l_tic,
      'w' value 320,
      'h' value 200,
      'mode' value l_mode,
      'state_sha' value p_state_sha,
      'frame_sha' value l_frame_sha,
      'cols' value l_cols format json,
      'audio' value l_audio format json,
      'complete' value l_complete
      returning clob)
      into l_document from dual;
    l_plain:=utf8_blob(l_document);
    p_payload:=utl_compress.lz_compress(l_plain);
  end;

  procedure new_game(
    p_skill in number,p_session out varchar2,p_payload out blob
  ) is
    l_limit number;
    l_ttl number;
    l_count number;
    l_lineage varchar2(64);
    l_state_sha varchar2(64);
    l_unused varchar2(64);
    l_now timestamp with time zone;
    l_spawn_x number;l_spawn_y number;l_spawn_z number;l_spawn_angle number;
    l_spawn_sector number;
  begin
    p_session:=null;p_payload:=null;
    if p_skill is null or p_skill<>trunc(p_skill) or p_skill not between 1 and 5 then
      fail(c_bad_request,'skill must be an integer from 1 through 5');
    end if;

    l_now:=utc_now;
    delete from game_sessions where session_token in (
      select session_token from game_sessions where expires_at<=l_now
      order by expires_at fetch first 8 rows only);
    select number_value into l_limit from doom_config
      where config_key='MAX_ACTIVE_SESSIONS';
    select number_value into l_ttl from doom_config
      where config_key='SESSION_TTL_SECONDS';
    select count(*) into l_count from game_sessions where expires_at>l_now;
    if l_count>=l_limit then fail(c_capacity,'active session capacity reached');end if;

    p_session:=lower(rawtohex(dbms_crypto.randombytes(16)));
    select lower(standard_hash('lineage|'||p_session,'SHA256'))
      into l_lineage from dual;
    insert into game_sessions(session_token,game_mode,skill,current_tic,rng_cursor,
      map_status,paused,menu_state,automap_state,current_player_id,save_lineage,
      last_command_seq,expires_at,created_at)
    values(p_session,'GAME',p_skill,0,0,'ACTIVE',0,'NONE','OFF',null,l_lineage,0,
      l_now+numtodsinterval(l_ttl,'SECOND'),l_now);

    select x,y,angle into l_spawn_x,l_spawn_y,l_spawn_angle
      from doom_map_thing where thing_type=1 and rownum=1;
    select sector_id into l_spawn_sector
      from table(doom_bsp_locate(l_spawn_x,l_spawn_y)) where rownum=1;
    select floor_height into l_spawn_z from doom_map_sector
      where sector_id=l_spawn_sector;
    insert into players(session_token,player_id,x,y,z,momentum_x,momentum_y,
      momentum_z,angle,view_height,view_bob,health,armor,armor_type,blue_key,
      yellow_key,red_key,ammo_bullets,ammo_shells,ammo_rockets,ammo_cells,
      weapon_mask,selected_weapon,power_invulnerability,power_invisibility,
      power_ironfeet,power_lightamp,kill_count,item_count,secret_count,alive)
    values(p_session,0,l_spawn_x,l_spawn_y,l_spawn_z,0,0,0,l_spawn_angle,
      41,0,100,0,0,0,0,0,50,0,0,0,3,'PISTOL',0,0,0,0,0,0,0,1);
    update game_sessions set current_player_id=0 where session_token=p_session;

    insert into sector_state(session_token,sector_id,floor_height,ceiling_height,
      light_level,light_timer,secret_found,damage_clock)
    select p_session,sector_id,floor_height,ceiling_height,light_level,null,0,0
      from doom_map_sector;
    insert into line_state(session_token,linedef_id,trigger_count,switch_on)
    select p_session,linedef_id,0,0 from doom_map_linedef;

    insert into mobjs(session_token,mobj_id,thing_type,state_id,state_tics,x,y,z,
      momentum_x,momentum_y,momentum_z,angle,radius,height,health,flags,
      target_mobj_id,tracer_mobj_id,reaction_time,spawn_thing_id,sector_id)
    select p_session,t.thing_id,t.thing_type,d.spawn_state_id,s.tics,t.x,t.y,
      0,0,0,0,t.angle,coalesce(d.radius,0),coalesce(d.height,0),
      coalesce(d.spawn_health,1),d.flags,null,null,0,t.thing_id,null
    from doom_map_thing t
    join doom_thing_type_def d on d.thing_type=t.thing_type
    join doom_state_def s on s.state_id=d.spawn_state_id
    where t.thing_type<>1 and d.spawn_state_id is not null;

    -- SAVE_GAME uses the history package's canonical serializer to establish
    -- the trusted tic-zero snapshot.  Slot 99 is removed before publication.
    doom_history.save_game(p_session,99,l_state_sha);
    delete from save_slots where session_token=p_session and slot_number=99;
    render_payload(p_session,l_state_sha,p_payload);
    commit;
  exception when others then
    rollback;p_session:=null;p_payload:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_bad_request,'new game failed');
  end;

  procedure step(
    p_session in varchar2,p_commands in clob,p_payload out blob
  ) is
    l_first number;l_last number;l_sha varchar2(64);l_cached blob;
    l_canonical clob;
    l_internal blob;l_state_sha varchar2(64);
    l_response_text clob;l_worker_used number;
  begin
    p_payload:=null;require_session(p_session);
    worker_step(p_session,p_commands,l_worker_used,p_payload);
    if l_worker_used=1 then return;end if;
    -- SQL may accept controls that are not yet retained. Stop the current owner
    -- first so the next eligible command reconstructs from the new SQL frontier.
    stop_worker_for_sql_fallback(p_session);
    begin
      select min(seq) keep(dense_rank first order by ord),
        max(seq) keep(dense_rank last order by ord)
        into l_first,l_last
        from json_table(p_commands,'$.commands[*]' columns(
          ord for ordinality,seq number path '$.seq' error on error));
      select json_object('v' value 1,'commands' value json_arrayagg(
        json_object('seq' value seq,'turn' value turn,
          'forward' value forward_move,'strafe' value strafe,
          'run' value run,'fire' value fire,'use' value use_action,
          'weapon' value weapon,'pause' value pause_toggle,
          'automap' value automap_toggle,'menu' value menu_action,
          'cheat' value cheat_json format json returning clob)
        order by ord returning clob) format json returning clob)
        into l_canonical
        from json_table(p_commands,'$.commands[*]' columns(
          ord for ordinality,seq number path '$.seq',turn number path '$.turn',
          forward_move number path '$.forward',strafe number path '$.strafe',
          run number path '$.run',fire number path '$.fire',
          use_action number path '$.use',weapon number path '$.weapon',
          pause_toggle number path '$.pause',automap_toggle number path '$.automap',
          menu_action varchar2(32) path '$.menu',
          cheat_json varchar2(4000) format json path '$.cheat'));
      l_sha:=lower(rawtohex(dbms_crypto.hash(l_canonical,
        dbms_crypto.hash_sh256)));
    exception when others then l_first:=null;l_last:=null;l_sha:=null;end;

    if l_first is not null then
      begin
        select response_blob into l_cached from step_responses
          where session_token=p_session and first_seq=l_first and last_seq=l_last
            and command_sha=l_sha;
        copy_blob(l_cached,p_payload);commit;return;
      exception when no_data_found then null;end;
    end if;

    doom_tic_tx.apply_batch(p_session,p_commands,l_internal);
    select state_sha into l_state_sha from step_responses
      where session_token=p_session and first_seq=l_first and last_seq=l_last;
    render_payload(p_session,l_state_sha,p_payload);
    l_response_text:=blob_text(utl_compress.lz_uncompress(p_payload));
    update step_responses set response_blob=p_payload,frame_sha=(
      select json_value(l_response_text,'$.frame_sha') from dual)
      where session_token=p_session and first_seq=l_first and last_seq=l_last;
    commit;
  exception when others then
    rollback;p_payload:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_bad_request,'step failed');
  end;

  procedure save_game(
    p_session in varchar2,p_slot in number,p_state_sha out varchar2
  ) is
  begin
    p_state_sha:=null;require_session(p_session);
    doom_history.save_game(p_session,p_slot,p_state_sha);commit;
  exception when others then
    rollback;p_state_sha:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_bad_request,'save failed');
  end;

  procedure load_game(
    p_session in varchar2,p_slot in number,p_payload out blob
  ) is
    l_internal blob;l_state_sha varchar2(64);
  begin
    p_payload:=null;require_session(p_session);
    doom_history.load_game(p_session,p_slot,l_internal);
    l_state_sha:=json_value(blob_text(l_internal),'$.state_sha');
    render_payload(p_session,l_state_sha,p_payload);commit;
  exception when others then
    rollback;p_payload:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_bad_request,'load failed');
  end;

  procedure start_replay(
    p_session in varchar2,p_from_tic in number,p_to_tic in number,
    p_replay_id out varchar2
  ) is
  begin
    p_replay_id:=null;require_session(p_session);
    doom_history.start_replay(p_session,p_from_tic,p_to_tic,p_replay_id);commit;
  exception when others then
    rollback;p_replay_id:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_bad_request,'replay start failed');
  end;

  procedure step_replay(p_replay_id in varchar2,p_payload out blob) is
    l_internal blob;l_session varchar2(32);l_state_sha varchar2(64);
  begin
    p_payload:=null;
    if p_replay_id is null or not regexp_like(p_replay_id,'^[0-9a-f]{32}$') then
      fail(c_bad_request,'unknown replay identifier');
    end if;
    select session_token into l_session from replay_cursors
      where replay_id=p_replay_id;
    require_session(l_session);
    doom_history.step_replay(p_replay_id,l_internal);
    l_state_sha:=json_value(blob_text(l_internal),'$.state_sha');
    render_payload(l_session,l_state_sha,p_payload);commit;
  exception when others then
    rollback;p_payload:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_bad_request,'replay step failed');
  end;

  procedure get_asset(
    p_asset_name in varchar2,p_payload out blob,p_media_type out varchar2
  ) is
    l_blob blob;
    l_hex clob;
  begin
    p_payload:=null;p_media_type:=null;
    if p_asset_name is null or p_asset_name not in
       ('PLAYPAL','GENMIDI','DSPISTOL') then
      fail(c_asset,'asset is not allowlisted');
    end if;
    if p_asset_name='PLAYPAL' then
      select xmlserialize(content xmlagg(xmlelement(e,
        lpad(to_char(red,'FMXX'),2,'0')||lpad(to_char(green,'FMXX'),2,'0')||
        lpad(to_char(blue,'FMXX'),2,'0')) order by palette_index)
        as clob no indent) into l_hex from doom_palette_texel;
      l_hex:=replace(replace(l_hex,'<E>',''),'</E>','');
      l_blob:=hex_blob(l_hex);
      p_media_type:='application/octet-stream';
    else
      select b.encoded_bytes into l_blob
        from doom_asset a join doom_asset_blob b on b.asset_id=a.asset_id
        where a.asset_name=p_asset_name
          and (p_asset_name<>'DSPISTOL' or a.asset_kind='sound');
      p_media_type:=case p_asset_name when 'DSPISTOL' then 'audio/x-doom'
        else 'application/octet-stream' end;
    end if;
    copy_blob(l_blob,p_payload);commit;
  exception when no_data_found then
    rollback;p_payload:=null;p_media_type:=null;
    raise_application_error(c_asset,'asset is not allowlisted');
  when others then
    rollback;p_payload:=null;p_media_type:=null;
    if sqlcode between -20999 and -20000 then raise;end if;
    raise_application_error(c_asset,'asset request failed');
  end;
end doom_api;
/
