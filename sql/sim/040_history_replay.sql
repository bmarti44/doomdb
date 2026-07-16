-- T6.4 deterministic persistence.  Durable history is append-only; restore
-- operations branch by lineage and only replace the live authoritative rows.
merge into doom_config d
using (select 'HISTORY_SNAPSHOT_INTERVAL' config_key,4 number_value from dual) s
on (d.config_key=s.config_key)
when matched then update set d.number_value=s.number_value,d.text_value=null
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,null);

-- The persistence schema is installed with the history feature, after the
-- earlier simulation phases.  Keeping these alterations here leaves the T6.1
-- and T6.2 bootstrap contract unchanged until ordered integration reaches T6.4.
alter table tic_commands add (
  lineage varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  previous_command_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  state_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  frame_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  state_blob blob default empty_blob() not null,
  constraint tic_commands_history_sha_ck check (
    regexp_like(previous_command_sha,'^[0-9a-f]{64}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$'))
);
alter table tic_commands drop constraint tic_commands_tic_uq;
alter table tic_commands add constraint tic_commands_tic_uq
  unique(session_token,lineage,tic,command_ordinal);

alter table game_events add (
  lineage varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  previous_event_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  event_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  constraint game_events_sha_ck check (
    regexp_like(previous_event_sha,'^[0-9a-f]{64}$') and
    regexp_like(event_sha,'^[0-9a-f]{64}$'))
);
alter table game_events drop constraint game_events_pk;
alter table game_events add constraint game_events_pk
  primary key(session_token,lineage,tic,event_ordinal);

alter table audio_events add (
  lineage varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  previous_event_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  event_sha varchar2(64) default '0000000000000000000000000000000000000000000000000000000000000000' not null,
  constraint audio_events_sha_ck check (
    regexp_like(previous_event_sha,'^[0-9a-f]{64}$') and
    regexp_like(event_sha,'^[0-9a-f]{64}$'))
);
alter table audio_events drop constraint audio_events_pk;
alter table audio_events add constraint audio_events_pk
  primary key(session_token,lineage,tic,event_ordinal);

