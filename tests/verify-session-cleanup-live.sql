whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_session varchar2(32);l_payload blob;l_slot number;l_count number;
  l_lineage varchar2(64);l_map_sha varchar2(64);l_job varchar2(30);
begin
  doom_api.new_game(3,l_session,l_payload);
  select worker_slot,target_lineage,state_map_sha
    into l_slot,l_lineage,l_map_sha from doom_worker_control
    where target_session=l_session;
  l_job:='DOOM_UNIFIED_WORKER_'||to_char(l_slot,'FM00');
  begin doom_worker_lifecycle.stop_job(
    l_job,true,'session cleanup orphan fixture');
  exception when others then null;end;
  -- Recreate the exact failure shape: the Scheduler session is absent but its
  -- fenced owner row survived, so the ordinary graceful stop has no consumer.
  update doom_worker_control set ready=0,standby=0,stop_requested=0,
    worker_sid=null,target_session=l_session,target_lineage=l_lineage,
    state_map_sha=l_map_sha,heartbeat=systimestamp-interval '2' minute
    where worker_slot=l_slot;
  update game_sessions set expires_at=systimestamp-interval '1' second
    where session_token=l_session;
  commit;
  doom_session_cleanup.purge_expired(1);
  select count(*) into l_count from game_sessions where session_token=l_session;
  if l_count<>0 then raise_application_error(-20000,'stale expired session not purged');end if;
  select count(*) into l_count from doom_worker_control
    where target_session=l_session;
  if l_count<>0 then raise_application_error(-20000,'stale worker owner not reclaimed');end if;
  dbms_output.put_line('PASS SESSION-CLEANUP-LIVE stale single-player owner reclaimed');
exception when others then
  rollback;
  if l_session is not null then
    update doom_worker_control set ready=0,standby=0,stop_requested=0,
      worker_sid=null,target_session=null,target_lineage=null,state_map_sha=null
      where target_session=l_session;
    delete from game_sessions where session_token=l_session;commit;
  end if;
  raise;
end;
/

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_player varchar2(64);l_count number;
begin
  doom_api.create_match('COOP',3,1,1,'PURGE FIXTURE',l_match,l_host,l_join,l_player);
  update doom_match set created_at=created_at-interval '30' minute,
    last_activity_at=last_activity_at-interval '30' minute,
    expires_at=systimestamp-interval '1' second
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
