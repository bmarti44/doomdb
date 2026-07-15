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

    -- Materialize the SQL-macro canvas once before downstream RLE and hash
    -- aggregation.  Besides avoiding duplicate renderer work, this keeps the
    -- macro at a top-level statement boundary required by Oracle's SQL-macro
    -- expansion rules.
    delete from frame_column;
    insert into frame_column(session_token,column_no)
      select p_session,level-1 from dual connect by level<=320;
    delete from frame_pixel where session_token=p_session;
    insert into frame_pixel(session_token,column_no,row_no,palette_index,
      layer_ordinal)
    select presentation.session_token,presentation.column_no,
      presentation.row_no,presentation.palette_index,presentation.layer_ordinal
    from doom_api_presentation_rows presentation
    join frame_column selected
      on selected.session_token=presentation.session_token
     and selected.column_no=presentation.column_no;

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

    select xmlserialize(content xmlagg(xmlelement(e,h) order by column_no,row_no)
      as clob no indent)
      into l_frame_hex
      from (
        select column_no,row_no,
          lpad(to_char(palette_index,'FMXX'),2,'0') h
        from frame_pixel where session_token=p_session
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
    l_response_text clob;
  begin
    p_payload:=null;require_session(p_session);
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
