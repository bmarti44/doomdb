whenever sqlerror exit failure rollback

-- Some runtime objects deliberately reference packages or columns installed
-- later in the bootstrap graph.  Close those forward dependencies explicitly
-- so a clean bootstrap finishes with no INVALID objects.
alter trigger doom_game_events_bir compile;
alter procedure doom_renderer_delta_fill compile;
alter procedure doom_renderer_snapshot_fill compile;

declare
  l_present number;
begin
  select count(*) into l_present from user_objects
    where object_name='DOOM_UNIFIED_WORKER' and object_type='PACKAGE BODY';
  if l_present=1 then
    execute immediate 'alter package doom_unified_worker compile body';
  end if;
end;
/

declare
  l_invalid number;
begin
  select count(*) into l_invalid from user_objects where status<>'VALID';
  if l_invalid<>0 then
    raise_application_error(-20000,'bootstrap left invalid runtime objects='||l_invalid);
  end if;
end;
/

-- Production bootstrap has already hash-fenced the accepted MLE module and all
-- ten E1M1 origins. Development bootstrap may intentionally defer that load.
declare
  l_origins number;
  l_runtime number;
begin
  select count(*) into l_origins from doom_mle_tic0_checkpoint;
  select count(*) into l_runtime from user_objects
    where object_name='DOOM_TEAVM_SIM_MULTI_INIT_GAME'
      and object_type='FUNCTION' and status='VALID';
  if l_origins=10 and l_runtime=1 then
    begin
      dbms_scheduler.drop_job('DOOM_MLE_WARM_JANITOR',true);
    exception when others then
      if sqlcode<>-27475 then raise;end if;
    end;
    dbms_scheduler.create_job(
      job_name=>'DOOM_MLE_WARM_JANITOR',
      job_type=>'STORED_PROCEDURE',
      job_action=>'DOOM_WORKER_LIFECYCLE.RECONCILE_WARM_SLOTS',
      start_date=>systimestamp,
      repeat_interval=>'FREQ=SECONDLY;INTERVAL=30',
      enabled=>true,
      auto_drop=>false);
    doom_match_worker.start_warm_pool;
  end if;
end;
/
