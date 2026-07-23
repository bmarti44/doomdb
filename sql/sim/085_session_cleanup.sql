whenever sqlerror exit failure rollback
set define off

-- Expired lineages can own tens of thousands of command/response LOB rows.
-- Cascading them inside NEW_GAME turns ordinary admission into an unbounded
-- storage operation, so retention cleanup runs only in this Scheduler session.
create or replace package doom_session_cleanup authid definer as
  $if $$doom_dev_ojvm $then
  procedure purge_expired(p_limit in number default 4);
  $end
  procedure purge_expired_matches(p_limit in number default 4);
end doom_session_cleanup;
/

create or replace package body doom_session_cleanup as
  $if $$doom_dev_ojvm $then
  procedure purge_expired(p_limit in number default 4) is
    l_limit pls_integer:=least(8,greatest(1,trunc(coalesce(p_limit,4))));
    l_deadline timestamp with time zone;l_active number;l_running number;
    l_job varchar2(30);
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
        -- A Scheduler session can disappear before RUN_SLOT reaches its
        -- catch-all. REQUEST_STOP then has nobody left to clear ownership and
        -- the expired lineage would pin this slot forever. After the bounded
        -- graceful-stop fence, force-stop any surviving expired owner and
        -- reclaim only rows whose Scheduler job is confirmed absent.
        if l_active<>0 then
          for worker_ in (
            select worker_slot from doom_worker_control
            where target_session=expired_.session_token
            for update skip locked
          ) loop
            l_job:='DOOM_UNIFIED_WORKER_'||to_char(worker_.worker_slot,'FM00');
            select count(*) into l_running from user_scheduler_running_jobs
              where job_name=l_job;
            if l_running<>0 then
              begin dbms_scheduler.stop_job(l_job,true);exception when others then null;end;
              select count(*) into l_running from user_scheduler_running_jobs
                where job_name=l_job;
            end if;
            if l_running=0 then
              update doom_worker_request set request_status='FAILED',
                error_text='expired worker owner reclaimed',completed_at=systimestamp
                where worker_slot=worker_.worker_slot
                  and request_status in('QUEUED','PROCESSING');
              update doom_worker_control set ready=0,standby=0,stop_requested=0,
                worker_sid=null,target_session=null,target_lineage=null,
                state_map_sha=null,last_error='expired owner reclaimed',
                heartbeat=systimestamp
                where worker_slot=worker_.worker_slot
                  and target_session=expired_.session_token;
            end if;
          end loop;
          select count(*) into l_active from doom_worker_control
            where target_session=expired_.session_token;
        end if;
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
  $end

  procedure purge_expired_matches(p_limit in number default 4) is
    l_limit pls_integer:=least(8,greatest(1,trunc(coalesce(p_limit,4))));
    l_job varchar2(64);l_generation number;
  begin
    for expired_ in (
      select match_id from doom_match
      where expires_at<=(localtimestamp at time zone 'UTC')
      order by expires_at fetch first l_limit rows only
    ) loop
      begin
        begin
          select job_name,generation into l_job,l_generation
            from doom_match_worker_control where match_id=expired_.match_id;
          begin doom_match_worker.stop_match(expired_.match_id,l_generation);
          exception when others then null;end;
          dbms_session.sleep(.1);
          begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
        exception when no_data_found then null;end;
        delete from doom_match where match_id=expired_.match_id
          and expires_at<=(localtimestamp at time zone 'UTC');
        commit;
      exception when others then rollback;
      end;
    end loop;
  end purge_expired_matches;
end doom_session_cleanup;
/

begin
  begin dbms_scheduler.drop_job('DOOM_EXPIRED_SESSION_PURGE',true);
  exception when others then if sqlcode<>-27475 then raise;end if;end;
  dbms_scheduler.create_job(
    job_name=>'DOOM_EXPIRED_SESSION_PURGE',
    job_type=>'PLSQL_BLOCK',
    $if $$doom_dev_ojvm $then
    job_action=>'begin doom_session_cleanup.purge_expired(4); doom_session_cleanup.purge_expired_matches(4); end;',
    $else
    job_action=>'begin doom_session_cleanup.purge_expired_matches(4); end;',
    $end
    start_date=>systimestamp+numtodsinterval(1,'MINUTE'),
    repeat_interval=>'FREQ=MINUTELY;INTERVAL=1',
    enabled=>true,auto_drop=>false);
end;
/

commit;
