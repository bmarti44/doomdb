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
  procedure create_match(
    p_game_mode         in  varchar2,
    p_skill             in  number,
    p_episode           in  number,
    p_map               in  number,
    p_display_name      in  varchar2,
    p_match             out varchar2,
    p_host_capability   out varchar2,
    p_join_capability   out varchar2,
    p_player_capability out varchar2,
    p_max_players       in  number default 2);

  procedure join_match(
    p_match             in     varchar2,
    p_join_capability   in     varchar2,
    p_display_name      in     varchar2,
    p_player_capability in out varchar2,
    p_player_slot       out    number);

  procedure ready_match(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_ready             in  number,
    p_match_state       out varchar2);

  procedure match_status(
    p_match             in  varchar2,
    p_capability        in  varchar2,
    p_match_state       out varchar2,
    p_game_mode         out varchar2,
    p_skill             out number,
    p_episode           out number,
    p_map               out number,
    p_max_players       out number,
    p_member_count      out number,
    p_ready_count       out number,
    p_requester_slot    out number,
    p_membership_epoch  out number,
    p_generation        out number,
    p_current_tic       out number,
    p_worker_mode       out varchar2);

  procedure submit_match_step(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_tic               in  number,
    p_command_seq       in  number,
    p_ticcmd_hex        in  varchar2,
    p_accepted          out number,
    p_membership_epoch  out number,
    p_generation        out number);

  procedure submit_match_batch(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_first_tic         in  number,
    p_first_command_seq in  number,
    p_ticcmd_hex        in  varchar2,
    p_accepted          out number,
    p_membership_epoch  out number,
    p_generation        out number,
    p_input_seq         in  number default null,
    p_input_ticcmd_hex  in  varchar2 default null);

  procedure submit_match_batch_input(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_first_tic         in  number,
    p_first_command_seq in  number,
    p_ticcmd_hex        in  varchar2,
    p_input_seq         in  number,
    p_input_ticcmd_hex  in  varchar2,
    p_accepted          out number,
    p_input_accepted    out number,
    p_effective_tic     out number,
    p_membership_epoch  out number,
    p_generation        out number,
    p_payload           out blob);

  procedure revise_match_input(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_input_seq         in  number,
    p_ticcmd_hex        in  varchar2,
    p_accepted          out number,
    p_effective_tic     out number,
    p_membership_epoch  out number,
    p_generation        out number,
    p_target_tic        in  number default null);

  procedure match_input_frontier(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_input_seq         out number);

  procedure exchange_match_batch(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_first_tic         in  number,
    p_first_frame_tic   in  number,
    p_first_command_seq in  number,
    p_ticcmd_hex        in  varchar2,
    p_wait_ms           in  number,
    p_accepted          out number,
    p_membership_epoch  out number,
    p_generation        out number,
    p_current_tic       out number,
    p_payload           out blob);

  procedure poll_match_batch(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_first_tic         in  number,
    p_wait_ms           in  number,
    p_frame_count       in  number default 4,
    p_current_tic       out number,
    p_payload           out blob);

  procedure poll_match_transitions(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_after_tic         in  number,
    p_hold_ms           in  number,
    p_max_transitions   in  number default 32,
    p_ready             out number,
    p_current_tic       out number,
    p_payload           out blob);

  $if $$doom_dev_ojvm $then
  procedure poll_match_frame(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_tic               in  number,
    p_wait_ms           in  number,
    p_ready             out number,
    p_current_tic       out number,
    p_payload           out blob);
  $end

  procedure leave_match(
    p_match             in  varchar2,
    p_player_capability in  varchar2,
    p_match_state       out varchar2);

  $if $$doom_dev_ojvm $then
  procedure new_game(
    p_skill       in  number,
    p_session     out varchar2,
    p_payload     out blob);

  procedure step(
    p_session     in  varchar2,
    p_commands    in  clob,
    p_payload     out blob);

  procedure submit_step(
    p_session     in  varchar2,
    p_commands    in  clob,
    p_request     out varchar2);

  procedure poll_frame(
    p_session     in  varchar2,
    p_seq         in  number,
    p_wait_ms     in  number,
    p_ready       out number,
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
  $end

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
  c_match_auth  constant pls_integer := -20713;

  procedure fail(p_code pls_integer, p_message varchar2) is
  begin
    raise_application_error(p_code,p_message);
  end;

  function player_capability_slot(
    p_match varchar2,p_capability varchar2,
    p_include_left number default 0) return number;

  procedure submit_match_batch_input(
    p_match in varchar2,p_player_capability in varchar2,p_first_tic in number,
    p_first_command_seq in number,p_ticcmd_hex in varchar2,p_input_seq in number,
    p_input_ticcmd_hex in varchar2,p_accepted out number,p_input_accepted out number,
    p_effective_tic out number,p_membership_epoch out number,p_generation out number,
    p_payload out blob
  ) is
    l_count number;l_slot number;l_base number;l_skip number;l_ready number;
    l_frame blob;l_length number;
    l_deadline timestamp with time zone;
  begin
    p_accepted:=0;p_input_accepted:=0;p_effective_tic:=null;
    p_membership_epoch:=null;p_generation:=null;p_payload:=null;
    if p_input_ticcmd_hex is null or
       not regexp_like(p_input_ticcmd_hex,'^([0-9a-fA-F]{16}){1,4}$') then
      fail(c_bad_request,'invalid fused input revisions');end if;
    l_count:=length(p_input_ticcmd_hex)/16;
    submit_match_batch(p_match,p_player_capability,p_first_tic,
      p_first_command_seq,p_ticcmd_hex,p_accepted,p_membership_epoch,p_generation,
      p_input_seq,p_input_ticcmd_hex);
    l_slot:=player_capability_slot(p_match,p_player_capability);
    select effective_tic into p_effective_tic from doom_match_input_event
      where match_id=p_match and player_slot=l_slot and input_seq=p_input_seq;
    p_input_accepted:=l_count;
    l_base:=p_effective_tic-mod(p_effective_tic-1,4);
    l_skip:=p_effective_tic-l_base;
    dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
    dbms_lob.writeappend(p_payload,6,
      utl_raw.concat(hextoraw('444d4232'),
        hextoraw(lpad(to_char(l_skip+1,'fmxx'),2,'0')),
        hextoraw('00')));
    for i in 0..l_skip loop
      l_deadline:=systimestamp+interval '2' second;
      loop
        l_ready:=0;
        begin
          select response_blob into l_frame from doom_match_frame
            where match_id=p_match and tic=l_base+i and player_slot=l_slot
              and membership_epoch=p_membership_epoch and generation=p_generation;
          l_ready:=1;
        exception when no_data_found then null;end;
        exit when l_ready=1 or systimestamp>=l_deadline;
        dbms_session.sleep(.005);
      end loop;
      if l_ready<>1 then p_payload:=null;return;end if;
      l_length:=dbms_lob.getlength(l_frame);
      dbms_lob.writeappend(p_payload,4,
        utl_raw.cast_from_binary_integer(l_length,utl_raw.big_endian));
      dbms_lob.copy(p_payload,l_frame,l_length,dbms_lob.getlength(p_payload)+1,1);
    end loop;
  end;

  function utc_now return timestamp with time zone is
  begin
    return localtimestamp at time zone 'UTC';
  end;

  -- expires_at is an idle lease, not an absolute match-duration limit. Renew
  -- it only after a capability-authenticated request; the retained worker must
  -- never keep an abandoned match alive by advancing neutral tics on its own.
  procedure renew_match_lease(p_match varchar2,p_now timestamp with time zone) is
  begin
    update doom_match set last_activity_at=p_now,
      expires_at=p_now+interval '20' minute
      where match_id=p_match and match_state in('LOBBY','ACTIVE')
        and expires_at<p_now+interval '10' minute;
  end;

  $if $$doom_dev_ojvm $then
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
  $end

  -- This bounded transport loop converts SQL-aggregated asset/response chunks;
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

  $if $$doom_dev_ojvm $then
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
  $end

  procedure copy_blob(p_source blob,p_target out blob) is
  begin
    dbms_lob.createtemporary(p_target,true,dbms_lob.call);
    dbms_lob.copy(p_target,p_source,dbms_lob.getlength(p_source));
  end;

  $if $$doom_dev_ojvm $then
  function config_number(p_key varchar2,p_default number) return number is
    l_value number;
  begin
    select number_value into l_value from doom_config where config_key=p_key;
    return l_value;
  exception when no_data_found then return p_default;
  end;
  $end

  function config_text(p_key varchar2,p_default varchar2) return varchar2 is
    l_value varchar2(4000);
  begin
    select text_value into l_value from doom_config where config_key=p_key;
    return l_value;
  exception when no_data_found then return p_default;
  end;

  function new_capability return varchar2 is
  begin
    return lower(rawtohex(dbms_crypto.randombytes(32)));
  end;

  function capability_hash(
    p_salt raw,p_capability varchar2
  ) return varchar2 is
  begin
    if p_capability is null or
       not regexp_like(p_capability,'^[0-9a-f]{64}$') then return null;end if;
    return lower(rawtohex(dbms_crypto.hash(
      utl_raw.concat(p_salt,hextoraw(p_capability)),
      dbms_crypto.hash_sh256)));
  exception when others then return null;
  end;

  procedure require_match_shape(p_match varchar2) is
  begin
    if p_match is null or not regexp_like(p_match,'^[0-9a-f]{32}$') then
      fail(c_match_auth,'match unavailable');
    end if;
  end;

  procedure require_display_name(p_name varchar2) is
  begin
    if p_name is null or lengthb(p_name)>32 or p_name<>trim(p_name) or
       regexp_like(p_name,'[[:cntrl:]]') then
      fail(c_bad_request,'display name is invalid');
    end if;
  end;

  function player_capability_slot(
    p_match varchar2,p_capability varchar2,p_include_left number default 0
  ) return number is
  begin
    if p_capability is not null and
       regexp_like(p_capability,'^[0-9a-f]{64}$') then
      for member_ in (
        select player_slot,member_state,capability_salt,capability_hash
        from doom_match_member where match_id=p_match order by player_slot
      ) loop
        if capability_hash(member_.capability_salt,p_capability)=
             member_.capability_hash and
           (p_include_left=1 or member_.member_state<>'LEFT') then
          return member_.player_slot;
        end if;
      end loop;
    end if;
    fail(c_match_auth,'match unavailable');
    return null;
  end;

  function any_capability_slot(
    p_match varchar2,p_capability varchar2,
    p_host_salt raw,p_host_hash varchar2
  ) return number is
  begin
    if capability_hash(p_host_salt,p_capability)=p_host_hash then return -1;end if;
    return player_capability_slot(p_match,p_capability);
  end;

  procedure create_match(
    p_game_mode in varchar2,p_skill in number,p_episode in number,
    p_map in number,p_display_name in varchar2,p_match out varchar2,
    p_host_capability out varchar2,p_join_capability out varchar2,
    p_player_capability out varchar2,p_max_players in number default 2
  ) is
    l_now timestamp with time zone:=utc_now;
    l_host_salt raw(32);l_join_salt raw(32);l_player_salt raw(32);
    l_solo_salt raw(32);l_solo_capability varchar2(64);l_solo_hash varchar2(64);
    l_host_hash varchar2(64);l_join_hash varchar2(64);l_player_hash varchar2(64);
    l_recent number;l_open number;l_lock number;
  begin
    p_match:=null;p_host_capability:=null;p_join_capability:=null;
    p_player_capability:=null;
    if p_game_mode is null or upper(p_game_mode) not in('COOP','DEATHMATCH') then
      fail(c_bad_request,'invalid match mode');
    end if;
    if p_skill is null or p_skill<>trunc(p_skill) or p_skill not between 1 and 5 or
       p_episode is null or p_episode<>trunc(p_episode) or
       p_episode not between 1 and 9 or p_map is null or p_map<>trunc(p_map) or
       p_map not between 1 and 99 or p_max_players is null or
       p_max_players<>trunc(p_max_players) or p_max_players not in(1,2) then
      fail(c_bad_request,'invalid match map selection');
    end if;
    require_display_name(p_display_name);

    -- Serialize the bounded global create check on an existing immutable
    -- configuration row. AutoREST supplies no trustworthy client address, so
    -- v1 uses a deliberately small global burst/open-lobby limit.
    select number_value into l_lock from doom_config
      where config_key='MAX_ACTIVE_SESSIONS' for update;
    select count(*) into l_recent from doom_match
      where created_at>l_now-interval '1' minute;
    select count(*) into l_open from doom_match
      where match_state in('LOBBY','ACTIVE') and expires_at>l_now;
    if l_recent>=16 or l_open>=32 then
      fail(c_capacity,'match capacity reached');
    end if;

    p_match:=lower(rawtohex(dbms_crypto.randombytes(16)));
    p_host_capability:=new_capability;
    p_join_capability:=new_capability;
    p_player_capability:=new_capability;
    l_host_salt:=dbms_crypto.randombytes(32);
    l_join_salt:=dbms_crypto.randombytes(32);
    l_player_salt:=dbms_crypto.randombytes(32);
    l_host_hash:=capability_hash(l_host_salt,p_host_capability);
    l_join_hash:=capability_hash(l_join_salt,p_join_capability);
    l_player_hash:=capability_hash(l_player_salt,p_player_capability);
    insert into doom_match(
      match_id,match_state,game_mode,skill,episode,map,max_players,
      membership_epoch,generation,current_tic,
      host_capability_salt,host_capability_hash,
      join_capability_salt,join_capability_hash,
      created_at,last_activity_at,expires_at)
    values(p_match,'LOBBY',upper(p_game_mode),p_skill,p_episode,p_map,2,1,0,0,
      l_host_salt,l_host_hash,l_join_salt,l_join_hash,
      l_now,l_now,l_now+interval '20' minute);
    insert into doom_match_member(
      match_id,player_slot,member_state,membership_epoch,generation,
      capability_epoch,capability_salt,capability_hash,display_name,
      joined_at,last_seen_at)
    values(p_match,0,'JOINED',1,0,1,l_player_salt,l_player_hash,
      p_display_name,l_now,l_now);
    if p_max_players=1 then
      -- The accepted MLE authority/checkpoint format is a two-slot lockstep
      -- world. Solo play preserves that proven identity with an uncredentialed
      -- neutral peer; its random bearer is discarded before commit, so no
      -- browser can join or control slot 1.
      l_solo_salt:=dbms_crypto.randombytes(32);
      l_solo_capability:=new_capability;
      l_solo_hash:=capability_hash(l_solo_salt,l_solo_capability);
      insert into doom_match_member(
        match_id,player_slot,member_state,membership_epoch,generation,
        capability_epoch,capability_salt,capability_hash,display_name,
        joined_at,last_seen_at,ready_at)
      values(p_match,1,'READY',1,0,1,l_solo_salt,l_solo_hash,
        'SOLO NEUTRAL',l_now,l_now,l_now);
      l_solo_capability:=null;
    end if;
    commit;
  exception when others then
    declare l_code pls_integer:=sqlcode;l_message varchar2(1800):=substr(sqlerrm,1,1800);
    begin
      rollback;p_match:=null;p_host_capability:=null;p_join_capability:=null;
      p_player_capability:=null;
      if l_code between -20999 and -20000 then
        raise_application_error(l_code,l_message);
      end if;
      raise_application_error(c_capacity,'match creation failed');
    end;
  end;

  procedure join_match(
    p_match in varchar2,p_join_capability in varchar2,
    p_display_name in varchar2,p_player_capability in out varchar2,
    p_player_slot out number
  ) is
    l_state varchar2(16);l_join_salt raw(32);l_join_hash varchar2(64);
    l_expiry timestamp with time zone;l_now timestamp with time zone:=utc_now;
    l_max number;l_epoch number;l_generation number;l_slot number;l_count number;
    l_player_salt raw(32);l_player_hash varchar2(64);
    l_player_token varchar2(64):=p_player_capability;
  begin
    p_player_slot:=null;require_match_shape(p_match);
    require_display_name(p_display_name);
    select match_state,join_capability_salt,join_capability_hash,expires_at,
           max_players,membership_epoch,generation
      into l_state,l_join_salt,l_join_hash,l_expiry,l_max,l_epoch,l_generation
      from doom_match where match_id=p_match for update;
    if l_expiry<=l_now or l_state<>'LOBBY' or
       capability_hash(l_join_salt,p_join_capability)<>l_join_hash then
      fail(c_match_auth,'match unavailable');
    end if;

    -- Supplying the previously returned player capability makes JOIN a safe
    -- retry/reconnect without ever persisting or reproducing bearer plaintext.
    if l_player_token is not null then
      l_slot:=player_capability_slot(p_match,l_player_token);
      select member_state into l_state from doom_match_member
        where match_id=p_match and player_slot=l_slot;
      if l_state='LEFT' then fail(c_match_auth,'match unavailable');end if;
      update doom_match_member set last_seen_at=l_now
        where match_id=p_match and player_slot=l_slot;
      update doom_match set last_activity_at=l_now where match_id=p_match;
      p_player_slot:=l_slot;commit;return;
    end if;

    select min(slot_) into l_slot from (
      select level slot_ from dual connect by level<=l_max-1
    ) slots where not exists(
      select 1 from doom_match_member member_
      where member_.match_id=p_match and member_.player_slot=slots.slot_
        and member_.member_state<>'LEFT');
    if l_slot is null then fail(c_capacity,'match capacity reached');end if;
    l_epoch:=l_epoch+1;
    update doom_match set membership_epoch=l_epoch,last_activity_at=l_now
      where match_id=p_match and membership_epoch=l_epoch-1 and generation=l_generation;
    if sql%rowcount<>1 then fail(c_match_auth,'match unavailable');end if;
    update doom_match_member set membership_epoch=l_epoch where match_id=p_match;
    p_player_capability:=new_capability;
    l_player_salt:=dbms_crypto.randombytes(32);
    l_player_hash:=capability_hash(l_player_salt,p_player_capability);
    update doom_match_member set member_state='JOINED',membership_epoch=l_epoch,
      generation=l_generation,capability_epoch=capability_epoch+1,
      capability_salt=l_player_salt,
      capability_hash=l_player_hash,
      display_name=p_display_name,joined_at=l_now,last_seen_at=l_now,
      ready_at=null,disconnected_at=null,leave_tic=null
      where match_id=p_match and player_slot=l_slot and member_state='LEFT';
    l_count:=sql%rowcount;
    if l_count=0 then
      insert into doom_match_member(
        match_id,player_slot,member_state,membership_epoch,generation,
        capability_epoch,capability_salt,capability_hash,display_name,
        joined_at,last_seen_at)
      values(p_match,l_slot,'JOINED',l_epoch,l_generation,1,l_player_salt,
        l_player_hash,
        p_display_name,l_now,l_now);
    end if;
    p_player_slot:=l_slot;commit;
  exception when no_data_found then
    rollback;p_player_capability:=null;p_player_slot:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;l_message varchar2(1800):=substr(sqlerrm,1,1800);
    begin
      rollback;p_player_slot:=null;
      if l_player_token is null then p_player_capability:=null;end if;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      end if;
      if l_code between -20999 and -20000 then
        raise_application_error(l_code,l_message);
      end if;
      raise_application_error(c_match_auth,'match unavailable');
    end;
  end;

  procedure ready_match(
    p_match in varchar2,p_player_capability in varchar2,p_ready in number,
    p_match_state out varchar2
  ) is
    l_state varchar2(16);l_expiry timestamp with time zone;l_now timestamp with time zone:=utc_now;
    l_max number;l_slot number;l_members number;l_ready number;
  begin
    p_match_state:=null;require_match_shape(p_match);
    if p_ready is null or p_ready<>trunc(p_ready) or p_ready not in(0,1) then
      fail(c_bad_request,'ready flag must be 0 or 1');
    end if;
    select match_state,expires_at,max_players into l_state,l_expiry,l_max
      from doom_match where match_id=p_match for update;
    if l_expiry<=l_now or l_state<>'LOBBY' then
      fail(c_match_auth,'match unavailable');
    end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    select count(*) into l_members from doom_match_member
      where match_id=p_match and member_state in('JOINED','READY');
    if p_ready=1 and l_members<>l_max then
      fail(c_bad_request,'all player slots must be joined before ready');
    end if;
    update doom_match_member set
      member_state=case p_ready when 1 then 'READY' else 'JOINED' end,
      ready_at=case p_ready when 1 then l_now else null end,last_seen_at=l_now
      where match_id=p_match and player_slot=l_slot
        and member_state in('JOINED','READY');
    if sql%rowcount<>1 then fail(c_match_auth,'match unavailable');end if;
    select count(*) into l_ready from doom_match_member
      where match_id=p_match and member_state='READY';
    update doom_match set last_activity_at=l_now where match_id=p_match;
    if l_members=l_max and l_ready=l_max then
      -- Commit READY membership before Scheduler creates its retained session.
      -- START_READY returns ACTIVE only after the retained MLE engine, its
      -- authoritative tic-zero identity/frontier, and its generation-matched
      -- warm recovery context are all committed and ready.
      commit;
      doom_match_worker.start_ready(p_match,30000,p_match_state);
    else
      p_match_state:='LOBBY';commit;
    end if;
  exception when no_data_found then
    rollback;p_match_state:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;l_message varchar2(1800):=substr(sqlerrm,1,1800);
    begin
      rollback;p_match_state:=null;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      end if;
      if l_code between -20999 and -20000 then
        raise_application_error(l_code,l_message);
      end if;
      raise_application_error(c_match_auth,'match unavailable');
    end;
  end;

  procedure match_status(
    p_match in varchar2,p_capability in varchar2,p_match_state out varchar2,
    p_game_mode out varchar2,p_skill out number,p_episode out number,
    p_map out number,p_max_players out number,p_member_count out number,
    p_ready_count out number,p_requester_slot out number,
    p_membership_epoch out number,p_generation out number,p_current_tic out number,
    p_worker_mode out varchar2
  ) is
    l_state varchar2(16);l_expiry timestamp with time zone;
    l_host_salt raw(32);l_host_hash varchar2(64);
    l_worker_status varchar2(16);
  begin
    p_match_state:=null;p_game_mode:=null;p_skill:=null;p_episode:=null;
    p_map:=null;p_max_players:=null;p_member_count:=null;p_ready_count:=null;
    p_requester_slot:=null;p_membership_epoch:=null;p_generation:=null;
    p_current_tic:=null;p_worker_mode:=null;require_match_shape(p_match);
    select match_state,game_mode,skill,episode,map,max_players,
           membership_epoch,generation,current_tic,expires_at,
           host_capability_salt,host_capability_hash
      into l_state,p_game_mode,p_skill,p_episode,p_map,p_max_players,
           p_membership_epoch,p_generation,p_current_tic,l_expiry,
           l_host_salt,l_host_hash
      from doom_match where match_id=p_match;
    if l_expiry<=utc_now then fail(c_match_auth,'match unavailable');end if;
    p_requester_slot:=any_capability_slot(
      p_match,p_capability,l_host_salt,l_host_hash);
    renew_match_lease(p_match,utc_now);
    select count(*),count(case when member_state='READY' then 1 end)
      into p_member_count,p_ready_count from doom_match_member
      where match_id=p_match and member_state<>'LEFT';
    p_match_state:=l_state;
    begin
      select worker_mode,worker_status into p_worker_mode,l_worker_status
        from doom_match_worker_control
        where match_id=p_match;
      if l_state='ACTIVE' and l_worker_status<>'READY' then
        p_match_state:='STARTING';
      end if;
    exception when no_data_found then
      select text_value into p_worker_mode from doom_config
        where config_key='MATCH_WORKER_MODE';
    end;
    if l_state='LOBBY' and p_member_count=p_max_players and
       p_ready_count=p_max_players then
      -- Concurrent READY commits can each observe only itself and leave a
      -- fully-ready lobby unclaimed. Authorized status polling is a generated
      -- AutoREST POST, so use it as an idempotent fenced claim/retry boundary.
      doom_match_worker.start_ready(p_match,20,p_match_state);
    else
      commit;
    end if;
  exception when no_data_found then
    p_match_state:=null;raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;l_message varchar2(1800):=substr(sqlerrm,1,1800);
    begin
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      end if;
      if l_code between -20999 and -20000 then
        raise_application_error(l_code,l_message);
      end if;
      raise_application_error(c_match_auth,'match unavailable');
    end;
  end;

  procedure submit_match_step(
    p_match in varchar2,p_player_capability in varchar2,p_tic in number,
    p_command_seq in number,p_ticcmd_hex in varchar2,p_accepted out number,
    p_membership_epoch out number,p_generation out number
  ) is
    l_slot number;l_state varchar2(16);l_expiry timestamp with time zone;
    l_now timestamp with time zone:=utc_now;l_raw raw(8);
  begin
    p_accepted:=0;p_membership_epoch:=null;p_generation:=null;
    require_match_shape(p_match);
    if p_tic is null or p_tic<>trunc(p_tic) or p_tic<1 or
       p_command_seq is null or p_command_seq<>trunc(p_command_seq) or
       p_command_seq<1 or p_ticcmd_hex is null or
       not regexp_like(p_ticcmd_hex,'^[0-9a-fA-F]{16}$') or
       substr(lower(p_ticcmd_hex),9,6)<>'000000' then
      fail(c_bad_request,'invalid match command');
    end if;
    select match_state,expires_at,membership_epoch,generation
      into l_state,l_expiry,p_membership_epoch,p_generation
      from doom_match where match_id=p_match;
    if l_state<>'ACTIVE' or l_expiry<=l_now or p_generation<1 then
      fail(c_match_auth,'match unavailable');
    end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null
      where match_id=p_match and player_slot=l_slot
        and member_state in('ACTIVE','DISCONNECTED')
        and membership_epoch=p_membership_epoch and generation=p_generation;
    if sql%rowcount<>1 then fail(c_match_auth,'match unavailable');end if;
    renew_match_lease(p_match,l_now);
    l_raw:=hextoraw(lower(p_ticcmd_hex));
    doom_match_worker.submit_command(p_match,l_slot,p_membership_epoch,
      p_generation,p_tic,p_command_seq,l_raw,p_accepted);
  exception when no_data_found then
    rollback;p_accepted:=0;p_membership_epoch:=null;p_generation:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;
    begin
      rollback;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      elsif l_code between -20999 and -20000 then
        raise_application_error(c_bad_request,'match command rejected');
      end if;
      raise_application_error(c_bad_request,'match command rejected');
    end;
  end;

  procedure submit_match_batch(
    p_match in varchar2,p_player_capability in varchar2,p_first_tic in number,
    p_first_command_seq in number,p_ticcmd_hex in varchar2,p_accepted out number,
    p_membership_epoch out number,p_generation out number,
    p_input_seq in number default null,p_input_ticcmd_hex in varchar2 default null
  ) is
    l_slot number;l_state varchar2(16);l_expiry timestamp with time zone;
    l_now timestamp with time zone:=utc_now;l_raw raw(32);l_input_raw raw(32);
  begin
    p_accepted:=0;p_membership_epoch:=null;p_generation:=null;
    if p_first_tic is null or p_first_tic<>trunc(p_first_tic) or
       p_first_command_seq is null or
       p_first_command_seq<>trunc(p_first_command_seq) or
       p_ticcmd_hex is null or
       not regexp_like(p_ticcmd_hex,'^([0-9a-fA-F]{32}|[0-9a-fA-F]{64})$') or
       substr(lower(p_ticcmd_hex),9,6)<>'000000' or
       substr(lower(p_ticcmd_hex),25,6)<>'000000' or
       (length(p_ticcmd_hex)=64 and
         (substr(lower(p_ticcmd_hex),41,6)<>'000000' or
          substr(lower(p_ticcmd_hex),57,6)<>'000000')) then
      fail(c_bad_request,'invalid match command batch');
    end if;
    if (p_input_seq is null and p_input_ticcmd_hex is not null) or
       (p_input_seq is not null and (p_input_seq<>trunc(p_input_seq) or p_input_seq<1 or
        p_input_ticcmd_hex is null or
        not regexp_like(p_input_ticcmd_hex,'^([0-9a-fA-F]{16}){1,4}$'))) then
      fail(c_bad_request,'invalid fused input revisions');end if;
    require_match_shape(p_match);
    select match_state,expires_at,membership_epoch,generation
      into l_state,l_expiry,p_membership_epoch,p_generation
      from doom_match where match_id=p_match;
    if l_state<>'ACTIVE' or l_expiry<=l_now or p_generation<1 then
      fail(c_match_auth,'match unavailable');
    end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    renew_match_lease(p_match,l_now);
    l_raw:=hextoraw(lower(p_ticcmd_hex));
    if p_input_ticcmd_hex is not null then
      l_input_raw:=hextoraw(lower(p_input_ticcmd_hex));end if;
    doom_match_worker.submit_command_batch(p_match,l_slot,p_membership_epoch,
      p_generation,p_first_tic,p_first_command_seq,l_raw,p_accepted,
      p_input_seq,l_input_raw);
  exception when no_data_found then
    rollback;p_accepted:=0;p_membership_epoch:=null;p_generation:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;
    begin
      rollback;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      elsif l_code between -20999 and -20000 then
        raise_application_error(c_bad_request,'match command batch rejected');
      end if;
      raise_application_error(c_bad_request,'match command batch rejected');
    end;
  end;

  procedure revise_match_input(
    p_match in varchar2,p_player_capability in varchar2,p_input_seq in number,
    p_ticcmd_hex in varchar2,p_accepted out number,p_effective_tic out number,
    p_membership_epoch out number,p_generation out number,
    p_target_tic in number default null
  ) is
    l_slot number;l_state varchar2(16);l_expiry timestamp with time zone;
    l_current number;l_frontier number;l_existing raw(8);l_raw raw(8);
    l_worker_mode varchar2(16);l_prior_effective number;l_sampling_tic number;
    l_request_status varchar2(16);
    l_now timestamp with time zone:=utc_now;
  begin
    p_accepted:=0;p_effective_tic:=null;
    p_membership_epoch:=null;p_generation:=null;
    if p_input_seq is null or p_input_seq<>trunc(p_input_seq) or p_input_seq<1 or
       p_ticcmd_hex is null or
       not regexp_like(p_ticcmd_hex,'^[0-9a-fA-F]{16}$') or
       substr(lower(p_ticcmd_hex),9,6)<>'000000' then
      fail(c_bad_request,'invalid match input revision');
    end if;
    require_match_shape(p_match);l_raw:=hextoraw(lower(p_ticcmd_hex));
    select match_state,expires_at,membership_epoch,generation,current_tic
      into l_state,l_expiry,p_membership_epoch,p_generation,l_current
      from doom_match where match_id=p_match for update;
    if l_state<>'ACTIVE' or l_expiry<=l_now or p_generation<1 then
      fail(c_match_auth,'match unavailable');end if;
    if p_target_tic is not null and
       (p_target_tic<>trunc(p_target_tic) or p_target_tic<1 or
        p_target_tic>l_current+12) then
      fail(c_bad_request,'invalid match input target');end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    select worker_mode,request_status,requested_tic
      into l_worker_mode,l_request_status,l_sampling_tic
      from doom_match_worker_control
      where match_id=p_match and generation=p_generation;
    begin
      select ticcmd_raw,effective_tic into l_existing,p_effective_tic
        from doom_match_input_event where match_id=p_match
          and player_slot=l_slot and input_seq=p_input_seq;
      if l_existing<>l_raw then fail(c_bad_request,'input revision mismatch');end if;
      renew_match_lease(p_match,l_now);p_accepted:=1;commit;return;
    exception when no_data_found then null;end;
    select coalesce(max(input_seq),0) into l_frontier
      from doom_match_input_event where match_id=p_match and player_slot=l_slot;
    if p_input_seq<>l_frontier+1 then fail(c_bad_request,'input revision sequence');end if;
    select coalesce(max(effective_tic),l_current) into l_prior_effective
      from doom_match_input_event where match_id=p_match and player_slot=l_slot;
    p_effective_tic:=case when l_worker_mode='PACED_INPUT'
      then greatest(l_current+1,l_prior_effective+1,
        case when l_request_status='PROCESSING' then l_sampling_tic+1
             else l_current+1 end,nvl(p_target_tic,l_current+1))
      else l_current+2 end;
    insert into doom_match_input_event(match_id,player_slot,input_seq,effective_tic,
      membership_epoch,generation,ticcmd_raw,command_sha,accepted_at)
    values(p_match,l_slot,p_input_seq,p_effective_tic,p_membership_epoch,
      p_generation,l_raw,lower(rawtohex(dbms_crypto.hash(
        l_raw,dbms_crypto.hash_sh256))),l_now);
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null where match_id=p_match and player_slot=l_slot
      and membership_epoch=p_membership_epoch and generation=p_generation
      and member_state in('ACTIVE','DISCONNECTED');
    if sql%rowcount<>1 then fail(c_match_auth,'match unavailable');end if;
    renew_match_lease(p_match,l_now);p_accepted:=1;commit;
  exception when no_data_found then
    rollback;p_accepted:=0;p_effective_tic:=null;
    p_membership_epoch:=null;p_generation:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;begin
      rollback;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      elsif l_code between -20999 and -20000 then
        raise_application_error(c_bad_request,'match input revision rejected');
      end if;
      raise_application_error(c_bad_request,'match input revision rejected');
    end;
  end;

  procedure match_input_frontier(
    p_match in varchar2,p_player_capability in varchar2,p_input_seq out number
  ) is
    l_slot number;
  begin
    p_input_seq:=null;require_match_shape(p_match);
    l_slot:=player_capability_slot(p_match,p_player_capability);
    select coalesce(max(input_seq),0) into p_input_seq
      from doom_match_input_event
      where match_id=p_match and player_slot=l_slot;
    renew_match_lease(p_match,utc_now);commit;
  exception when no_data_found then
    p_input_seq:=null;raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;l_message varchar2(1800):=substr(sqlerrm,1,1800);
    begin
      p_input_seq:=null;
      if l_code between -20999 and -20000 then
        raise_application_error(l_code,l_message);
      end if;
      raise_application_error(c_match_auth,'match unavailable');
    end;
  end;

  procedure exchange_match_batch(
    p_match in varchar2,p_player_capability in varchar2,p_first_tic in number,
    p_first_frame_tic in number,p_first_command_seq in number,
    p_ticcmd_hex in varchar2,p_wait_ms in number,
    p_accepted out number,p_membership_epoch out number,p_generation out number,
    p_current_tic out number,p_payload out blob
  ) is
    l_ready number;l_frame blob;l_length number;l_slot number;
    l_deadline timestamp with time zone;l_now timestamp with time zone;
    l_frontier number;
  begin
    p_payload:=null;p_current_tic:=null;
    if p_first_frame_tic is null or
       p_first_frame_tic<>trunc(p_first_frame_tic) or p_first_frame_tic<1 or
       p_first_frame_tic>p_first_tic or
       p_wait_ms is null or p_wait_ms<>trunc(p_wait_ms) or
       p_wait_ms not between 0 and 1000 then
      fail(c_bad_request,'invalid match exchange wait');
    end if;
    -- A second exchange lane can reserve the next batch before the first lane
    -- has advanced the durable frontier.  Wait inside the correlated request
    -- rather than rejecting valid, bounded four-tic lead commands.
    l_deadline:=systimestamp+numtodsinterval(p_wait_ms/1000,'SECOND');
    loop
      select current_tic into l_frontier from doom_match where match_id=p_match;
      exit when p_first_tic<=l_frontier+4 or systimestamp>=l_deadline;
      dbms_session.sleep(.005);
    end loop;
    if p_first_tic>l_frontier+4 then
      fail(c_bad_request,'match exchange frontier wait expired');
    end if;
    submit_match_batch(p_match,p_player_capability,p_first_tic,
      p_first_command_seq,p_ticcmd_hex,p_accepted,
      p_membership_epoch,p_generation);
    l_slot:=player_capability_slot(p_match,p_player_capability);
    dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
    dbms_lob.writeappend(p_payload,5,hextoraw('444d423104'));
    for i in 0..3 loop
      l_deadline:=systimestamp+numtodsinterval(p_wait_ms/1000,'SECOND');
      loop
        l_ready:=0;
        begin
          select response_blob into l_frame from doom_match_frame
            where match_id=p_match and tic=p_first_frame_tic+i
              and player_slot=l_slot and membership_epoch=p_membership_epoch
              and generation=p_generation;
          l_ready:=1;
        exception when no_data_found then null;end;
        exit when l_ready=1 or systimestamp>=l_deadline;
        dbms_session.sleep(.01);
      end loop;
      if l_ready<>1 then p_payload:=null;return;end if;
      l_length:=dbms_lob.getlength(l_frame);
      dbms_lob.writeappend(p_payload,4,
        utl_raw.cast_from_binary_integer(l_length,utl_raw.big_endian));
      dbms_lob.copy(p_payload,l_frame,l_length,
        dbms_lob.getlength(p_payload)+1,1);
    end loop;
    select current_tic into p_current_tic from doom_match
      where match_id=p_match and membership_epoch=p_membership_epoch
        and generation=p_generation;
    l_now:=utc_now;
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null where match_id=p_match and player_slot=l_slot
      and member_state in('ACTIVE','DISCONNECTED')
      and membership_epoch=p_membership_epoch and generation=p_generation;
    commit;
  end;

  procedure poll_match_batch(
    p_match in varchar2,p_player_capability in varchar2,p_first_tic in number,
    p_wait_ms in number,p_frame_count in number default 4,
    p_current_tic out number,p_payload out blob
  ) is
    l_state varchar2(16);l_expiry timestamp with time zone;
    l_epoch number;l_generation number;l_slot number;l_ready number;
    l_frame blob;l_length number;l_deadline timestamp with time zone;
    l_base_tic number;l_total number;l_skip number;
    l_now timestamp with time zone:=utc_now;l_worker_mode varchar2(16);
  begin
    p_payload:=null;p_current_tic:=null;require_match_shape(p_match);
    if p_first_tic is null or p_first_tic<>trunc(p_first_tic) or p_first_tic<1 or
       p_wait_ms is null or p_wait_ms<>trunc(p_wait_ms) or
       p_wait_ms not between 0 and 5000 or p_frame_count is null or
       p_frame_count<>trunc(p_frame_count) or p_frame_count not between 1 and 4
       then fail(c_bad_request,'invalid match batch poll');end if;
    select match_state,expires_at,membership_epoch,generation,current_tic
      into l_state,l_expiry,l_epoch,l_generation,p_current_tic
      from doom_match where match_id=p_match;
    if l_state<>'ACTIVE' or l_expiry<=l_now or l_generation<1 then
      fail(c_match_auth,'match unavailable');end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    select worker_mode into l_worker_mode from doom_match_worker_control
      where match_id=p_match and generation=l_generation;
    if l_worker_mode='PACED_INPUT' then
      l_base_tic:=p_first_tic;l_skip:=0;l_total:=p_frame_count;
    else
      l_base_tic:=p_first_tic-mod(p_first_tic-1,4);
      l_skip:=p_first_tic-l_base_tic;l_total:=p_frame_count+l_skip;
    end if;
    dbms_lob.createtemporary(p_payload,true,dbms_lob.call);
    if l_worker_mode='PACED_INPUT' then
      dbms_lob.writeappend(p_payload,5,
        utl_raw.concat(hextoraw('444d4233'),
          hextoraw(lpad(to_char(l_total,'fmxx'),2,'0'))));
    else
      dbms_lob.writeappend(p_payload,6,
        utl_raw.concat(hextoraw('444d4232'),
          hextoraw(lpad(to_char(l_total,'fmxx'),2,'0')),
          hextoraw(lpad(to_char(l_skip,'fmxx'),2,'0'))));
    end if;
    for i in 0..l_total-1 loop
      l_deadline:=systimestamp+numtodsinterval(p_wait_ms/1000,'SECOND');
      loop
        l_ready:=0;
        begin
          select response_blob into l_frame from doom_match_frame
            where match_id=p_match and tic=l_base_tic+i
              and player_slot=l_slot and membership_epoch=l_epoch
              and generation=l_generation;
          l_ready:=1;
        exception when no_data_found then null;end;
        exit when l_ready=1 or systimestamp>=l_deadline;
        dbms_session.sleep(.01);
      end loop;
      if l_ready<>1 then p_payload:=null;return;end if;
      l_length:=dbms_lob.getlength(l_frame);
      dbms_lob.writeappend(p_payload,4,
        utl_raw.cast_from_binary_integer(l_length,utl_raw.big_endian));
      dbms_lob.copy(p_payload,l_frame,l_length,
        dbms_lob.getlength(p_payload)+1,1);
    end loop;
    select current_tic into p_current_tic from doom_match
      where match_id=p_match and membership_epoch=l_epoch and generation=l_generation;
    update doom_match_member set
      member_state=case when l_worker_mode='LOCKSTEP' then 'ACTIVE' else member_state end,
      last_seen_at=l_now,
      disconnected_at=case when l_worker_mode='LOCKSTEP' then null else disconnected_at end
      where match_id=p_match and player_slot=l_slot
      and member_state in('ACTIVE','DISCONNECTED')
      and membership_epoch=l_epoch and generation=l_generation;
    renew_match_lease(p_match,l_now);
    commit;
  exception when no_data_found then
    rollback;p_current_tic:=null;p_payload:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    rollback;p_current_tic:=null;p_payload:=null;
    raise_application_error(c_bad_request,'match batch poll rejected');
  end;

  procedure poll_match_transitions(
    p_match in varchar2,p_player_capability in varchar2,p_after_tic in number,
    p_hold_ms in number,p_max_transitions in number default 32,
    p_ready out number,p_current_tic out number,p_payload out blob
  ) is
    l_state varchar2(16);l_expiry timestamp with time zone;
    l_epoch number;l_generation number;l_slot number;
    l_now timestamp with time zone:=utc_now;
  begin
    p_ready:=0;p_current_tic:=null;p_payload:=null;require_match_shape(p_match);
    if p_after_tic is null or p_after_tic<>trunc(p_after_tic) or p_after_tic<0 or
       p_hold_ms is null or p_hold_ms<>trunc(p_hold_ms) or
       p_hold_ms not between 0 and 500 or p_max_transitions is null or
       p_max_transitions<>trunc(p_max_transitions) or
       p_max_transitions not between 1 and 64 then
      fail(c_bad_request,'invalid match transition poll');
    end if;
    select match_state,expires_at,membership_epoch,generation,current_tic
      into l_state,l_expiry,l_epoch,l_generation,p_current_tic
      from doom_match where match_id=p_match;
    if l_state<>'ACTIVE' or l_expiry<=l_now or l_generation<1 or
       p_after_tic>p_current_tic then
      fail(c_match_auth,'match unavailable');
    end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    doom_mle_transition_transport.poll_batch(
      p_match,l_slot,l_epoch,l_generation,p_after_tic,p_max_transitions,
      p_hold_ms,p_ready,p_payload);
    select current_tic into p_current_tic from doom_match
      where match_id=p_match and membership_epoch=l_epoch
        and generation=l_generation;
    l_now:=utc_now;
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null where match_id=p_match and player_slot=l_slot
      and member_state in('ACTIVE','DISCONNECTED')
      and membership_epoch=l_epoch and generation=l_generation;
    renew_match_lease(p_match,l_now);
    commit;
  exception when no_data_found then
    rollback;p_ready:=0;p_current_tic:=null;p_payload:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;
    begin
      rollback;p_ready:=0;p_current_tic:=null;p_payload:=null;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      elsif l_code between -20999 and -20000 then
        raise_application_error(c_bad_request,'match transition poll rejected');
      end if;
      raise_application_error(c_bad_request,'match transition poll rejected');
    end;
  end;

  $if $$doom_dev_ojvm $then
  procedure poll_match_frame(
    p_match in varchar2,p_player_capability in varchar2,p_tic in number,
    p_wait_ms in number,p_ready out number,p_current_tic out number,
    p_payload out blob
  ) is
    l_slot number;l_state varchar2(16);l_expiry timestamp with time zone;
    l_epoch number;l_generation number;l_wait number;
    l_deadline timestamp with time zone;l_now timestamp with time zone:=utc_now;
    l_worker_status varchar2(16);l_worker_heartbeat timestamp with time zone;
    l_recovery_state varchar2(16);
  begin
    p_ready:=0;p_current_tic:=null;p_payload:=null;require_match_shape(p_match);
    if p_tic is null or p_tic<>trunc(p_tic) or p_tic<0 or
       p_wait_ms is null or p_wait_ms<>trunc(p_wait_ms) or
       p_wait_ms not between 0 and 1000 then
      fail(c_bad_request,'invalid match poll');
    end if;
    select match_state,expires_at,membership_epoch,generation,current_tic
      into l_state,l_expiry,l_epoch,l_generation,p_current_tic
      from doom_match where match_id=p_match;
    if l_state<>'ACTIVE' or l_expiry<=l_now or l_generation<1 then
      fail(c_match_auth,'match unavailable');
    end if;
    l_slot:=player_capability_slot(p_match,p_player_capability);
    l_deadline:=systimestamp+numtodsinterval(p_wait_ms/1000,'SECOND');
    loop
      doom_match_worker.poll_frame(p_match,l_slot,l_epoch,l_generation,p_tic,
        p_ready,p_payload);
      exit when p_ready=1 or systimestamp>=l_deadline;
      dbms_session.sleep(.01);
    end loop;
    if p_ready=0 then
      begin
        select worker_status,heartbeat into l_worker_status,l_worker_heartbeat
          from doom_match_worker_control where match_id=p_match;
        if l_worker_status in('FAILED','STOPPED') or
           (l_worker_status='READY' and
            l_worker_heartbeat<utc_now-interval '5' second) then
          doom_match_worker.recover_match(p_match,0,l_recovery_state);
        end if;
      exception when no_data_found then null;end;
    end if;
    select current_tic into p_current_tic from doom_match
      where match_id=p_match and membership_epoch=l_epoch
        and generation=l_generation;
    l_now:=utc_now;
    update doom_match_member set member_state='ACTIVE',last_seen_at=l_now,
      disconnected_at=null
      where match_id=p_match and player_slot=l_slot
        and member_state in('ACTIVE','DISCONNECTED')
        and membership_epoch=l_epoch and generation=l_generation;
    renew_match_lease(p_match,l_now);
    commit;
  exception when no_data_found then
    rollback;p_ready:=0;p_current_tic:=null;p_payload:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;
    begin
      rollback;p_ready:=0;p_current_tic:=null;p_payload:=null;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      elsif l_code between -20999 and -20000 then
        raise_application_error(c_bad_request,'match poll rejected');
      end if;
      raise_application_error(c_bad_request,'match poll rejected');
    end;
  end;
  $end

  procedure leave_match(
    p_match in varchar2,p_player_capability in varchar2,
    p_match_state out varchar2
  ) is
    l_state varchar2(16);l_expiry timestamp with time zone;
    l_epoch number;l_generation number;l_slot number;
    l_member_state varchar2(16);l_now timestamp with time zone:=utc_now;
    l_current number;l_leave_tic number;l_request_status varchar2(16);
    l_requested_tic number;
  begin
    p_match_state:=null;require_match_shape(p_match);
    select match_state,expires_at,membership_epoch,generation
      into l_state,l_expiry,l_epoch,l_generation
      from doom_match where match_id=p_match for update;
    if l_expiry<=l_now or l_state not in('LOBBY','CANCELLED','ACTIVE','FINISHED') then
      fail(c_match_auth,'match unavailable');
    end if;
    l_slot:=player_capability_slot(p_match,p_player_capability,1);
    select member_state into l_member_state from doom_match_member
      where match_id=p_match and player_slot=l_slot;
    if l_member_state='LEFT' then
      p_match_state:=l_state;commit;return;
    end if;
    if l_state='FINISHED' then fail(c_match_auth,'match unavailable');end if;
    if l_state='ACTIVE' then
      select current_tic into l_current from doom_match where match_id=p_match;
      if l_slot=0 then
        update doom_match_member set member_state='LEFT',
          leave_tic=l_current+1,last_seen_at=l_now where match_id=p_match;
        update doom_match set match_state='FINISHED',finished_at=l_now,
          last_activity_at=l_now where match_id=p_match;
        commit;doom_match_worker.stop_match(p_match,l_generation);
        p_match_state:='FINISHED';return;
      end if;
      select request_status,requested_tic into l_request_status,l_requested_tic
        from doom_match_worker_control where match_id=p_match
          and generation=l_generation for update;
      l_leave_tic:=case when l_request_status='PROCESSING' and
        l_requested_tic=l_current+1 then l_current+2 else l_current+1 end;
      update doom_match_member set member_state='LEFT',leave_tic=l_leave_tic,
        last_seen_at=l_now where match_id=p_match and player_slot=l_slot;
      if l_leave_tic=l_current+1 then
        update doom_match_command set command_source='NEUTRAL_LEFT',
          ticcmd_raw=hextoraw('0000000000000000'),
          command_sha=lower(rawtohex(dbms_crypto.hash(
            hextoraw('0000000000000000'),dbms_crypto.hash_sh256))),
          accepted_at=l_now where match_id=p_match and player_slot=l_slot
            and tic=l_leave_tic and generation=l_generation;
      end if;
      update doom_match set last_activity_at=l_now where match_id=p_match;
      commit;p_match_state:='ACTIVE';return;
    end if;
    if l_slot=0 then
      update doom_match_member set member_state='LEFT',leave_tic=0,
        last_seen_at=l_now where match_id=p_match;
      update doom_match set match_state='CANCELLED',finished_at=l_now,
        last_activity_at=l_now where match_id=p_match;
      p_match_state:='CANCELLED';
    else
      l_epoch:=l_epoch+1;
      update doom_match set membership_epoch=l_epoch,last_activity_at=l_now
        where match_id=p_match and membership_epoch=l_epoch-1
          and generation=l_generation;
      if sql%rowcount<>1 then fail(c_match_auth,'match unavailable');end if;
      update doom_match_member set membership_epoch=l_epoch where match_id=p_match;
      update doom_match_member set member_state='LEFT',leave_tic=0,
        last_seen_at=l_now where match_id=p_match and player_slot=l_slot;
      p_match_state:='LOBBY';
    end if;
    commit;
  exception when no_data_found then
    rollback;p_match_state:=null;
    raise_application_error(c_match_auth,'match unavailable');
  when others then
    declare l_code pls_integer:=sqlcode;l_message varchar2(1800):=substr(sqlerrm,1,1800);
    begin
      rollback;p_match_state:=null;
      if l_code=c_match_auth then
        raise_application_error(c_match_auth,'match unavailable');
      end if;
      if l_code between -20999 and -20000 then
        raise_application_error(l_code,l_message);
      end if;
      raise_application_error(c_match_auth,'match unavailable');
    end;
  end;


  $if $$doom_dev_ojvm $then
  function byte_hex(p_value number) return varchar2 is
  begin
    if p_value<>trunc(p_value) or p_value not between -127 and 127 then
      fail(c_bad_request,'invalid signed-byte command');
    end if;
    return lpad(to_char(mod(p_value+256,256),'fmxx'),2,'0');
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

  -- Select the retained worker for exact gameplay and presentation ticcmds.
  -- USE is admitted only by the separately default-off split-phase gate when
  -- the SQL engine is selected; Mocha owns its native USE/pause/map/menu path.
  procedure worker_step(
    p_session in varchar2,p_commands in clob,p_async in number,p_used out number,
    p_request_out out varchar2,p_payload out blob
  ) is
    l_input_version number;l_count number;l_seq number;l_turn number;l_forward number;l_strafe number;
    l_run number;l_fire number;l_use number;l_weapon number;l_pause number;
    l_automap number;l_menu varchar2(32);l_cheat varchar2(4000);
    l_lineage varchar2(64);l_tic number;l_expected_seq number;l_fire_supported number;
    l_action_version number;
    l_deadline timestamp with time zone;
    l_heartbeat timestamp with time zone;
    l_generation number;l_ready number;l_map_sha varchar2(64);l_error varchar2(4000);
    l_request varchar2(32);l_command raw(24);l_status varchar2(16);
    l_response_generation number;l_committed_tic number;l_committed_seq number;
    l_delta_version number;l_delta_count number;l_delta_sha varchar2(64);
    l_state_sha varchar2(64);l_frame_sha varchar2(64);l_response_bytes number;
    l_response_sha varchar2(64);l_delta blob;l_worker_payload blob;
    l_pipeline_ahead number:=0;l_flags number:=0;
  begin
    p_used:=0;p_request_out:=null;p_payload:=null;
    if config_number('UNIFIED_WORKER_ENABLED',0)<>1 then
      if p_async=1 then fail(c_capacity,'retained worker is disabled');end if;
      return;
    end if;
    begin
      select json_value(p_commands,'$.v' returning number error on error)
        into l_input_version from dual;
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
    exception when others then
      if p_async=1 then fail(c_bad_request,'invalid retained command JSON');end if;
      return;
    end;
    if l_input_version not in(1,2) or
       (l_input_version=2 and config_text('GAME_ENGINE','SQL')<>'MOCHA') or
       l_count<>1 or l_seq is null or l_turn is null or l_forward is null or
       l_strafe is null or l_run is null or
       (l_input_version=1 and l_turn not in(-1,0,1)) or
       (l_input_version=2 and (l_turn<>trunc(l_turn) or l_turn not between -127 and 127 or
         l_forward<>trunc(l_forward) or l_forward not between -127 and 127 or
         l_strafe<>trunc(l_strafe) or l_strafe not between -127 and 127)) or
       (l_input_version=1 and (l_forward not in(-1,0,1) or l_strafe not in(-1,0,1))) or
       l_run not in(0,1) or
       coalesce(l_fire,0) not in(0,1) or coalesce(l_use,0) not in(0,1) or
       (coalesce(l_use,0)=1 and config_text('GAME_ENGINE','SQL')<>'MOCHA' and
        config_number('UNIFIED_WORKER_SPLIT_USE_ENABLED',0)<>1) or
       coalesce(l_weapon,0) not between 0 and 9 or
       coalesce(l_pause,0) not in(0,1) or coalesce(l_automap,0) not in(0,1) or
       coalesce(l_menu,'NONE') not in('NONE','OPTIONS') or
       coalesce(l_cheat,'') not in('','GOD','ALL','NOCLIP','FULLMAP') then
      if p_async=1 then fail(c_bad_request,'command is outside retained submit controls');end if;
      return;
    end if;
    l_flags:=coalesce(l_pause,0)+coalesce(l_automap,0)*2+
      case coalesce(l_menu,'NONE') when 'OPTIONS' then 4 else 0 end+
      case coalesce(l_cheat,'') when 'GOD' then 8 when 'ALL' then 16
        when 'NOCLIP' then 24 when 'FULLMAP' then 32 else 0 end;

    select save_lineage,current_tic,last_command_seq
      into l_lineage,l_tic,l_expected_seq from game_sessions
      where session_token=p_session;
    -- The provisional version byte is ignored by retry matching below; the
    -- final version must be selected only after pipelined predecessors commit.
    l_command:=hextoraw('444D534302010000'||u64_hex(l_seq)||byte_hex(l_turn)||
      byte_hex(l_forward)||byte_hex(l_strafe)||
      case l_run when 0 then '00' else '01' end||
      case coalesce(l_fire,0) when 0 then '00' else '01' end||
      case coalesce(l_use,0) when 0 then '00' else '01' end||
      lpad(to_char(coalesce(l_weapon,0),'fmxx'),2,'0')||
      lpad(to_char(l_flags,'fmxx'),2,'0'));
    -- A network retry can arrive after the durable frontier advanced. New and
    -- bounded-future commands cannot possibly have a committed response, so
    -- never pay the immutable BLOB lookup on their hot submit path.
    if l_seq<=l_expected_seq then
      begin
        select q.request_id,r.response_blob into l_request,l_worker_payload
          from doom_worker_request q join doom_worker_result r
            on r.request_id=q.request_id
          where q.session_token=p_session and q.save_lineage=l_lineage
            and q.expected_command_seq=l_seq-1
            and utl_raw.compare(utl_raw.substr(q.command_pack,17,8),
              utl_raw.substr(l_command,17,8))=0
            and q.request_status='COMMITTED';
        p_request_out:=l_request;p_used:=1;
        if p_async=0 then copy_blob(l_worker_payload,p_payload);end if;
        return;
      exception when no_data_found then null;end;
    end if;
    if l_seq between l_expected_seq+2 and l_expected_seq+32 then
      -- Ticcmds are keyboard state, not response-derived actions. DMSC/v3 and
      -- v4 defer READY/transition decisions to the ordered resident worker, so
      -- every live command can be queued against its deterministic future
      -- frontier without occupying an ORDS connection waiting on a predecessor.
      l_pipeline_ahead:=l_seq-l_expected_seq-1;
      l_tic:=l_tic+l_pipeline_ahead;
      l_expected_seq:=l_seq-1;
      l_action_version:=case when coalesce(l_fire,0)=1 or l_flags>0 then 4 else 3 end;
    end if;
    if l_seq<>l_expected_seq+1 then
      if p_async=1 then fail(c_capacity,'async frontier seq='||l_seq||
        ' expected='||(l_expected_seq+1));end if;
      return;
    end if;

    -- DMSC/v4 retains every catalog-defined weapon attack, including exact
    -- rocket/plasma transient projectile lifecycles and recursive splash.
    if coalesce(l_fire,0)=1 then
      select case when w.attack_kind in('HITSCAN','MELEE','PROJECTILE') then 1 else 0 end
        into l_fire_supported
        from players p join doom_weapon_def w on w.weapon_id=p.selected_weapon
        join game_sessions s on s.session_token=p.session_token and s.current_player_id=p.player_id
        where p.session_token=p_session;
      if l_fire_supported<>1 then
        if p_async=1 then fail(c_bad_request,'fire is outside retained submit controls');end if;
        return;
      end if;
    end if;

    if l_pipeline_ahead=0 then
      select /* T121_STEP_PLAN_ANCHOR */ s.current_tic,s.last_command_seq,
        case when coalesce(l_fire,0)<>0 or l_flags>0 then 4
          when coalesce(l_use,0)<>0 or coalesce(l_weapon,0)<>0 or
          p.pending_weapon is not null or p.weapon_state not like 'WEAPON_%_READY' or
          p.weapon_state_tics not in(0,1) then 3 else 2 end
        into l_tic,l_expected_seq,l_action_version
        from game_sessions s join players p
          on p.session_token=s.session_token and p.player_id=s.current_player_id
        where s.session_token=p_session;
      if l_seq<>l_expected_seq+1 then
        raise_application_error(c_capacity,'pipelined action-version frontier race');
      end if;
    end if;
    l_command:=hextoraw('444D5343'||case l_action_version when 4 then '04' when 3 then '03' else '02' end||
      '010000'||u64_hex(l_seq)||byte_hex(l_turn)||
      byte_hex(l_forward)||byte_hex(l_strafe)||
      case l_run when 0 then '00' else '01' end||
      case coalesce(l_fire,0) when 0 then '00' else '01' end||
      case coalesce(l_use,0) when 0 then '00' else '01' end||
      lpad(to_char(coalesce(l_weapon,0),'fmxx'),2,'0')||
      lpad(to_char(l_flags,'fmxx'),2,'0'));

    if p_async=1 then
      begin
        doom_worker_api.worker_status(p_session,l_generation,l_ready,l_map_sha,
          l_heartbeat,l_error);
        if l_ready<>1 then
          doom_worker_api.claim(p_session,l_generation,l_ready,l_map_sha,l_error);
        end if;
      exception when others then
        if sqlcode<>-20721 then raise;end if;
        doom_worker_api.claim(p_session,l_generation,l_ready,l_map_sha,l_error);
      end;
    else
      doom_worker_api.claim(p_session,l_generation,l_ready,l_map_sha,l_error);
    end if;
    if l_ready<>1 or l_error is not null then
      raise_application_error(c_capacity,coalesce(l_error,'worker is not ready'));
    end if;
    l_request:=lower(substr(rawtohex(dbms_crypto.hash(
      utl_i18n.string_to_raw(p_session||'|'||l_lineage||'|'||
        to_char(l_generation,'TM9')||'|'||rawtohex(l_command),'AL32UTF8'),
        dbms_crypto.hash_sh256)),1,32));
    if p_async=1 then
      doom_worker_api.submit_async(p_session,l_lineage,l_generation,l_request,
        l_tic,l_expected_seq,l_action_version,1,l_command,l_status);
    else
      for l_attempt in 1..3 loop
        doom_worker_api.step(p_session,l_lineage,l_generation,l_request,l_tic,
          l_expected_seq,l_action_version,1,l_command,
          config_number('UNIFIED_WORKER_WAIT_SECONDS',10),l_status,
          l_response_generation,l_committed_tic,l_committed_seq,l_delta_version,
          l_delta_count,l_delta_sha,l_state_sha,l_frame_sha,l_response_bytes,
          l_response_sha,l_delta,l_worker_payload,l_error);
        exit when l_status in('COMMITTED','ROLLED_BACK','FAILED');
      end loop;
    end if;
    if p_async=1 then
      if l_status not in('QUEUED','PROCESSING','COMMITTED') or l_error is not null then
        raise_application_error(c_bad_request,'worker submit failed: '||
          coalesce(l_error,l_status));
      end if;
      p_request_out:=l_request;p_used:=1;return;
    end if;
    if l_status<>'COMMITTED' or l_error is not null or
       l_response_generation<>l_generation or l_committed_tic<>l_tic+1 or
       l_committed_seq<>l_seq or l_worker_payload is null then
      raise_application_error(c_bad_request,'worker step failed: '||
        coalesce(l_error,l_status)||' generation='||coalesce(to_char(l_response_generation),'NULL')||
        '/'||to_char(l_generation)||' tic='||coalesce(to_char(l_committed_tic),'NULL')||
        '/'||to_char(l_tic+1)||' seq='||coalesce(to_char(l_committed_seq),'NULL')||
        '/'||to_char(l_seq)||' payload='||case when l_worker_payload is null then 'NULL' else 'BLOB' end);
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
    l_lineage varchar2(64);
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
    select current_tic,save_lineage,lower(game_mode),case when map_status='DONE' then 1 else 0 end
      into l_tic,l_lineage,l_mode,l_complete from game_sessions
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
      where session_token=p_session and lineage=l_lineage and tic=l_tic;

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
    l_generation number;l_ready number;l_map_sha varchar2(64);
    l_worker_error varchar2(4000);l_worker_payload blob;
    l_mocha_committed number:=0;
  begin
    p_session:=null;p_payload:=null;
    if p_skill is null or p_skill<>trunc(p_skill) or p_skill not between 1 and 5 then
      fail(c_bad_request,'skill must be an integer from 1 through 5');
    end if;

    l_now:=utc_now;
    -- Expired lineages can own hundreds of thousands of LOB-backed rows.
    -- Request-time cascade deletion made NEW_GAME block for minutes; the
    -- bounded retention worker owns cleanup outside this latency path.
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
    begin
      select sector_id into l_spawn_sector
        from table(doom_bsp_locate(l_spawn_x,l_spawn_y)) where rownum=1;
    exception when no_data_found then
      -- A cached SQL-macro cursor can retain an empty bind-sensitive plan after
      -- an OJVM-heavy session reset. Re-expanding the immutable spawn literals
      -- gives Oracle a distinct cursor while preserving the exact BSP oracle.
      select sector_id into l_spawn_sector
        from table(doom_bsp_locate(
          (select x from doom_map_thing where thing_type=1 and rownum=1),
          (select y from doom_map_thing where thing_type=1 and rownum=1)))
        where rownum=1;
    end;
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
    if config_text('GAME_ENGINE','SQL')='MOCHA' then
      -- Freeze engine identity in the durable lineage before Scheduler
      -- admission. Worker startup and every later request derive their engine
      -- path from this row, never from a mutable global selector.
      doom_mocha_bridge.create_lineage(p_session,l_lineage,p_skill,1,1);
      -- The Scheduler session cannot see the lineage until it is committed.
      -- READY is published only after that retained owner has encoded its
      -- generation-fenced current frame into DOOM_MOCHA_FRAME_CACHE.
      commit;l_mocha_committed:=1;
      doom_worker_api.claim(p_session,l_generation,l_ready,l_map_sha,l_worker_error);
      if l_ready<>1 or l_worker_error is not null then
        raise_application_error(c_capacity,
          coalesce(l_worker_error,'Mocha worker is not ready'));
      end if;
      select response_blob into l_worker_payload from doom_mocha_frame_cache
        where session_token=p_session and save_lineage=l_lineage
          and generation=l_generation and tic=0;
      copy_blob(l_worker_payload,p_payload);
      return;
    end if;
    render_payload(p_session,l_state_sha,p_payload);
    commit;
  exception when others then
    declare
      l_error_code pls_integer:=sqlcode;
      l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_payload:=null;
      if l_mocha_committed=1 and p_session is not null then
        begin doom_unified_worker.request_stop(p_session);exception when others then null;end;
        begin delete from game_sessions where session_token=p_session;commit;
        exception when others then rollback;end;
      end if;
      p_session:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,'new game failed');
    end;
  end;

  procedure step(
    p_session in varchar2,p_commands in clob,p_payload out blob
  ) is
    l_first number;l_last number;l_sha varchar2(64);l_cached blob;
    l_canonical clob;
    l_internal blob;l_state_sha varchar2(64);
    l_response_text clob;l_worker_used number;l_request varchar2(32);
  begin
    p_payload:=null;require_session(p_session);
    worker_step(p_session,p_commands,0,l_worker_used,l_request,p_payload);
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
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_payload:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,'step failed');
    end;
  end;

  procedure submit_step(
    p_session in varchar2,p_commands in clob,p_request out varchar2
  ) is
    l_used number;l_payload blob;
  begin
    p_request:=null;require_session(p_session);
    worker_step(p_session,p_commands,1,l_used,p_request,l_payload);
    if l_used<>1 or p_request is null then
      fail(c_bad_request,'command is not supported by the retained submit path');
    end if;
    commit;
  exception when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_request:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,'submit step failed');
    end;
  end;

  procedure poll_frame(
    p_session in varchar2,p_seq in number,p_wait_ms in number,
    p_ready out number,p_payload out blob
  ) is
    l_lineage varchar2(64);l_source blob;l_request varchar2(32);
    l_request_generation number;l_expected_tic number;l_expected_seq number;
    l_command_version number;l_command_count number;l_command raw(2000);
    l_created timestamp with time zone;l_generation number;l_worker_ready number;
    l_map_sha varchar2(64);l_worker_error varchar2(4000);
    l_replacement varchar2(32);l_submit_status varchar2(16);
    l_deadline timestamp with time zone;
  begin
    p_ready:=0;p_payload:=null;require_session(p_session);
    if p_seq is null or p_seq<>trunc(p_seq) or p_seq not between 1 and 999999999999 or
       p_wait_ms is null or p_wait_ms<>trunc(p_wait_ms) or
       p_wait_ms not between 0 and 1000 then
      fail(c_bad_request,'invalid frame poll');
    end if;
    select save_lineage into l_lineage from game_sessions
      where session_token=p_session;
    begin
      select request_id,generation,expected_tic,expected_command_seq,
        command_version,command_count,command_pack,created_at
        into l_request,l_request_generation,l_expected_tic,l_expected_seq,
          l_command_version,l_command_count,l_command,l_created
        from doom_worker_request
        where session_token=p_session and save_lineage=l_lineage
          and expected_command_seq=p_seq-1
          and request_status in('QUEUED','PROCESSING','COMMITTED');
    exception when no_data_found then commit;return;end;
    l_deadline:=systimestamp+numtodsinterval(p_wait_ms/1000,'SECOND');
    loop
      begin
        select /* T121_FRAME_ANCHOR */ x.response_blob into l_source
          from doom_worker_request q join doom_worker_result x
            on x.request_id=q.request_id
          where q.request_id=l_request and q.request_status='COMMITTED';
        copy_blob(l_source,p_payload);p_ready:=1;commit;return;
      exception when no_data_found then null;end;
      exit when systimestamp>=l_deadline;
      -- The retained Mocha worker normally commits in under 10 ms. A 50 ms
      -- polling quantum dominated the otherwise-correlated request and added
      -- one to two display tics of input latency. Keep the bounded waiter, but
      -- sample at 2 ms so readiness—not the sleep floor—sets response time.
      dbms_session.sleep(.002);
    end loop;
    -- A forced Scheduler stop can leave READY plus a fresh heartbeat behind.
    -- Keep the expensive data-dictionary liveness check off the hot submit
    -- path: perform it only for a correlated request that has made no progress
    -- for one second. CLAIM fences/reconstructs a dead generation. If that
    -- changes the generation, migrate the exact durable command bytes under a
    -- deterministic replacement id; concurrent polls collapse idempotently.
    if systimestamp>=l_created+numtodsinterval(1,'SECOND') then
      doom_worker_api.claim(p_session,l_generation,l_worker_ready,l_map_sha,
        l_worker_error);
      if l_worker_ready<>1 or l_worker_error is not null then
        fail(c_capacity,coalesce(l_worker_error,'worker recovery is not ready'));
      end if;
      if l_generation<>l_request_generation then
        l_replacement:=lower(substr(rawtohex(dbms_crypto.hash(
          utl_i18n.string_to_raw(p_session||'|'||l_lineage||'|'||
            to_char(l_generation,'TM9')||'|'||rawtohex(l_command),'AL32UTF8'),
          dbms_crypto.hash_sh256)),1,32));
        doom_worker_api.submit_async(p_session,l_lineage,l_generation,
          l_replacement,l_expected_tic,l_expected_seq,l_command_version,
          l_command_count,l_command,l_submit_status);
        if l_submit_status not in('QUEUED','PROCESSING','COMMITTED') then
          fail(c_capacity,'worker recovery submit failed');
        end if;
      end if;
    end if;
    commit;
  exception when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_ready:=0;p_payload:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,'poll frame failed');
    end;
  end;

  procedure save_game(
    p_session in varchar2,p_slot in number,p_state_sha out varchar2
  ) is
    l_lineage varchar2(64);l_tic number;l_rng number;l_seq number;
    l_frame_sha varchar2(64);
  begin
    p_state_sha:=null;require_session(p_session);
    if config_text('GAME_ENGINE','SQL')='MOCHA' then
      if p_slot is null or p_slot<>trunc(p_slot) or p_slot not between 0 and 99 then
        fail(c_bad_request,'save slot must be an integer from 0 through 99');
      end if;
      select save_lineage,current_tic,rng_cursor into l_lineage,l_tic,l_rng
        from game_sessions where session_token=p_session for update;
      if l_tic=0 then
        l_seq:=0;
        select state_sha,frame_sha into p_state_sha,l_frame_sha
          from doom_mocha_frame_cache where session_token=p_session
            and save_lineage=l_lineage and tic=0;
      else
        select command_seq,state_sha,frame_sha into l_seq,p_state_sha,l_frame_sha
          from doom_mocha_command where session_token=p_session
            and save_lineage=l_lineage and tic=l_tic;
      end if;
      merge into doom_mocha_save_slot d using(select p_session session_token,
        p_slot slot_number from dual) s
      on(d.session_token=s.session_token and d.slot_number=s.slot_number)
      when matched then update set d.source_lineage=l_lineage,
        d.saved_tic=l_tic,d.saved_command_seq=l_seq,d.rng_cursor=l_rng,
        d.state_sha=p_state_sha,d.frame_sha=l_frame_sha,d.saved_at=systimestamp
      when not matched then insert(session_token,slot_number,source_lineage,
        saved_tic,saved_command_seq,rng_cursor,state_sha,frame_sha)
      values(p_session,p_slot,l_lineage,l_tic,l_seq,l_rng,p_state_sha,l_frame_sha);
      commit;return;
    end if;
    doom_history.save_game(p_session,p_slot,p_state_sha);commit;
  exception when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_state_sha:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,'save failed');
    end;
  end;

  procedure load_game(
    p_session in varchar2,p_slot in number,p_payload out blob
  ) is
    l_internal blob;l_state_sha varchar2(64);
    l_source_lineage varchar2(64);l_old_lineage varchar2(64);
    l_new_lineage varchar2(64);l_frame_sha varchar2(64);
    l_saved_tic number;l_saved_seq number;l_rng number;l_frontier number;
    l_generation number;l_ready number;l_map_sha varchar2(64);
    l_worker_error varchar2(4000);l_source blob;
  begin
    p_payload:=null;require_session(p_session);
    if config_text('GAME_ENGINE','SQL')='MOCHA' then
      if p_slot is null or p_slot<>trunc(p_slot) or p_slot not between 0 and 99 then
        fail(c_bad_request,'save slot must be an integer from 0 through 99');
      end if;
      stop_worker_for_sql_fallback(p_session);
      select source_lineage,saved_tic,saved_command_seq,rng_cursor,
        state_sha,frame_sha
        into l_source_lineage,l_saved_tic,l_saved_seq,l_rng,
          l_state_sha,l_frame_sha
        from doom_mocha_save_slot where session_token=p_session
          and slot_number=p_slot;
      select save_lineage,last_command_seq into l_old_lineage,l_frontier
        from game_sessions where session_token=p_session for update;
      select lower(standard_hash('MOCHA_LOAD|'||l_old_lineage||'|'||
        to_char(l_frontier+1,'TM9','NLS_NUMERIC_CHARACTERS=''.,''')||'|'||
        to_char(p_slot,'TM9')||'|'||l_state_sha,'SHA256'))
        into l_new_lineage from dual;
      insert into doom_mocha_lineage(session_token,save_lineage,skill,episode,map,
        engine_revision,iwad_sha)
      select session_token,l_new_lineage,skill,episode,map,engine_revision,iwad_sha
        from doom_mocha_lineage where session_token=p_session
          and save_lineage=l_source_lineage;
      insert into doom_mocha_command(session_token,save_lineage,command_seq,tic,
        generation,ticcmd_raw,ticcmd_sha,state_sha,frame_sha,created_at)
      select session_token,l_new_lineage,command_seq,tic,generation,ticcmd_raw,
        ticcmd_sha,state_sha,frame_sha,created_at
        from doom_mocha_command where session_token=p_session
          and save_lineage=l_source_lineage and tic<=l_saved_tic;
      insert into doom_mocha_initial_frame(session_token,save_lineage,state_sha,
        frame_sha,response_blob)
      select session_token,l_new_lineage,state_sha,frame_sha,response_blob
        from doom_mocha_initial_frame where session_token=p_session
          and save_lineage=l_source_lineage;
      insert into doom_mocha_frame_ledger(session_token,save_lineage,
        command_seq,tic,request_id,state_sha,frame_sha,response_sha,created_at)
      select session_token,l_new_lineage,command_seq,tic,request_id,state_sha,
        frame_sha,response_sha,created_at
        from doom_mocha_frame_ledger where session_token=p_session
          and save_lineage=l_source_lineage and tic<=l_saved_tic;
      update game_sessions set save_lineage=l_new_lineage,current_tic=l_saved_tic,
        rng_cursor=l_rng where session_token=p_session
          and save_lineage=l_old_lineage and last_command_seq=l_frontier;
      if sql%rowcount<>1 then fail(c_bad_request,'load lineage race');end if;
      for l_audio in (
        select tic,event_ordinal,asset_kind,asset_name,volume,separation
          from audio_events where session_token=p_session
            and lineage=l_source_lineage and tic<=l_saved_tic
          order by tic,event_ordinal
      ) loop
        insert into audio_events(session_token,tic,event_ordinal,asset_kind,
          asset_name,volume,separation)
        values(p_session,l_audio.tic,l_audio.event_ordinal,l_audio.asset_kind,
          l_audio.asset_name,l_audio.volume,l_audio.separation);
      end loop;
      commit;
      doom_worker_api.claim(p_session,l_generation,l_ready,l_map_sha,l_worker_error);
      if l_ready<>1 or l_worker_error is not null then
        raise_application_error(c_capacity,
          coalesce(l_worker_error,'Mocha load worker is not ready'));
      end if;
      select response_blob into l_source from doom_mocha_frame_cache
        where session_token=p_session and save_lineage=l_new_lineage
          and generation=l_generation and tic=l_saved_tic;
      copy_blob(l_source,p_payload);return;
    end if;
    doom_history.load_game(p_session,p_slot,l_internal);
    l_state_sha:=json_value(blob_text(l_internal),'$.state_sha');
    render_payload(p_session,l_state_sha,p_payload);commit;
  exception when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_payload:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,'load failed');
    end;
  end;

  procedure start_replay(
    p_session in varchar2,p_from_tic in number,p_to_tic in number,
    p_replay_id out varchar2
  ) is
    l_lineage varchar2(64);l_state_sha varchar2(64);l_frame_sha varchar2(64);
    l_command_sha varchar2(64);l_count number;l_seed varchar2(4000);
    c_zero_sha constant varchar2(64) := rpad('0',64,'0');
  begin
    p_replay_id:=null;require_session(p_session);
    if config_text('GAME_ENGINE','SQL')='MOCHA' then
      if p_from_tic is null or p_to_tic is null or
         p_from_tic<>trunc(p_from_tic) or p_to_tic<>trunc(p_to_tic) or
         p_from_tic<0 or p_to_tic<p_from_tic then
        fail(c_bad_request,'invalid replay range');
      end if;
      select save_lineage into l_lineage from game_sessions
        where session_token=p_session for update;
      select count(*) into l_count from doom_mocha_command
        where session_token=p_session and save_lineage=l_lineage
          and tic>p_from_tic and tic<=p_to_tic;
      if l_count<>p_to_tic-p_from_tic then
        fail(c_bad_request,'incomplete replay range');
      end if;
      if p_from_tic=0 then
        select state_sha,frame_sha into l_state_sha,l_frame_sha
          from doom_mocha_initial_frame where session_token=p_session
            and save_lineage=l_lineage;
        l_command_sha:=c_zero_sha;
      else
        select ticcmd_sha,state_sha,frame_sha
          into l_command_sha,l_state_sha,l_frame_sha
          from doom_mocha_command where session_token=p_session
            and save_lineage=l_lineage and tic=p_from_tic;
      end if;
      select 'MOCHA_REPLAY|'||p_session||'|'||l_lineage||'|'||
        to_char(p_from_tic,'TM9')||'|'||to_char(p_to_tic,'TM9')||'|'||
        to_char(count(*)+1,'TM9') into l_seed from replay_cursors;
      select lower(substr(standard_hash(l_seed,'SHA256'),1,32))
        into p_replay_id from dual;
      insert into replay_cursors(replay_id,session_token,lineage,from_tic,
        current_tic,to_tic,command_sha,event_sha,state_sha,frame_sha,state_blob,
        completed)
      values(p_replay_id,p_session,l_lineage,p_from_tic,p_from_tic,p_to_tic,
        l_command_sha,c_zero_sha,l_state_sha,l_frame_sha,empty_blob(),
        case when p_from_tic=p_to_tic then 1 else 0 end);
      commit;return;
    end if;
    doom_history.start_replay(p_session,p_from_tic,p_to_tic,p_replay_id);commit;
  exception when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_replay_id:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,
        'replay start failed: '||l_error_message);
    end;
  end;

  procedure step_replay(p_replay_id in varchar2,p_payload out blob) is
    l_internal blob;l_source blob;l_session varchar2(32);l_lineage varchar2(64);
    l_state_sha varchar2(64);l_frame_sha varchar2(64);l_command_sha varchar2(64);
    l_current number;l_to number;l_completed number;l_mocha number;
  begin
    p_payload:=null;
    if p_replay_id is null or not regexp_like(p_replay_id,'^[0-9a-f]{32}$') then
      fail(c_bad_request,'unknown replay identifier');
    end if;
    select session_token,lineage,current_tic,to_tic,completed
      into l_session,l_lineage,l_current,l_to,l_completed from replay_cursors
      where replay_id=p_replay_id;
    require_session(l_session);
    select count(*) into l_mocha from doom_mocha_lineage
      where session_token=l_session and save_lineage=l_lineage;
    if l_mocha=1 then
      if l_completed=0 then
        select ticcmd_sha,state_sha,frame_sha
          into l_command_sha,l_state_sha,l_frame_sha
          from doom_mocha_command where session_token=l_session
            and save_lineage=l_lineage and tic=l_current+1;
        update replay_cursors set current_tic=l_current+1,
          command_sha=l_command_sha,state_sha=l_state_sha,frame_sha=l_frame_sha,
          completed=case when l_current+1=l_to then 1 else 0 end
          where replay_id=p_replay_id and current_tic=l_current;
        if sql%rowcount<>1 then fail(c_bad_request,'replay cursor race');end if;
        l_current:=l_current+1;
      end if;
      if l_current=0 then
        select response_blob into l_source from doom_mocha_initial_frame
          where session_token=l_session and save_lineage=l_lineage;
      else
        select r.response_blob into l_source from doom_mocha_frame_ledger f
          join doom_worker_result r on r.request_id=f.request_id
          where f.session_token=l_session and f.save_lineage=l_lineage
            and f.tic=l_current and r.state_sha=f.state_sha
            and r.frame_sha=f.frame_sha and r.response_sha=f.response_sha;
      end if;
      copy_blob(l_source,p_payload);commit;return;
    end if;
    doom_history.step_replay(p_replay_id,l_internal);
    l_state_sha:=json_value(blob_text(l_internal),'$.state_sha');
    render_payload(l_session,l_state_sha,p_payload);commit;
  exception when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_payload:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_bad_request,
        'replay step failed: '||l_error_message);
    end;
  end;

  $end

  procedure get_asset(
    p_asset_name in varchar2,p_payload out blob,p_media_type out varchar2
  ) is
    l_blob blob;
    l_hex clob;
  begin
    p_payload:=null;p_media_type:=null;
    if p_asset_name is null or
       (p_asset_name not in(
          'PLAYPAL','TITLEPIC','GENMIDI','M_DOOM','M_NGAME','M_OPTION',
          'M_LOADG','M_SAVEG','M_RDTHIS','M_QUITG','M_NEWG','M_SKILL',
          'M_JKILL','M_ROUGH','M_HURT','M_ULTRA','M_NMARE',
          'M_SKULL1','M_SKULL2') and
        not regexp_like(p_asset_name,'^DS[A-Z0-9]{1,6}$')) then
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
    elsif p_asset_name='TITLEPIC' then
      select xmlserialize(content xmlagg(xmlelement(e,
        lpad(to_char(t.c,'FMXX'),2,'0')) order by t.y,t.x)
        as clob no indent) into l_hex
        from at t join doom_asset a on a.asset_id=t.a
        where a.asset_kind='ui_patch' and a.asset_name='TITLEPIC';
      l_hex:=replace(replace(l_hex,'<E>',''),'</E>','');
      l_blob:=hex_blob(l_hex);
      if dbms_lob.getlength(l_blob)<>320*200 then fail(c_asset,'title asset is invalid');end if;
      p_media_type:='application/x-doom-indexed';
    elsif substr(p_asset_name,1,2)='M_' then
      select /* T121_ASSET_ANCHOR */ b.encoded_bytes,b.media_type into l_blob,p_media_type
        from doom_asset a join doom_asset_blob b on b.asset_id=a.asset_id
        where a.asset_kind='mocha_ui_patch' and a.asset_name=p_asset_name;
    else
      select b.encoded_bytes into l_blob
        from doom_asset a join doom_asset_blob b on b.asset_id=a.asset_id
        where a.asset_name=p_asset_name
          and (p_asset_name='GENMIDI' or a.asset_kind='sound');
      p_media_type:=case when substr(p_asset_name,1,2)='DS'
        then 'audio/x-doom' else 'application/octet-stream' end;
    end if;
    copy_blob(l_blob,p_payload);commit;
  exception when no_data_found then
    rollback;p_payload:=null;p_media_type:=null;
    raise_application_error(c_asset,'asset is not allowlisted');
  when others then
    declare l_error_code pls_integer:=sqlcode;l_error_message varchar2(2000):=substr(sqlerrm,1,1800);
    begin
      rollback;p_payload:=null;p_media_type:=null;
      if l_error_code between -20999 and -20000 then
        raise_application_error(l_error_code,l_error_message);
      end if;
      raise_application_error(c_asset,'asset request failed');
    end;
  end;
end doom_api;
/
