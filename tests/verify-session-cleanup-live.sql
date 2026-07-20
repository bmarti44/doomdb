whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

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
