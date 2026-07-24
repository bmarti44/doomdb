whenever sqlerror exit failure rollback
set define off

-- In-place upgrade for diagnostic-only recovery-stage telemetry and the
-- high-awake checkpoint-SAVE scaffold. Fresh installs receive the same
-- columns and hook domain from 048_multiplayer_worker.sql.
declare
  l_constraint number;
  procedure add_column(p_name varchar2,p_definition varchar2) is
    l_count number;
  begin
    select count(*) into l_count from user_tab_columns
      where table_name='DOOM_MATCH_WORKER_CONTROL' and column_name=p_name;
    if l_count=0 then
      execute immediate 'alter table doom_match_worker_control add ('||
        p_name||' '||p_definition||')';
    end if;
  end;
begin
  add_column('RECOVERY_CHECKPOINT_TIC','number(12)');
  add_column('RECOVERY_FRONTIER_TIC','number(12)');
  add_column('RECOVERY_RESTORE_MS','number');
  add_column('RECOVERY_REPLAY_MS','number');
  add_column('RECOVERY_PUBLISH_MS','number');
  add_column('RECOVERY_WORKER_TOTAL_MS','number');
  add_column('RECOVERY_MEASURED_AT','timestamp with time zone');

  select count(*) into l_constraint from user_constraints
    where table_name='DOOM_MATCH_WORKER_CONTROL'
      and constraint_name='DOOM_MATCH_WORKER_CONTROL_STATUS_CK';
  if l_constraint=1 then
    execute immediate 'alter table doom_match_worker_control drop constraint '||
      'doom_match_worker_control_status_ck';
  end if;
  execute immediate q'[
    alter table doom_match_worker_control add constraint
    doom_match_worker_control_status_ck check(
      worker_status in('STARTING','READY','FAILED','STOPPED') and
      request_status in('IDLE','QUEUED','PROCESSING','FAILED') and
      stop_requested in(0,1) and route_diagnostics in(0,1) and
      checkpoint_test_hook in(0,1,2))]';

  select count(*) into l_constraint from user_constraints
    where table_name='DOOM_MATCH_WORKER_CONTROL'
      and constraint_name='DOOM_MATCH_CHECKPOINT_HOOK_CK';
  if l_constraint=1 then
    execute immediate 'alter table doom_match_worker_control drop constraint '||
      'doom_match_checkpoint_hook_ck';
  end if;
  execute immediate q'[
    alter table doom_match_worker_control add constraint
    doom_match_checkpoint_hook_ck check(checkpoint_test_hook in(0,1,2))]';
end;
/

commit;
