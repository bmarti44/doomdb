whenever sqlerror exit failure rollback
set define off

-- Expired lineages can own tens of thousands of command/response LOB rows.
-- Cascading them inside NEW_GAME turns ordinary admission into an unbounded
-- storage operation, so retention cleanup runs only in this Scheduler session.
create or replace package doom_session_cleanup authid definer as
  procedure purge_expired(p_limit in number default 2);
end doom_session_cleanup;
/

create or replace package body doom_session_cleanup as
  procedure purge_expired(p_limit in number default 2) is
    l_limit pls_integer:=least(8,greatest(1,trunc(coalesce(p_limit,2))));
    l_deadline timestamp with time zone;l_active number;
  begin
    for expired_ in (
      select session_token from game_sessions
      where expires_at<=(localtimestamp at time zone 'UTC')
      order by expires_at fetch first l_limit rows only
    ) loop
      begin
        begin
          doom_unified_worker.request_stop(expired_.session_token);
        exception when others then null;
        end;
        l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
        loop
          select count(*) into l_active from doom_worker_control
            where target_session=expired_.session_token;
          exit when l_active=0 or systimestamp>=l_deadline;
          dbms_session.sleep(.1);
        end loop;
        if l_active=0 then
          delete from game_sessions where session_token=expired_.session_token
            and expires_at<=(localtimestamp at time zone 'UTC');
          commit;
        else
          rollback;
        end if;
      exception when others then
        rollback;
      end;
    end loop;
  end purge_expired;
end doom_session_cleanup;
/

begin
  begin dbms_scheduler.drop_job('DOOM_EXPIRED_SESSION_PURGE',true);
  exception when others then if sqlcode<>-27475 then raise;end if;end;
  dbms_scheduler.create_job(
    job_name=>'DOOM_EXPIRED_SESSION_PURGE',
    job_type=>'PLSQL_BLOCK',
    job_action=>'begin doom_session_cleanup.purge_expired(2); end;',
    start_date=>systimestamp+numtodsinterval(10,'MINUTE'),
    repeat_interval=>'FREQ=MINUTELY;INTERVAL=10',
    enabled=>true,auto_drop=>false);
end;
/

commit;
