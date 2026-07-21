whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  l_match varchar2(32);l_host varchar2(64);l_join varchar2(64);
  l_p0 varchar2(64);l_p1 varchar2(64);l_state varchar2(32);l_slot number;
  l_mode varchar2(16);l_worker_mode varchar2(16);l_skill number;l_episode number;
  l_map number;l_max number;l_members number;l_ready number;l_requester number;
  l_epoch number;l_generation number;l_tic number;l_job varchar2(64);
  procedure cleanup_ is
  begin
    if l_match is null then return;end if;
    begin
      select job_name,generation into l_job,l_generation
        from doom_match_worker_control where match_id=l_match;
      doom_match_worker.stop_match(l_match,l_generation);dbms_session.sleep(.2);
      begin dbms_scheduler.drop_job(l_job,true);exception when others then null;end;
    exception when no_data_found then null;end;
    delete from doom_match where match_id=l_match;commit;
  end;
begin
  doom_api.create_match('COOP',3,1,1,'STAGE HOST',l_match,l_host,l_join,l_p0);
  l_p1:=null;doom_api.join_match(l_match,l_join,'STAGE GUEST',l_p1,l_slot);
  doom_api.ready_match(l_match,l_p0,1,l_state);
  doom_api.ready_match(l_match,l_p1,1,l_state);
  for i in 1..1800 loop
    doom_api.match_status(l_match,l_host,l_state,l_mode,l_skill,l_episode,l_map,
      l_max,l_members,l_ready,l_requester,l_epoch,l_generation,l_tic,l_worker_mode);
    exit when l_state='ACTIVE';dbms_session.sleep(.1);
  end loop;
  if l_state<>'ACTIVE' or l_worker_mode<>'PACED_INPUT' then
    raise_application_error(-20000,'paced diagnostic did not start');end if;
  update doom_match_worker_control set route_diagnostics=1 where match_id=l_match;
  commit;
  for i in 1..6000 loop
    select current_tic into l_tic from doom_match where match_id=l_match;
    exit when l_tic>=400;dbms_session.sleep(.01);
  end loop;
  select job_name,generation into l_job,l_generation
    from doom_match_worker_control where match_id=l_match;
  doom_match_worker.stop_match(l_match,l_generation);dbms_session.sleep(.2);
  for metric_ in (
    with samples as (
      select t.tic,
        extract(second from(cast(t.committed_at as timestamp)-
          cast(t.deadline_at as timestamp)))*1000 total_ms,
        to_number(regexp_substr(r.route_status,'sqlToJavaMicros=([0-9]+)',1,1,null,1))/1000 pre_java_ms,
        to_number(regexp_substr(r.route_status,'javaMicros=([0-9]+)',1,1,null,1))/1000 java_ms,
        to_number(regexp_substr(r.route_status,'sqlAfterJavaMicros=([0-9]+)',1,1,null,1))/1000 post_java_ms,
        to_number(regexp_substr(r.route_status,'frameRowsMicros=([0-9]+)',1,1,null,1))/1000 frame_rows_ms,
        to_number(regexp_substr(r.route_status,'frameFinalizeMicros=([0-9]+)',1,1,null,1))/1000 frame_finalize_ms,
        to_number(regexp_substr(r.route_status,'ledgerMicros=([0-9]+)',1,1,null,1))/1000 ledger_ms,
        to_number(regexp_substr(r.route_status,'retirementMicros=([0-9]+)',1,1,null,1))/1000 retirement_ms,
        to_number(regexp_substr(r.route_status,'frontierMicros=([0-9]+)',1,1,null,1))/1000 frontier_ms,
        to_number(regexp_substr(r.route_status,'commitMicros=([0-9]+)',1,1,null,1))/1000 commit_ms,
        (to_number(regexp_substr(r.route_status,'sqlToJavaMicros=([0-9]+)',1,1,null,1))+
         to_number(regexp_substr(r.route_status,'javaMicros=([0-9]+)',1,1,null,1))+
         to_number(regexp_substr(r.route_status,'sqlAfterJavaMicros=([0-9]+)',1,1,null,1))+
         to_number(regexp_substr(r.route_status,'commitMicros=([0-9]+)',1,1,null,1)))/1000 instrumented_ms
      from doom_match_tic t join doom_match_route_trace r
        on r.match_id=t.match_id and r.tic=t.tic
      where t.match_id=l_match and t.tic>64
    ), metrics as (
      select 'PRE_JAVA' metric,pre_java_ms value from samples union all
      select 'JAVA',java_ms from samples union all
      select 'POST_JAVA',post_java_ms from samples union all
      select 'FRAME_ROWS',frame_rows_ms from samples union all
      select 'FRAME_FINALIZE',frame_finalize_ms from samples union all
      select 'LEDGER_CHECKPOINT',ledger_ms from samples union all
      select 'RETIREMENT',retirement_ms from samples union all
      select 'FRONTIER',frontier_ms from samples union all
      select 'COMMIT',commit_ms from samples union all
      select 'INSTRUMENTED_TOTAL',instrumented_ms from samples union all
      select 'PRECOMMIT_TOTAL',total_ms from samples
    )
    select metric,count(*) samples,round(avg(value),3) average_ms,
      round(percentile_cont(.5)within group(order by value),3) p50_ms,
      round(percentile_cont(.95)within group(order by value),3) p95_ms,
      round(max(value),3) max_ms from metrics group by metric order by metric
  ) loop
    dbms_output.put_line('PACED_STAGE|'||metric_.metric||'|n='||metric_.samples||
      '|avg_ms='||metric_.average_ms||'|p50_ms='||metric_.p50_ms||
      '|p95_ms='||metric_.p95_ms||'|max_ms='||metric_.max_ms);
  end loop;
  cleanup_;
  dbms_output.put_line('PASS P13-PACED-STAGE-DIAGNOSTIC');
exception when others then rollback;cleanup_;raise;
end;
/
