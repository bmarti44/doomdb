whenever sqlerror exit failure rollback
set define off

create or replace package doom_mle_transition_transport authid definer as
  -- DMB1 v1 contract: at most four held polls in the six-session ORDS pool;
  -- two sessions are always reserved for input and recovery/control traffic.
  c_pool_sessions constant pls_integer:=6;
  c_pool_reserve constant pls_integer:=2;
  c_max_held_polls constant pls_integer:=4;
  -- Oracle Free enforces two runnable PDB sessions at the pinned 50% cap.
  -- Reserve one for the retained ticker/input path. Held DBMS_ALERT waits do
  -- not consume this budget, but only one prompt-return path is guaranteed to
  -- become runnable without competing with authority work.
  c_resmgr_running_sessions constant pls_integer:=2;
  c_resmgr_worker_reserve constant pls_integer:=1;
  c_max_concurrent_poll_returns constant pls_integer:=1;
  c_max_batch_transitions constant pls_integer:=64;
  c_max_hold_ms constant pls_integer:=500;

  procedure publish(p_match in varchar2,p_payload in raw);

  procedure poll_batch(
    p_match in varchar2,
    p_player_slot in number,
    p_membership_epoch in number,
    p_generation in number,
    p_after_tic in number,
    p_max_transitions in number,
    p_hold_ms in number,
    p_ready out number,
    p_payload out blob);
end doom_mle_transition_transport;
/

