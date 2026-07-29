whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_player varchar2(64);l_state varchar2(16);l_expiry timestamp with time zone;
begin
  doom_api.create_match(
    'COOP',3,1,1,'ABANDONED LOBBY',l_match,l_host,l_join,l_player);
  update doom_match_member set
    joined_at=joined_at-interval '16' second,
    last_seen_at=last_seen_at-interval '16' second
    where match_id=l_match and player_slot=0;
  commit;
  doom_session_cleanup.reap_abandoned_matches(1);
  select match_state,expires_at into l_state,l_expiry from doom_match
    where match_id=l_match;
  if l_state<>'CANCELLED' or l_expiry>systimestamp then
    raise_application_error(-20000,'abandoned lobby retained capacity');
  end if;
  dbms_output.put_line(
    'PASS SESSION-CLEANUP-LIVE abandoned browser lobby releases capacity');
exception when others then
  rollback;
  if l_match is not null then delete from doom_match where match_id=l_match;commit;end if;
  raise;
end;
/

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_player varchar2(64);l_state varchar2(16);l_generation number;
  l_tic number;l_slot number;l_assigned number;l_ready number;
  l_stop number;l_deadline timestamp with time zone;
  procedure cleanup_ is
  begin
    if l_match is null then return;end if;
    begin
      select generation into l_generation from doom_match_worker_control
        where match_id=l_match;
      doom_match_worker.stop_match(l_match,l_generation);
    exception when no_data_found then null;end;
    l_deadline:=systimestamp+numtodsinterval(90,'SECOND');
    loop
      select count(*) into l_assigned from doom_mle_warm_slot
        where assigned_match=l_match;
      exit when l_assigned=0 or systimestamp>=l_deadline;
      dbms_session.sleep(.1);
    end loop;
    if l_assigned=0 then delete from doom_match where match_id=l_match;commit;end if;
  exception when others then rollback;
  end;
begin
  doom_api.create_match(
    'COOP',3,1,1,'ABANDONED ACTIVE',l_match,l_host,l_join,l_player,1);
  doom_api.ready_match(l_match,l_player,1,l_state);
  l_deadline:=systimestamp+numtodsinterval(180,'SECOND');
  loop
    select match_state,generation,current_tic
      into l_state,l_generation,l_tic from doom_match where match_id=l_match;
    exit when l_state='ACTIVE';
    if l_state in('FAILED','CANCELLED','TERMINATED')
        or systimestamp>=l_deadline then
      raise_application_error(-20000,'active abandonment setup failed '||l_state);
    end if;
    dbms_session.sleep(.1);
  end loop;
  select slot_id into l_slot from doom_mle_warm_slot
    where assigned_match=l_match and assigned_role='AUTHORITY'
      and slot_status='RUNNING';
  update doom_match_member set
    joined_at=joined_at-interval '16' second,
    ready_at=ready_at-interval '16' second,
    last_seen_at=last_seen_at-interval '16' second
    where match_id=l_match and player_slot=0;
  commit;
  doom_session_cleanup.reap_abandoned_matches(1);
  select match_state into l_state from doom_match where match_id=l_match;
  select stop_requested into l_stop from doom_match_worker_control
    where match_id=l_match;
  if l_state<>'FINISHED' or l_stop<>1 then
    raise_application_error(-20000,
      'abandoned active match retained state/worker '||l_state||'/'||l_stop);
  end if;
  l_deadline:=systimestamp+numtodsinterval(90,'SECOND');
  loop
    select count(*) into l_assigned from doom_mle_warm_slot
      where assigned_match=l_match;
    exit when l_assigned=0 or systimestamp>=l_deadline;
    dbms_session.sleep(.1);
  end loop;
  if l_assigned<>0 then
    raise_application_error(-20000,'abandoned active match retained slot');
  end if;
  select count(*) into l_ready from doom_mle_warm_slot
    where slot_id=l_slot and slot_status='READY' and assigned_match is null;
  if l_ready<>1 then
    raise_application_error(-20000,'abandoned active slot was not reusable');
  end if;
  delete from doom_match where match_id=l_match;commit;l_match:=null;
  dbms_output.put_line(
    'PASS SESSION-CLEANUP-LIVE abandoned active browser releases retained slot');
exception when others then rollback;cleanup_;raise;
end;
/

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_player varchar2(64);l_count number;
begin
  doom_api.create_match('COOP',3,1,1,'PURGE FIXTURE',l_match,l_host,l_join,l_player);
  update doom_match set
    created_at=to_timestamp_tz(
      '1969-12-31 23:59:58 UTC','YYYY-MM-DD HH24:MI:SS TZR'),
    last_activity_at=to_timestamp_tz(
      '1969-12-31 23:59:59 UTC','YYYY-MM-DD HH24:MI:SS TZR'),
    -- PURGE_EXPIRED_MATCHES is deliberately bounded and oldest-first. Make
    -- this fixture unambiguously first even if a concurrent diagnostic leaves
    -- another expired lineage between setup and the call.
    expires_at=to_timestamp_tz(
      '1970-01-01 00:00:00 UTC','YYYY-MM-DD HH24:MI:SS TZR')
    where match_id=l_match;
  commit;
  doom_session_cleanup.purge_expired_matches(1);
  select count(*) into l_count from doom_match where match_id=l_match;
  if l_count<>0 then raise_application_error(-20000,'expired match not purged');end if;
  dbms_output.put_line('PASS SESSION-CLEANUP-LIVE expired match cascade purged off request path');
exception when others then
  rollback;
  if l_match is not null then delete from doom_match where match_id=l_match;commit;end if;
  raise;
end;
/
