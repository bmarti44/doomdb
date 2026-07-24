whenever sqlerror exit failure rollback
set define off

-- In-place upgrade for authority-session CPU telemetry. Fresh installs
-- already receive these columns from 048_multiplayer_worker.sql.
declare
  l_count number;
  procedure add_column(
    p_table varchar2,p_name varchar2,p_definition varchar2
  ) is
    l_column_count number;
  begin
    select count(*) into l_column_count from user_tab_columns
      where table_name=p_table and column_name=p_name;
    if l_column_count=0 then
      execute immediate 'alter table '||p_table||' add ('||
        p_name||' '||p_definition||')';
    end if;
  end;
begin
  add_column('DOOM_MATCH_WORKER_CONTROL','WORKER_CPU_CS','number');
  add_column('DOOM_MATCH_WORKER_CONTROL','WORKER_SERIAL','number');
  add_column('DOOM_MATCH_WORKER_CONTROL','CPU_SAMPLE_TIC','number(12)');
  add_column('DOOM_MATCH_WORKER_CONTROL','CPU_SAMPLE_AT','timestamp with time zone');
  add_column('DOOM_MATCH_WORKER_CONTROL','CPU_WINDOW_MS','number');
  add_column('DOOM_MATCH_WORKER_CONTROL','CPU_PERCENT','number');
  add_column('DOOM_MATCH_WORKER_CONTROL','BUSY_UNTIL','timestamp with time zone');
  add_column('DOOM_MATCH_SLOW_CALL','PRE_MLE_MS','number');
  add_column('DOOM_MATCH_SLOW_CALL','MLE_MS','number');
  add_column('DOOM_MATCH_SLOW_CALL','POST_MLE_MS','number');
  add_column('DOOM_MATCH_SLOW_CALL','COMMIT_MS','number');
  add_column('DOOM_MATCH_SLOW_CALL','CHECKPOINT_SAVE_MS','number');
  add_column('DOOM_MATCH_SLOW_CALL','CHECKPOINT_PUBLISH_MS','number');
  select count(*) into l_count from user_constraints
    where table_name='DOOM_MATCH_WORKER_CONTROL'
      and constraint_name='DOOM_MATCH_WORKER_CPU_CK';
  if l_count=0 then
    execute immediate q'[
      alter table doom_match_worker_control add constraint
      doom_match_worker_cpu_ck check(
        (worker_cpu_cs is null or worker_cpu_cs>=0) and
        (cpu_sample_tic is null or cpu_sample_tic>=0) and
        (cpu_window_ms is null or cpu_window_ms>0) and
        (cpu_percent is null or cpu_percent between 0 and 100))]';
  end if;
end;
/

declare
  l_count number;
begin
  select count(*) into l_count from user_tables
    where table_name='DOOM_MATCH_LIVENESS_PROBE';
  if l_count=0 then
    execute immediate q'[
      create table doom_match_liveness_probe (
        probe_id number generated always as identity,
        match_id varchar2(32) not null,
        generation number(12) not null,
        endpoint varchar2(32) not null,
        worker_sid number,
        worker_serial number,
        heartbeat_age_ms number,
        busy_until timestamp with time zone,
        session_found number(1) not null,
        observed_action varchar2(64),
        checkpoint_action number(1) not null,
        decision varchar2(32) not null,
        observed_at timestamp with time zone default
          (localtimestamp at time zone 'UTC') not null,
        constraint doom_match_liveness_probe_pk primary key(probe_id),
        constraint doom_match_liveness_probe_match_fk foreign key(match_id)
          references doom_match(match_id) on delete cascade,
        constraint doom_match_liveness_probe_bits_ck check(
          session_found in(0,1) and checkpoint_action in(0,1))
      )]';
    execute immediate q'[
      create index doom_match_liveness_probe_ix
      on doom_match_liveness_probe(match_id,generation,observed_at)]';
  end if;
end;
/

commit;