create or replace package body doom_mle_transition_transport as
  c_error constant pls_integer:=-20798;

  function utc_now return timestamp with time zone is
  begin return localtimestamp at time zone 'UTC';end;

  function u32(p_value number) return raw deterministic is
  begin
    if p_value is null or p_value<0 or p_value>2147483647 or
       p_value<>trunc(p_value) then
      raise_application_error(c_error,'DMB1 uint32 value');
    end if;
    return utl_raw.cast_from_binary_integer(p_value,utl_raw.big_endian);
  end;

  function u16(p_value number) return raw deterministic is
  begin
    if p_value is null or p_value<0 or p_value>65535 or
       p_value<>trunc(p_value) then
      raise_application_error(c_error,'DMB1 uint16 value');
    end if;
    return utl_raw.substr(u32(p_value),3,2);
  end;

  function read_u32(p_raw raw,p_offset pls_integer) return number deterministic is
  begin
    return utl_raw.cast_to_binary_integer(
      utl_raw.substr(p_raw,p_offset,4),utl_raw.big_endian);
  end;

  function alert_name(p_match varchar2) return varchar2 deterministic is
  begin
    return 'DOOM_DMD1_'||substr(lower(rawtohex(dbms_crypto.hash(
      utl_i18n.string_to_raw(p_match,'AL32UTF8'),dbms_crypto.hash_sh256))),1,20);
  end;

  function elapsed_ms(p_started timestamp with time zone) return number is
    l_value interval day to second:=utc_now-p_started;
  begin
    return greatest(0,round(extract(day from l_value)*86400000+
      extract(hour from l_value)*3600000+extract(minute from l_value)*60000+
      extract(second from l_value)*1000));
  end;

  procedure append_raw(p_blob in out nocopy blob,p_raw raw) is
  begin dbms_lob.writeappend(p_blob,utl_raw.length(p_raw),p_raw);end;

  procedure publish(p_match in varchar2,p_payload in raw) is
    l_tic number;l_generation number;l_epoch number;l_length pls_integer;
    l_previous varchar2(64);l_chain varchar2(64);l_actual raw(32);l_blob blob;
    l_now timestamp with time zone:=utc_now;
    l_long_poll number;
  begin
    l_length:=utl_raw.length(p_payload);
    if l_length<150 or utl_raw.cast_to_varchar2(utl_raw.substr(p_payload,1,4))<>'DMD1' then
      raise_application_error(c_error,'DMD1 payload');
    end if;
    l_tic:=read_u32(p_payload,5);l_generation:=read_u32(p_payload,9);
    l_epoch:=read_u32(p_payload,13);
    l_previous:=lower(rawtohex(utl_raw.substr(p_payload,21,32)));
    l_chain:=lower(rawtohex(utl_raw.substr(p_payload,53,32)));
    l_actual:=dbms_crypto.hash(utl_raw.concat(
      utl_raw.substr(p_payload,1,52),utl_raw.substr(p_payload,85)),
      dbms_crypto.hash_sh256);
    if l_chain<>lower(rawtohex(l_actual)) then
      raise_application_error(c_error,'DMD1 chain');
    end if;
    insert into doom_match_transition(match_id,tic,membership_epoch,generation,
      previous_chain_sha,chain_sha,payload_bytes,payload_blob,committed_at)
    values(p_match,l_tic,l_epoch,l_generation,l_previous,l_chain,l_length,
      empty_blob(),l_now) returning payload_blob into l_blob;
    append_raw(l_blob,p_payload);
    -- DBMS_ALERT signals become visible only with the publishing transaction's
    -- commit, exactly matching the authoritative frontier visibility point.
    select long_poll_enabled into l_long_poll from doom_match_poll_capacity
      where capacity_id=1;
    if l_long_poll=1 then
      dbms_alert.signal(alert_name(p_match),to_char(l_tic,'FM999999999999'));
    end if;
  end;

  procedure poll_batch(
    p_match in varchar2,p_player_slot in number,p_membership_epoch in number,
    p_generation in number,p_after_tic in number,p_max_transitions in number,
    p_hold_ms in number,p_ready out number,p_payload out blob
  ) is
    l_max pls_integer;l_hold pls_integer;l_token raw(16):=sys_guid();
    l_started timestamp with time zone:=utc_now;l_now timestamp with time zone;
    l_frontier number;l_count number;l_last number;l_flags pls_integer:=0;
    l_alert varchar2(64):=alert_name(p_match);l_message varchar2(1800);
    l_status integer;l_remaining number;l_header raw(32);l_expected number;
    l_generation number;l_epoch number;l_capacity number;l_held number;
    l_long_poll number;
  begin
    p_ready:=0;p_payload:=null;
    if p_player_slot is null or p_player_slot<>trunc(p_player_slot) or
       p_player_slot not between 0 and 3 or p_after_tic is null or
       p_after_tic<>trunc(p_after_tic) or p_after_tic<0 then
      raise_application_error(c_error,'DMB1 request fence');
    end if;
    l_max:=least(greatest(coalesce(p_max_transitions,32),1),c_max_batch_transitions);
    l_hold:=least(greatest(coalesce(p_hold_ms,0),0),c_max_hold_ms);
    select m.generation,m.membership_epoch,m.current_tic
      into l_generation,l_epoch,l_frontier
      from doom_match m join doom_match_member member_
        on member_.match_id=m.match_id and member_.player_slot=p_player_slot
      where m.match_id=p_match and m.match_state='ACTIVE'
        and m.generation=p_generation and m.membership_epoch=p_membership_epoch
        and member_.generation=p_generation
        and member_.membership_epoch=p_membership_epoch;
    if l_generation<>p_generation or l_epoch<>p_membership_epoch or
       p_after_tic>l_frontier then
      raise_application_error(c_error,'DMB1 frontier changed');
    end if;

    begin
      select max_held_polls,long_poll_enabled into l_capacity,l_long_poll
        from doom_match_poll_capacity
        where capacity_id=1 for update;
      if l_long_poll=0 then l_hold:=0;end if;
      l_now:=utc_now;
      delete from doom_match_poll_lease where expires_at<=l_now;
      select count(*) into l_held from doom_match_poll_lease;
      if l_held>=l_capacity then
        raise_application_error(c_error,'held poll capacity reserved');
      end if;
      insert into doom_match_poll_lease(match_id,player_slot,membership_epoch,
        generation,poll_token,started_at,expires_at)
      values(p_match,p_player_slot,p_membership_epoch,p_generation,l_token,l_started,
        l_started+numtodsinterval((l_hold+1000)/1000,'SECOND'));
      commit;
    exception when dup_val_on_index then
      rollback;raise_application_error(c_error,'one outstanding poll per player');
    end;

    -- Immediate batching is the Free-edition fallback. Registering/removing an
    -- alert for a zero-hold request needlessly takes UL locks and contends with
    -- the authority worker's per-tic SIGNAL, collapsing ticker throughput.
    if l_hold>0 then dbms_alert.register(l_alert);end if;
    loop
      select generation,membership_epoch,current_tic
        into l_generation,l_epoch,l_frontier from doom_match
        where match_id=p_match and match_state='ACTIVE';
      if l_generation<>p_generation or l_epoch<>p_membership_epoch or
         l_frontier<p_after_tic then
        raise_application_error(c_error,'DMB1 frontier changed');
      end if;
      select count(*),max(tic) into l_count,l_last from (
        select tic from doom_match_transition where match_id=p_match
          and membership_epoch=p_membership_epoch and tic>p_after_tic
          and tic<=l_frontier
          order by tic
      ) where rownum<=l_max;
      exit when l_count>0 or elapsed_ms(l_started)>=l_hold;
      l_remaining:=greatest(0,(l_hold-elapsed_ms(l_started))/1000);
      dbms_alert.waitone(l_alert,l_message,l_status,l_remaining);
    end loop;

    if l_count=0 then
      l_flags:=1;l_last:=p_after_tic;
      if l_frontier>p_after_tic then
        raise_application_error(c_error,'DMB1 committed transition gap');
      end if;
    elsif l_frontier>l_last then l_flags:=2;
    end if;
    l_header:=utl_raw.concat(utl_raw.cast_to_raw('DMB1'),u16(1),u16(l_flags),
      u16(l_count),u16(0),u32(p_generation),u32(p_membership_epoch),
      u32(p_after_tic),u32(l_frontier),u32(least(elapsed_ms(l_started),2147483647)));
    dbms_lob.createtemporary(p_payload,true,dbms_lob.call);append_raw(p_payload,l_header);
    l_expected:=p_after_tic+1;
    for transition_ in (
      select tic,payload_bytes,payload_blob from (
        select tic,payload_bytes,payload_blob from doom_match_transition
          where match_id=p_match and membership_epoch=p_membership_epoch
            and tic>p_after_tic and tic<=l_frontier order by tic
      ) where rownum<=l_max order by tic
    ) loop
      if transition_.tic<>l_expected or
         transition_.payload_bytes<>dbms_lob.getlength(transition_.payload_blob) then
        raise_application_error(c_error,'DMB1 transition sequence');
      end if;
      append_raw(p_payload,u32(transition_.payload_bytes));
      dbms_lob.append(p_payload,transition_.payload_blob);l_expected:=l_expected+1;
    end loop;
    p_ready:=case when l_count>0 then 1 else 0 end;
    if l_hold>0 then dbms_alert.remove(l_alert);end if;
    delete from doom_match_poll_lease where match_id=p_match
      and player_slot=p_player_slot and poll_token=l_token;
    commit;
  exception when others then
    if l_hold>0 then
      begin dbms_alert.remove(l_alert);exception when others then null;end;
    end if;
    begin
      delete from doom_match_poll_lease where match_id=p_match
        and player_slot=p_player_slot and poll_token=l_token;
      commit;
    exception when others then rollback;end;
    raise;
  end;
end doom_mle_transition_transport;
/
