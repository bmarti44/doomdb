whenever sqlerror exit failure rollback
set define off

-- Expired lineages can own tens of thousands of command/response LOB rows.
-- Cascading them inside NEW_GAME turns ordinary admission into an unbounded
-- storage operation, so retention cleanup runs only in this Scheduler session.
create or replace package doom_session_cleanup authid definer as
  $if $$doom_dev_ojvm $then
  procedure purge_expired(p_limit in number default 4);
  $end
  procedure reap_abandoned_matches(p_limit in number default 4);
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
              begin doom_worker_lifecycle.stop_job(
                l_job,true,'expired session cleanup');
              exception when others then null;end;
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

  -- Browser unload delivery is best-effort. Reconcile a match whose host has
  -- stopped all authenticated presence traffic without waiting for its
  -- twenty-minute idle lease. Fifteen seconds preserves bounded network/tab
  -- suspension recovery while preventing a dead browser from retaining the
  -- Free-tier game slot indefinitely.
  procedure reap_abandoned_matches(p_limit in number default 4) is
    l_limit pls_integer:=least(8,greatest(1,trunc(coalesce(p_limit,4))));
    l_now timestamp with time zone:=localtimestamp at time zone 'UTC';
    l_state varchar2(16);l_generation number;l_current_tic number;
  begin
    for abandoned_ in (
      select m.match_id
      from doom_match m
      join doom_match_member host_
        on host_.match_id=m.match_id and host_.player_slot=0
      where m.match_state in('LOBBY','ACTIVE')
        and (host_.member_state='LEFT' or host_.last_seen_at<
          l_now-numtodsinterval(15,'SECOND'))
      order by host_.last_seen_at
      fetch first l_limit rows only
    ) loop
      begin
        select m.match_state,m.generation,m.current_tic
          into l_state,l_generation,l_current_tic
          from doom_match m
          where m.match_id=abandoned_.match_id
            and m.match_state in('LOBBY','ACTIVE')
            and exists(
              select 1 from doom_match_member host_
              where host_.match_id=m.match_id and host_.player_slot=0
                and (host_.member_state='LEFT' or host_.last_seen_at<
                  l_now-numtodsinterval(15,'SECOND')))
          for update skip locked;
      exception when no_data_found then continue;end;
      update doom_match_member set member_state='LEFT',
        leave_tic=case when l_state='ACTIVE'
          then l_current_tic+1 else 0 end,
        disconnected_at=coalesce(disconnected_at,l_now),last_seen_at=l_now
        where match_id=abandoned_.match_id and player_slot=0
          and member_state<>'LEFT';
      update doom_match set
        match_state=case l_state
          when 'ACTIVE' then 'FINISHED' else 'CANCELLED' end,
        finished_at=l_now,last_activity_at=l_now,expires_at=l_now
        where match_id=abandoned_.match_id
          and match_state=l_state and generation=l_generation;
      update doom_match_worker_control set stop_requested=1,heartbeat=l_now
        where match_id=abandoned_.match_id;
      update doom_match_standby_control set stop_requested=1,heartbeat=l_now
        where match_id=abandoned_.match_id
          and standby_status in('STARTING','READY');
    end loop;
    commit;
  end reap_abandoned_matches;

  procedure purge_expired_matches(p_limit in number default 4) is
    l_limit pls_integer:=least(8,greatest(1,trunc(coalesce(p_limit,4))));
    l_job varchar2(64);l_generation number;l_assigned number;
    l_deadline timestamp with time zone;
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
          if l_job like 'DOOM_MLE_WARM\_%' escape '\' then
            -- Warm Scheduler jobs are retained pool infrastructure, never
            -- match-owned resources. Wait for both assigned contexts to honor
            -- STOP_REQUESTED and recycle before deleting the match lineage.
            -- Dropping this job destroys capacity for every later game.
            l_deadline:=systimestamp+numtodsinterval(10,'SECOND');
            loop
              select count(*) into l_assigned from doom_mle_warm_slot
                where assigned_match=expired_.match_id
                  and slot_status in('CLAIMED','RUNNING');
              exit when l_assigned=0 or systimestamp>=l_deadline;
              dbms_session.sleep(.1);
            end loop;
            if l_assigned<>0 then
              rollback;
              continue;
            end if;
          else
            dbms_session.sleep(.1);
            begin dbms_scheduler.drop_job(l_job,true);
            exception when others then null;end;
          end if;
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
    job_action=>'begin doom_session_cleanup.purge_expired(4); doom_session_cleanup.reap_abandoned_matches(4); doom_session_cleanup.purge_expired_matches(4); end;',
    $else
    job_action=>'begin doom_session_cleanup.reap_abandoned_matches(4); doom_session_cleanup.purge_expired_matches(4); end;',
    $end
    start_date=>systimestamp+numtodsinterval(1,'MINUTE'),
    repeat_interval=>'FREQ=MINUTELY;INTERVAL=1',
    enabled=>true,auto_drop=>false);
end;
/

commit;