alter table state_history drop constraint state_history_pk;
alter table state_history drop constraint state_history_range_ck;
alter table state_history add (
  lineage varchar2(64) not null,
  command_sha varchar2(64) not null,
  event_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  snapshot_sha varchar2(64) not null,
  snapshot_reason varchar2(24) not null,
  constraint state_history_pk primary key(session_token,lineage,tic),
  constraint state_history_range_ck check (
    tic>=0 and first_command_seq>=0 and last_command_seq>=first_command_seq-1),
  constraint state_history_reason_ck check (snapshot_reason in
    ('NEW_GAME','INTERVAL','SAVE','SAVE_INTERVAL','LOAD','REWIND')),
  constraint state_history_history_sha_ck check (
    regexp_like(command_sha,'^[0-9a-f]{64}$') and
    regexp_like(event_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$') and
    regexp_like(snapshot_sha,'^[0-9a-f]{64}$'))
);

alter table save_slots add (
  snapshot_sha varchar2(64) not null,
  constraint save_slots_snapshot_sha_ck check (regexp_like(snapshot_sha,'^[0-9a-f]{64}$'))
);

create table replay_cursors (
  replay_id varchar2(32) not null,
  session_token varchar2(32) not null,
  lineage varchar2(64) not null,
  from_tic number(12) not null,
  current_tic number(12) not null,
  to_tic number(12) not null,
  command_sha varchar2(64) not null,
  event_sha varchar2(64) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  state_blob blob not null,
  completed number(1) not null,
  constraint replay_cursors_pk primary key(replay_id),
  constraint replay_cursors_session_fk foreign key(session_token)
    references game_sessions(session_token) on delete cascade,
  constraint replay_cursors_range_ck check (
    from_tic>=0 and current_tic between from_tic and to_tic and to_tic>=from_tic),
  constraint replay_cursors_done_ck check (completed in(0,1)),
  constraint replay_cursors_identity_ck check (regexp_like(replay_id,'^[0-9a-f]{32}$')),
  constraint replay_cursors_sha_ck check (
    regexp_like(command_sha,'^[0-9a-f]{64}$') and
    regexp_like(event_sha,'^[0-9a-f]{64}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$'))
);

create table history_heads (
  session_token varchar2(32) not null,
  lineage varchar2(64) not null,
  command_sha varchar2(64) not null,
  event_sha varchar2(64) not null,
  constraint history_heads_pk primary key(session_token,lineage),
  constraint history_heads_session_fk foreign key(session_token)
    references game_sessions(session_token) on delete cascade,
  constraint history_heads_sha_ck check (
    regexp_like(command_sha,'^[0-9a-f]{64}$') and
    regexp_like(event_sha,'^[0-9a-f]{64}$'))
);

create or replace trigger doom_game_events_bir
before insert on game_events for each row
declare
  l_document clob;
begin
  select save_lineage into :new.lineage from game_sessions
    where session_token=:new.session_token;
  merge into history_heads d using(select :new.session_token session_token,
    :new.lineage lineage from dual) s
  on(d.session_token=s.session_token and d.lineage=s.lineage)
  when not matched then insert(session_token,lineage,command_sha,event_sha)
    values(s.session_token,s.lineage,
      '0000000000000000000000000000000000000000000000000000000000000000',
      '0000000000000000000000000000000000000000000000000000000000000000');
  select event_sha into :new.previous_event_sha from history_heads
    where session_token=:new.session_token and lineage=:new.lineage for update;
  select json_object('lineage' value :new.lineage,'tic' value :new.tic,
    'ordinal' value :new.event_ordinal,'type' value :new.event_type,
    'actor' value :new.actor_mobj_id,'target' value :new.target_mobj_id,
    'number' value :new.number_value,'text' value :new.text_value,
    'previous_event_sha' value :new.previous_event_sha returning clob)
    into l_document from dual;
  :new.event_sha:=lower(rawtohex(dbms_crypto.hash(l_document,dbms_crypto.hash_sh256)));
  update history_heads set event_sha=:new.event_sha
    where session_token=:new.session_token and lineage=:new.lineage;
end;
/

create or replace trigger doom_audio_events_bir
before insert on audio_events for each row
declare
  l_document clob;
begin
  select save_lineage into :new.lineage from game_sessions
    where session_token=:new.session_token;
  merge into history_heads d using(select :new.session_token session_token,
    :new.lineage lineage from dual) s
  on(d.session_token=s.session_token and d.lineage=s.lineage)
  when not matched then insert(session_token,lineage,command_sha,event_sha)
    values(s.session_token,s.lineage,
      '0000000000000000000000000000000000000000000000000000000000000000',
      '0000000000000000000000000000000000000000000000000000000000000000');
  select event_sha into :new.previous_event_sha from history_heads
    where session_token=:new.session_token and lineage=:new.lineage for update;
  select json_object('lineage' value :new.lineage,'tic' value :new.tic,
    'ordinal' value :new.event_ordinal,'asset_kind' value :new.asset_kind,
    'asset_name' value :new.asset_name,
    'volume' value :new.volume,'separation' value :new.separation,
    'previous_event_sha' value :new.previous_event_sha returning clob)
    into l_document from dual;
  :new.event_sha:=lower(rawtohex(dbms_crypto.hash(l_document,dbms_crypto.hash_sh256)));
  update history_heads set event_sha=:new.event_sha
    where session_token=:new.session_token and lineage=:new.lineage;
end;
/

create or replace package doom_history authid definer as
  procedure capture_tic(
    p_session in varchar2,
    p_tic in number,
    p_state_document in clob,
    p_state_sha in varchar2,
    p_frame_sha in varchar2
  );
  procedure save_game(p_session in varchar2,p_slot in number,p_state_sha out varchar2);
  procedure load_game(p_session in varchar2,p_slot in number,p_payload out blob);
  procedure rewind_to_tic(p_session in varchar2,p_tic in number,p_payload out blob);
  procedure start_replay(
    p_session in varchar2,p_from_tic in number,p_to_tic in number,
    p_replay_id out varchar2
  );
  procedure step_replay(p_replay_id in varchar2,p_payload out blob);
end doom_history;
/

create or replace package body doom_history as
  c_bad_history constant pls_integer := -20891;
  c_bad_slot constant pls_integer := -20892;
  c_missing_save constant pls_integer := -20893;
  c_bad_range constant pls_integer := -20894;
  c_missing_replay constant pls_integer := -20895;
  c_zero_sha constant varchar2(64) := rpad('0',64,'0');
  history_snapshot_interval constant pls_integer := 4;

  procedure fail(p_code pls_integer,p_message varchar2) is
  begin
    raise_application_error(p_code,p_message);
  end;

  function sha256(p_document clob) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.hash(p_document,dbms_crypto.hash_sh256)));
  end;

  function sha256(p_document blob) return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.hash(p_document,dbms_crypto.hash_sh256)));
  end;

  function utf8_blob(p_document clob) return blob is
    l_blob blob;l_dest integer:=1;l_src integer:=1;l_context integer:=0;l_warning integer;
  begin
    dbms_lob.createtemporary(l_blob,true,dbms_lob.call);
    dbms_lob.converttoblob(l_blob,p_document,dbms_lob.lobmaxsize,l_dest,l_src,
      nls_charset_id('AL32UTF8'),l_context,l_warning);
    if l_warning<>0 then fail(c_bad_history,'UTF-8 history conversion failed');end if;
    return l_blob;
  end;

  function blob_text(p_blob blob) return clob is
    l_clob clob;l_dest integer:=1;l_src integer:=1;l_context integer:=0;l_warning integer;
  begin
    dbms_lob.createtemporary(l_clob,true,dbms_lob.call);
    dbms_lob.converttoclob(l_clob,p_blob,dbms_lob.lobmaxsize,l_dest,l_src,
      nls_charset_id('AL32UTF8'),l_context,l_warning);
    if l_warning<>0 then fail(c_bad_history,'UTF-8 snapshot conversion failed');end if;
    return l_clob;
  end;

  function logical_state_document(p_session varchar2) return clob is
    l_document clob;
  begin
    select json_object(
      'schema' value 1,'skill' value s.skill,
      'current_player_id' value s.current_player_id,'tic' value s.current_tic,
      'rng_cursor' value s.rng_cursor,'game_mode' value s.game_mode,
      'map_status' value s.map_status,'paused' value s.paused,
      'menu_state' value s.menu_state,'automap_state' value s.automap_state,
      'player' value (select json_object(
        'player_id' value p.player_id,'x' value p.x,'y' value p.y,'z' value p.z,
        'momentum_x' value p.momentum_x,'momentum_y' value p.momentum_y,
        'momentum_z' value p.momentum_z,'angle' value p.angle,
        'view_height' value p.view_height,'view_bob' value p.view_bob,
        'health' value p.health,'armor' value p.armor,'armor_type' value p.armor_type,
        'blue_key' value p.blue_key,'yellow_key' value p.yellow_key,'red_key' value p.red_key,
        'ammo_bullets' value p.ammo_bullets,'ammo_shells' value p.ammo_shells,
        'ammo_rockets' value p.ammo_rockets,'ammo_cells' value p.ammo_cells,
        'weapon_mask' value p.weapon_mask,'selected_weapon' value p.selected_weapon,
        'pending_weapon' value p.pending_weapon,'weapon_state' value p.weapon_state,
        'weapon_state_tics' value p.weapon_state_tics,
        'flash_state' value p.flash_state,'flash_state_tics' value p.flash_state_tics,
        'refire' value p.refire,'backpack' value p.backpack,
        'power_berserk' value p.power_berserk,
        'power_invulnerability' value p.power_invulnerability,
        'power_invisibility' value p.power_invisibility,
        'power_ironfeet' value p.power_ironfeet,'power_lightamp' value p.power_lightamp,
        'kill_count' value p.kill_count,'item_count' value p.item_count,
        'secret_count' value p.secret_count,'alive' value p.alive,
        'noclip' value p.noclip returning clob)
        from players p where p.session_token=s.session_token
          and p.player_id=s.current_player_id) format json,
      'mobjs' value coalesce((select json_arrayagg(json_object(
        'mobj_id' value mobj_id,'thing_type' value thing_type,'state_id' value state_id,
        'state_tics' value state_tics,'x' value x,'y' value y,'z' value z,
        'momentum_x' value momentum_x,'momentum_y' value momentum_y,
        'momentum_z' value momentum_z,'angle' value angle,'radius' value radius,
        'height' value height,'health' value health,'flags' value flags,
        'target_mobj_id' value target_mobj_id,'tracer_mobj_id' value tracer_mobj_id,
        'reaction_time' value reaction_time,'spawn_thing_id' value spawn_thing_id,
        'owner_mobj_id' value owner_mobj_id,
        'projectile_kind' value projectile_kind,'exploded' value exploded,
        'sector_id' value sector_id,'move_direction' value move_direction,
        'awake' value awake,'attack_cooldown' value attack_cooldown,
        'monster_health_seen' value monster_health_seen,
        'death_processed' value death_processed
        returning clob) order by mobj_id returning clob)
        from mobjs where session_token=s.session_token),to_clob('[]')) format json,
      'sectors' value coalesce((select json_arrayagg(json_object(
        'sector_id' value sector_id,'floor_height' value floor_height,
        'ceiling_height' value ceiling_height,'light_level' value light_level,
        'light_timer' value light_timer,'secret_found' value secret_found,
        'damage_clock' value damage_clock returning clob)
        order by sector_id returning clob) from sector_state
        where session_token=s.session_token),to_clob('[]')) format json,
      'lines' value coalesce((select json_arrayagg(json_object(
        'linedef_id' value linedef_id,'trigger_count' value trigger_count,
        'switch_on' value switch_on returning clob) order by linedef_id returning clob)
        from line_state where session_token=s.session_token),to_clob('[]')) format json,
      'movers' value coalesce((select json_arrayagg(json_object(
        'mover_id' value mover_id,'sector_id' value sector_id,'plane' value plane,
        'direction' value direction,'speed' value speed,'target_height' value target_height,
        'wait_tics' value wait_tics,'timer_tics' value timer_tics,
        'mover_kind' value mover_kind,'origin_height' value origin_height,
        'source_linedef_id' value source_linedef_id returning clob)
        order by mover_id returning clob) from active_movers
        where session_token=s.session_token),to_clob('[]')) format json,
      'switches' value coalesce((select json_arrayagg(json_object(
        'linedef_id' value linedef_id,'timer_tics' value timer_tics,
        'restore_texture' value restore_texture returning clob)
        order by linedef_id returning clob) from active_switches
        where session_token=s.session_token),to_clob('[]')) format json,
      'ordering_version' value 'APPENDIX-F-1' returning clob)
    into l_document from game_sessions s where s.session_token=p_session;
    return l_document;
  exception when no_data_found then fail(c_bad_history,'unknown session');return null;
  end;

  function command_hash(
    p_seq number,p_lineage varchar2,p_tic number,p_ordinal number,
    p_turn number,p_forward number,p_strafe number,p_run number,p_fire number,
    p_use number,p_weapon number,p_pause number,p_automap number,
    p_menu varchar2,p_cheat varchar2,p_previous varchar2
  ) return varchar2 is l_document clob;
  begin
    select json_object('seq' value p_seq,'lineage' value p_lineage,'tic' value p_tic,
      'ordinal' value p_ordinal,'turn' value p_turn,'forward' value p_forward,
      'strafe' value p_strafe,'run' value p_run,'fire' value p_fire,
      'use' value p_use,'weapon' value p_weapon,'pause' value p_pause,
      'automap' value p_automap,'menu' value p_menu,
      'cheat' value coalesce(p_cheat,''),'previous_command_sha' value p_previous
      returning clob) into l_document from dual;
    return sha256(l_document);
  end;

  function event_hash(
    p_lineage varchar2,p_tic number,p_ordinal number,p_type varchar2,
    p_actor number,p_target number,p_number number,p_text varchar2,p_previous varchar2
  ) return varchar2 is l_document clob;
  begin
    select json_object('lineage' value p_lineage,'tic' value p_tic,
      'ordinal' value p_ordinal,'type' value p_type,'actor' value p_actor,
      'target' value p_target,'number' value p_number,'text' value p_text,
      'previous_event_sha' value p_previous returning clob)
      into l_document from dual;
    return sha256(l_document);
  end;

  function audio_event_hash(
    p_lineage varchar2,p_tic number,p_ordinal number,p_asset_kind varchar2,
    p_asset_name varchar2,
    p_volume number,p_separation number,p_previous varchar2
  ) return varchar2 is l_document clob;
  begin
    select json_object('lineage' value p_lineage,'tic' value p_tic,
      'ordinal' value p_ordinal,'asset_kind' value p_asset_kind,
      'asset_name' value p_asset_name,'volume' value p_volume,
      'separation' value p_separation,'previous_event_sha' value p_previous
      returning clob) into l_document from dual;
    return sha256(l_document);
  end;

  function snapshot_document(
    p_session varchar2,p_lineage varchar2,p_frontier number,
    p_command_sha varchar2,p_event_sha varchar2,p_state_sha varchar2,
    p_frame_sha varchar2,p_state clob
  ) return clob is l_document clob;
  begin
    select json_object('schema' value 1,'lineage' value p_lineage,
      'frontier' value p_frontier,'command_sha' value p_command_sha,
      'event_sha' value p_event_sha,'state_sha' value p_state_sha,
      'frame_sha' value p_frame_sha,'state' value p_state format json returning clob)
      into l_document from dual;
    return l_document;
  end;

  procedure heads(
    p_session varchar2,p_lineage varchar2,p_tic number,
    p_command_sha out varchar2,p_event_sha out varchar2,p_frame_sha out varchar2
  ) is
  begin
    begin select command_sha,frame_sha into p_command_sha,p_frame_sha from (
      select command_sha,frame_sha from tic_commands where session_token=p_session
       and lineage=p_lineage and tic<=p_tic order by tic desc,command_ordinal desc,
       command_seq desc) where rownum=1;
    exception when no_data_found then p_command_sha:=c_zero_sha;p_frame_sha:=c_zero_sha;end;
    begin select event_sha into p_event_sha from (
      select event_sha from (
        select tic,event_ordinal,0 event_kind,event_sha from game_events
          where session_token=p_session and lineage=p_lineage and tic<=p_tic
        union all
        select tic,event_ordinal,1,event_sha from audio_events
          where session_token=p_session and lineage=p_lineage and tic<=p_tic)
      order by tic desc,event_kind desc,event_ordinal desc) where rownum=1;
    exception when no_data_found then p_event_sha:=c_zero_sha;end;
  end;

  procedure persist_snapshot(
    p_session varchar2,p_lineage varchar2,p_tic number,p_reason varchar2,
    p_state clob,p_state_sha varchar2,p_frame_sha varchar2
  ) is
    l_frontier number;l_first number;l_command_sha varchar2(64);
    l_event_sha varchar2(64);l_unused varchar2(64);l_document clob;l_blob blob;l_sha varchar2(64);
  begin
    select last_command_seq into l_frontier from game_sessions
      where session_token=p_session for update;
    heads(p_session,p_lineage,p_tic,l_command_sha,l_event_sha,l_unused);
    select coalesce(min(command_seq),l_frontier+1) into l_first from tic_commands
      where session_token=p_session and lineage=p_lineage;
    l_document:=snapshot_document(p_session,p_lineage,l_frontier,l_command_sha,
      l_event_sha,p_state_sha,p_frame_sha,p_state);
    l_blob:=utf8_blob(l_document);l_sha:=sha256(l_blob);
    insert into state_history(session_token,lineage,tic,first_command_seq,
      last_command_seq,state_sha,command_sha,event_sha,frame_sha,snapshot_sha,
      snapshot_reason,snapshot_blob)
    values(p_session,p_lineage,p_tic,l_first,l_frontier,p_state_sha,l_command_sha,
      l_event_sha,p_frame_sha,l_sha,p_reason,l_blob);
  exception when dup_val_on_index then null;
  end;

  procedure verify_snapshot(
    p_blob blob,p_lineage varchar2,p_frontier number,p_state_sha varchar2,
    p_command_sha varchar2,p_event_sha varchar2,p_frame_sha varchar2,
    p_snapshot_sha varchar2,p_state out clob
  ) is l_document clob;l_embedded clob;
  begin
    if sha256(p_blob)<>p_snapshot_sha then fail(c_bad_history,'snapshot blob hash mismatch');end if;
    l_document:=blob_text(p_blob);
    if json_value(l_document,'$.schema' returning number)<>1
       or json_value(l_document,'$.lineage')<>p_lineage
       or json_value(l_document,'$.frontier' returning number)<>p_frontier
       or json_value(l_document,'$.state_sha')<>p_state_sha
       or json_value(l_document,'$.command_sha')<>p_command_sha
       or json_value(l_document,'$.event_sha')<>p_event_sha
       or json_value(l_document,'$.frame_sha')<>p_frame_sha then
      fail(c_bad_history,'snapshot envelope mismatch');
    end if;
    select state_doc into l_embedded from json_table(l_document,'$' columns(
      state_doc clob format json path '$.state' error on error));
    if sha256(l_embedded)<>p_state_sha then fail(c_bad_history,'snapshot state hash mismatch');end if;
    p_state:=l_embedded;
  exception when others then
    if sqlcode=c_bad_history then raise;end if;
    fail(c_bad_history,'invalid snapshot envelope');
  end;

  procedure reconstruct(
    p_session varchar2,p_lineage varchar2,p_target_tic number,
    p_state out clob,p_state_sha out varchar2,p_frame_sha out varchar2,
    p_command_sha out varchar2,p_event_sha out varchar2
  ) is
    l_tic number;l_frontier number;l_blob blob;l_snapshot_sha varchar2(64);
    l_expected varchar2(64);l_count number;l_last_tic number;
  begin
    -- Greatest trusted snapshot no later than the requested logical tic.
    select tic,last_command_seq,state_sha,command_sha,event_sha,frame_sha,
           snapshot_sha,snapshot_blob
      into l_tic,l_frontier,p_state_sha,p_command_sha,p_event_sha,p_frame_sha,
           l_snapshot_sha,l_blob
      from (select * from state_history where session_token=p_session
             and lineage=p_lineage and tic<=p_target_tic order by tic desc)
     where rownum=1;
    verify_snapshot(l_blob,p_lineage,l_frontier,p_state_sha,p_command_sha,
      p_event_sha,p_frame_sha,l_snapshot_sha,p_state);

    l_last_tic:=l_tic;l_count:=0;
    for c in (select * from tic_commands where session_token=p_session
      and lineage=p_lineage and tic>l_tic and tic<=p_target_tic
      order by tic,command_ordinal,command_seq) loop
      if c.tic<>l_last_tic+1 or c.command_ordinal<>0
         or c.previous_command_sha<>p_command_sha then
        fail(c_bad_history,'command range or predecessor mismatch');
      end if;
      l_expected:=command_hash(c.command_seq,c.lineage,c.tic,c.command_ordinal,
        c.turn,c.forward_move,c.strafe,c.run,c.fire,c.use_action,c.weapon_slot,
        c.pause_toggle,c.automap_toggle,c.menu_action,c.cheat_code,
        c.previous_command_sha);
      if l_expected<>c.command_sha or sha256(blob_text(c.state_blob))<>c.state_sha then
        fail(c_bad_history,'command or state hash mismatch');
      end if;
      p_state:=blob_text(c.state_blob);p_state_sha:=c.state_sha;
      p_frame_sha:=c.frame_sha;p_command_sha:=c.command_sha;
      l_last_tic:=c.tic;l_count:=l_count+1;
    end loop;
    if l_last_tic<>p_target_tic then fail(c_bad_history,'command range incomplete');end if;

    for e in (select * from (
      select tic,event_ordinal,0 event_kind,lineage,event_type,actor_mobj_id,
        target_mobj_id,number_value,text_value,cast(null as varchar2(20)) asset_kind,
        cast(null as varchar2(32)) asset_name,
        cast(null as number) volume,cast(null as number) separation,
        previous_event_sha,event_sha from game_events where session_token=p_session
          and lineage=p_lineage and tic>l_tic and tic<=p_target_tic
      union all
      select tic,event_ordinal,1,lineage,cast(null as varchar2(32)),cast(null as number),
        cast(null as number),cast(null as number),cast(null as varchar2(4000)),asset_kind,
        asset_name,
        volume,separation,previous_event_sha,event_sha from audio_events
        where session_token=p_session and lineage=p_lineage and tic>l_tic
          and tic<=p_target_tic)
      order by tic,event_kind,event_ordinal) loop
      if e.event_kind=0 then
        l_expected:=event_hash(e.lineage,e.tic,e.event_ordinal,e.event_type,
          e.actor_mobj_id,e.target_mobj_id,e.number_value,e.text_value,
          e.previous_event_sha);
      else
        l_expected:=audio_event_hash(e.lineage,e.tic,e.event_ordinal,e.asset_kind,e.asset_name,
          e.volume,e.separation,e.previous_event_sha);
      end if;
      if e.previous_event_sha<>p_event_sha or e.event_sha<>l_expected then
        fail(c_bad_history,'event predecessor or hash mismatch');
      end if;
      p_event_sha:=e.event_sha;
    end loop;
  exception when no_data_found then fail(c_bad_history,'no trusted snapshot');
  end;

  procedure restore_state(p_session varchar2,p_state clob) is
  begin
    update game_sessions set current_player_id=null where session_token=p_session;
    delete from active_switches where session_token=p_session;
    delete from active_movers where session_token=p_session;
    delete from line_state where session_token=p_session;
    delete from sector_state where session_token=p_session;
    delete from mobjs where session_token=p_session;
    delete from players where session_token=p_session;

    update game_sessions s set (skill,current_tic,rng_cursor,game_mode,map_status,
      paused,menu_state,automap_state)=(select skill,tic,rng,mode_name,map_name,
      paused,menu_name,automap from json_table(p_state,'$' columns(
        skill number path '$.skill',tic number path '$.tic',rng number path '$.rng_cursor',
        mode_name varchar2(16) path '$.game_mode',map_name varchar2(16) path '$.map_status',
        paused number path '$.paused',menu_name varchar2(32) path '$.menu_state',
        automap varchar2(16) path '$.automap_state')))
      where s.session_token=p_session;
    insert into players select p_session,j.* from json_table(p_state,'$.player' columns(
      player_id number path '$.player_id',x number path '$.x',y number path '$.y',z number path '$.z',
      momentum_x number path '$.momentum_x',momentum_y number path '$.momentum_y',momentum_z number path '$.momentum_z',
      angle number path '$.angle',view_height number path '$.view_height',view_bob number path '$.view_bob',
      health number path '$.health',armor number path '$.armor',armor_type number path '$.armor_type',
      blue_key number path '$.blue_key',yellow_key number path '$.yellow_key',red_key number path '$.red_key',
      ammo_bullets number path '$.ammo_bullets',ammo_shells number path '$.ammo_shells',ammo_rockets number path '$.ammo_rockets',ammo_cells number path '$.ammo_cells',
      weapon_mask number path '$.weapon_mask',selected_weapon varchar2(32) path '$.selected_weapon',
      power_invulnerability number path '$.power_invulnerability',power_invisibility number path '$.power_invisibility',
      power_ironfeet number path '$.power_ironfeet',power_lightamp number path '$.power_lightamp',
      kill_count number path '$.kill_count',item_count number path '$.item_count',secret_count number path '$.secret_count',alive number path '$.alive',
      noclip number path '$.noclip',pending_weapon varchar2(32) path '$.pending_weapon',
      weapon_state varchar2(64) path '$.weapon_state',weapon_state_tics number path '$.weapon_state_tics',
      flash_state varchar2(64) path '$.flash_state',flash_state_tics number path '$.flash_state_tics',
      refire number path '$.refire',backpack number path '$.backpack',power_berserk number path '$.power_berserk')) j;
    insert into mobjs select p_session,j.* from json_table(p_state,'$.mobjs[*]' columns(
      mobj_id number path '$.mobj_id',thing_type number path '$.thing_type',state_id varchar2(64) path '$.state_id',state_tics number path '$.state_tics',
      x number path '$.x',y number path '$.y',z number path '$.z',momentum_x number path '$.momentum_x',momentum_y number path '$.momentum_y',momentum_z number path '$.momentum_z',
      angle number path '$.angle',radius number path '$.radius',height number path '$.height',health number path '$.health',flags number path '$.flags',
      target_mobj_id number path '$.target_mobj_id',tracer_mobj_id number path '$.tracer_mobj_id',reaction_time number path '$.reaction_time',spawn_thing_id number path '$.spawn_thing_id',
      owner_mobj_id number path '$.owner_mobj_id',projectile_kind varchar2(32) path '$.projectile_kind',exploded number path '$.exploded',
      sector_id number path '$.sector_id',move_direction number path '$.move_direction',awake number path '$.awake',
      attack_cooldown number path '$.attack_cooldown',monster_health_seen number path '$.monster_health_seen',death_processed number path '$.death_processed')) j;
    insert into sector_state select p_session,j.* from json_table(p_state,'$.sectors[*]' columns(
      sector_id number path '$.sector_id',floor_height number path '$.floor_height',ceiling_height number path '$.ceiling_height',
      light_level number path '$.light_level',light_timer number path '$.light_timer',
      secret_found number path '$.secret_found',damage_clock number path '$.damage_clock')) j;
    insert into line_state select p_session,j.* from json_table(p_state,'$.lines[*]' columns(
      linedef_id number path '$.linedef_id',trigger_count number path '$.trigger_count',switch_on number path '$.switch_on')) j;
    insert into active_movers select p_session,j.* from json_table(p_state,'$.movers[*]' columns(
      mover_id number path '$.mover_id',sector_id number path '$.sector_id',plane varchar2(8) path '$.plane',direction number path '$.direction',speed number path '$.speed',
      target_height number path '$.target_height',wait_tics number path '$.wait_tics',timer_tics number path '$.timer_tics',mover_kind varchar2(24) path '$.mover_kind',
      origin_height number path '$.origin_height',source_linedef_id number path '$.source_linedef_id')) j;
    insert into active_switches select p_session,j.* from json_table(p_state,'$.switches[*]' columns(
      linedef_id number path '$.linedef_id',timer_tics number path '$.timer_tics',restore_texture varchar2(32) path '$.restore_texture')) j;
    update game_sessions set current_player_id=json_value(p_state,'$.current_player_id' returning number)
      where session_token=p_session;
  end;

  procedure response_blob(p_tic number,p_state_sha varchar2,p_frame_sha varchar2,p_payload out blob) is
    l_json clob;
  begin
    select json_object('v' value 1,'tic' value p_tic,'state_sha' value p_state_sha,
      'frame_sha' value p_frame_sha returning clob) into l_json from dual;
    p_payload:=utf8_blob(l_json);
  end;

  procedure capture_tic(
    p_session in varchar2,p_tic in number,p_state_document in clob,
    p_state_sha in varchar2,p_frame_sha in varchar2
  ) is
    l_lineage varchar2(64);l_current number;l_interval number;
    l_command_sha varchar2(64);l_event_sha varchar2(64);l_unused varchar2(64);
  begin
    select save_lineage,current_tic into l_lineage,l_current from game_sessions
      where session_token=p_session for update;
    if p_tic<>l_current or sha256(p_state_document)<>p_state_sha then
      fail(c_bad_history,'capture state mismatch');
    end if;
    heads(p_session,l_lineage,p_tic,l_command_sha,l_event_sha,l_unused);
    if l_command_sha=c_zero_sha then fail(c_bad_history,'captured tic has no command');end if;
    select number_value into l_interval from doom_config
      where config_key='HISTORY_SNAPSHOT_INTERVAL';
    if not regexp_like(l_lineage,'^[0-9a-f]{64}$') then
      persist_snapshot(p_session,l_lineage,p_tic,'INTERVAL',p_state_document,
        p_state_sha,p_frame_sha);
    elsif mod(p_tic,history_snapshot_interval)=0 or mod(p_tic,l_interval)=0 then
      persist_snapshot(p_session,l_lineage,p_tic,'INTERVAL',p_state_document,
        p_state_sha,p_frame_sha);
    end if;
  end;

  procedure save_game(p_session in varchar2,p_slot in number,p_state_sha out varchar2) is
    l_lineage varchar2(64);l_tic number;l_state clob;l_frame_sha varchar2(64);
    l_command_sha varchar2(64);l_event_sha varchar2(64);l_blob blob;l_snapshot_sha varchar2(64);
  begin
    if p_slot is null or p_slot<>trunc(p_slot) or p_slot not between 0 and 99 then
      fail(c_bad_slot,'save slot must be an integer from 0 through 99');
    end if;
    select save_lineage,current_tic into l_lineage,l_tic from game_sessions
      where session_token=p_session for update;
    l_state:=logical_state_document(p_session);p_state_sha:=sha256(l_state);
    heads(p_session,l_lineage,l_tic,l_command_sha,l_event_sha,l_frame_sha);
    if l_frame_sha=c_zero_sha then l_frame_sha:=p_state_sha;end if;
    persist_snapshot(p_session,l_lineage,l_tic,'SAVE',l_state,p_state_sha,l_frame_sha);
    select snapshot_blob,snapshot_sha into l_blob,l_snapshot_sha from state_history
      where session_token=p_session and lineage=l_lineage and tic=l_tic;
    merge into save_slots d using(select p_session session_token,p_slot slot_number from dual) s
    on(d.session_token=s.session_token and d.slot_number=s.slot_number)
    when matched then update set d.saved_tic=l_tic,d.lineage=l_lineage,
      d.state_sha=p_state_sha,d.snapshot_blob=l_blob,d.snapshot_sha=l_snapshot_sha
    when not matched then insert(session_token,slot_number,saved_tic,lineage,state_sha,
      snapshot_blob,snapshot_sha) values(p_session,p_slot,l_tic,l_lineage,p_state_sha,
      l_blob,l_snapshot_sha);
  exception when no_data_found then fail(c_bad_history,'unknown session');
  end;

  procedure branch_to(
    p_session varchar2,p_state clob,p_state_sha varchar2,p_frame_sha varchar2,
    p_command_sha varchar2,p_event_sha varchar2,p_label varchar2,p_payload out blob
  ) is
    l_old varchar2(64);l_new varchar2(64);l_frontier number;l_tic number;
    l_document clob;l_blob blob;l_snapshot_sha varchar2(64);l_reason varchar2(24);
  begin
    select save_lineage,last_command_seq into l_old,l_frontier from game_sessions
      where session_token=p_session for update;
    l_tic:=json_value(p_state,'$.tic' returning number);
    select lower(standard_hash(p_label||'|'||l_old||'|'||to_char(l_frontier+1,'TM9',
      'NLS_NUMERIC_CHARACTERS=''.,''')||'|'||p_state_sha,'SHA256')) into l_new from dual;
    restore_state(p_session,p_state);
    update game_sessions set save_lineage=l_new where session_token=p_session;
    l_reason:=case when substr(p_label,1,4)='LOAD' then 'LOAD' else 'REWIND' end;
    l_document:=snapshot_document(p_session,l_new,l_frontier,p_command_sha,
      p_event_sha,p_state_sha,p_frame_sha,p_state);
    l_blob:=utf8_blob(l_document);l_snapshot_sha:=sha256(l_blob);
    insert into state_history(session_token,lineage,tic,first_command_seq,
      last_command_seq,state_sha,command_sha,event_sha,frame_sha,snapshot_sha,
      snapshot_reason,snapshot_blob)
    values(p_session,l_new,l_tic,l_frontier+1,l_frontier,p_state_sha,p_command_sha,
      p_event_sha,p_frame_sha,l_snapshot_sha,l_reason,l_blob);
    merge into history_heads d using(select p_session session_token,l_new lineage from dual) s
    on(d.session_token=s.session_token and d.lineage=s.lineage)
    when matched then update set d.command_sha=p_command_sha,d.event_sha=p_event_sha
    when not matched then insert(session_token,lineage,command_sha,event_sha)
      values(s.session_token,s.lineage,p_command_sha,p_event_sha);
    response_blob(l_tic,p_state_sha,p_frame_sha,p_payload);
  end;

  procedure load_game(p_session in varchar2,p_slot in number,p_payload out blob) is
    l_lineage varchar2(64);l_tic number;l_state_sha varchar2(64);
    l_command_sha varchar2(64);l_event_sha varchar2(64);l_frame_sha varchar2(64);
    l_snapshot_sha varchar2(64);l_blob blob;l_state clob;l_frontier number;
  begin
    if p_slot is null or p_slot<>trunc(p_slot) or p_slot not between 0 and 99 then
      fail(c_bad_slot,'load slot must be an integer from 0 through 99');
    end if;
    select lineage,saved_tic,state_sha,snapshot_blob,snapshot_sha
      into l_lineage,l_tic,l_state_sha,l_blob,l_snapshot_sha from save_slots
      where session_token=p_session and slot_number=p_slot;
    select last_command_seq,command_sha,event_sha,frame_sha into l_frontier,
      l_command_sha,l_event_sha,l_frame_sha from state_history where
      session_token=p_session and lineage=l_lineage and tic=l_tic;
    verify_snapshot(l_blob,l_lineage,l_frontier,l_state_sha,l_command_sha,
      l_event_sha,l_frame_sha,l_snapshot_sha,l_state);
    branch_to(p_session,l_state,l_state_sha,l_frame_sha,l_command_sha,l_event_sha,
      'LOAD:'||to_char(p_slot,'TM9'),p_payload);
  exception when no_data_found then fail(c_missing_save,'save slot not found');
  end;

  procedure rewind_to_tic(p_session in varchar2,p_tic in number,p_payload out blob) is
    l_lineage varchar2(64);l_state clob;l_state_sha varchar2(64);l_frame_sha varchar2(64);
    l_command_sha varchar2(64);l_event_sha varchar2(64);l_current number;
  begin
    if p_tic is null or p_tic<>trunc(p_tic) or p_tic<0 then
      fail(c_bad_range,'rewind tic must be a nonnegative integer');
    end if;
    select save_lineage,current_tic into l_lineage,l_current from game_sessions
      where session_token=p_session for update;
    if p_tic>l_current then fail(c_bad_range,'rewind beyond current tic');end if;
    reconstruct(p_session,l_lineage,p_tic,l_state,l_state_sha,l_frame_sha,
      l_command_sha,l_event_sha);
    branch_to(p_session,l_state,l_state_sha,l_frame_sha,l_command_sha,l_event_sha,
      'REWIND:'||to_char(p_tic,'TM9'),p_payload);
  exception when no_data_found then fail(c_bad_history,'unknown session');
  end;

  procedure start_replay(
    p_session in varchar2,p_from_tic in number,p_to_tic in number,
    p_replay_id out varchar2
  ) is
    l_lineage varchar2(64);l_state clob;l_state_blob blob;l_state_sha varchar2(64);
    l_frame_sha varchar2(64);l_command_sha varchar2(64);l_event_sha varchar2(64);
    l_count number;l_seed varchar2(4000);
  begin
    if p_from_tic is null or p_to_tic is null or p_from_tic<>trunc(p_from_tic)
       or p_to_tic<>trunc(p_to_tic) or p_from_tic<0 or p_to_tic<p_from_tic then
      fail(c_bad_range,'invalid replay range');
    end if;
    select save_lineage into l_lineage from game_sessions
      where session_token=p_session for update;
    reconstruct(p_session,l_lineage,p_from_tic,l_state,l_state_sha,l_frame_sha,
      l_command_sha,l_event_sha);
    select count(*) into l_count from tic_commands where session_token=p_session
      and lineage=l_lineage and tic>p_from_tic and tic<=p_to_tic;
    if l_count<>p_to_tic-p_from_tic then fail(c_bad_range,'incomplete replay range');end if;
    select 'REPLAY|'||p_session||'|'||l_lineage||'|'||to_char(p_from_tic,'TM9')||
      '|'||to_char(p_to_tic,'TM9')||'|'||to_char(count(*)+1,'TM9')
      into l_seed from replay_cursors;
    select lower(substr(standard_hash(l_seed,'SHA256'),1,32)) into p_replay_id from dual;
    l_state_blob:=utf8_blob(l_state);
    insert into replay_cursors(replay_id,session_token,lineage,from_tic,current_tic,
      to_tic,command_sha,event_sha,state_sha,frame_sha,state_blob,completed)
    values(p_replay_id,p_session,l_lineage,p_from_tic,p_from_tic,p_to_tic,
      l_command_sha,l_event_sha,l_state_sha,l_frame_sha,l_state_blob,
      case when p_from_tic=p_to_tic then 1 else 0 end);
  exception when no_data_found then fail(c_bad_history,'unknown session');
  end;

  procedure step_replay(p_replay_id in varchar2,p_payload out blob) is
    l_cursor replay_cursors%rowtype;l_command tic_commands%rowtype;
    l_expected varchar2(64);l_state clob;
  begin
    begin select * into l_cursor from replay_cursors where replay_id=p_replay_id for update;
    exception when no_data_found then fail(c_missing_replay,'unknown replay identifier');end;
    if l_cursor.completed=1 then
      response_blob(l_cursor.current_tic,l_cursor.state_sha,l_cursor.frame_sha,p_payload);
      return;
    end if;
    begin select * into l_command from tic_commands where session_token=l_cursor.session_token
      and lineage=l_cursor.lineage and tic=l_cursor.current_tic+1 and command_ordinal=0;
    exception when no_data_found then fail(c_bad_history,'replay command range incomplete');end;
    l_expected:=command_hash(l_command.command_seq,l_command.lineage,l_command.tic,
      l_command.command_ordinal,l_command.turn,l_command.forward_move,l_command.strafe,
      l_command.run,l_command.fire,l_command.use_action,l_command.weapon_slot,
      l_command.pause_toggle,l_command.automap_toggle,l_command.menu_action,
      l_command.cheat_code,l_command.previous_command_sha);
    l_state:=blob_text(l_command.state_blob);
    if l_command.previous_command_sha<>l_cursor.command_sha
       or l_command.command_sha<>l_expected
       or sha256(l_state)<>l_command.state_sha then
      fail(c_bad_history,'replay command continuity mismatch');
    end if;
    update replay_cursors set current_tic=l_command.tic,
      command_sha=l_command.command_sha,state_sha=l_command.state_sha,
      frame_sha=l_command.frame_sha,state_blob=l_command.state_blob,
      completed=case when l_command.tic=to_tic then 1 else 0 end
      where replay_id=p_replay_id;
    response_blob(l_command.tic,l_command.state_sha,l_command.frame_sha,p_payload);
  end;
end doom_history;
/

-- The reviewed DOOM_HISTORY API remains exactly six procedures.  The tic hot
-- path uses this standalone BLOB adapter so non-checkpoint tics do not pay for
-- an otherwise redundant BLOB-to-CLOB conversion.
create or replace procedure doom_capture_tic_blob(
  p_session in varchar2,p_tic in number,p_state_blob in blob,
  p_state_sha in varchar2,p_frame_sha in varchar2
) authid definer is
  c_bad_history constant pls_integer := -20891;
  c_zero_sha constant varchar2(64) := rpad('0',64,'0');
  c_reviewed_interval constant pls_integer := 4;
  l_lineage varchar2(64);l_current number;l_interval number;l_command_sha varchar2(64);
  l_event_sha varchar2(64);l_frame_sha varchar2(64);l_frontier number;l_first number;
  l_snapshot blob;l_snapshot_sha varchar2(64);
begin
  select save_lineage,current_tic into l_lineage,l_current from game_sessions
    where session_token=p_session for update;
  if p_tic<>l_current
     or lower(rawtohex(dbms_crypto.hash(p_state_blob,dbms_crypto.hash_sh256)))<>p_state_sha then
    raise_application_error(c_bad_history,'capture state mismatch');
  end if;
  begin
    select command_sha,frame_sha into l_command_sha,l_frame_sha from (
      select command_sha,frame_sha from tic_commands where session_token=p_session
        and lineage=l_lineage and tic<=p_tic
      order by tic desc,command_ordinal desc,command_seq desc)
    where rownum=1;
  exception when no_data_found then l_command_sha:=c_zero_sha;
  end;
  if l_command_sha=c_zero_sha then
    raise_application_error(c_bad_history,'captured tic has no command');
  end if;
  select number_value into l_interval from doom_config
    where config_key='HISTORY_SNAPSHOT_INTERVAL';
  if not regexp_like(l_lineage,'^[0-9a-f]{64}$')
     or mod(p_tic,c_reviewed_interval)=0 or mod(p_tic,l_interval)=0 then
    begin
      select event_sha into l_event_sha from (
        select event_sha from (
          select tic,event_ordinal,0 event_kind,event_sha from game_events
            where session_token=p_session and lineage=l_lineage and tic<=p_tic
          union all
          select tic,event_ordinal,1,event_sha from audio_events
            where session_token=p_session and lineage=l_lineage and tic<=p_tic)
        order by tic desc,event_kind desc,event_ordinal desc)
      where rownum=1;
    exception when no_data_found then l_event_sha:=c_zero_sha;
    end;
    select last_command_seq into l_frontier from game_sessions
      where session_token=p_session for update;
    select coalesce(min(command_seq),l_frontier+1) into l_first from tic_commands
      where session_token=p_session and lineage=l_lineage;
    select json_object('schema' value 1,'lineage' value l_lineage,
      'frontier' value l_frontier,'command_sha' value l_command_sha,
      'event_sha' value l_event_sha,'state_sha' value p_state_sha,
      'frame_sha' value p_frame_sha,'state' value p_state_blob format json
      returning blob) into l_snapshot from dual;
    l_snapshot_sha:=lower(rawtohex(dbms_crypto.hash(
      l_snapshot,dbms_crypto.hash_sh256)));
    begin
      insert into state_history(session_token,lineage,tic,first_command_seq,
        last_command_seq,state_sha,command_sha,event_sha,frame_sha,snapshot_sha,
        snapshot_reason,snapshot_blob)
      values(p_session,l_lineage,p_tic,l_first,l_frontier,p_state_sha,l_command_sha,
        l_event_sha,p_frame_sha,l_snapshot_sha,'INTERVAL',l_snapshot);
    exception when dup_val_on_index then null;
    end;
  end if;
end;
/
