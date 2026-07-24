-- Private retained-match worker rendezvous. One Scheduler session owns one
-- authoritative MLE engine; this table is never granted or AutoREST-enabled.
declare
  l_deferrable varchar2(16);
begin
  select deferrable into l_deferrable from user_constraints
    where constraint_name='DOOM_MATCH_FRAME_TIC_FK';
  if l_deferrable<>'DEFERRABLE' then
    execute immediate 'alter table doom_match_frame drop constraint doom_match_frame_tic_fk';
    execute immediate q'[alter table doom_match_frame add constraint
      doom_match_frame_tic_fk foreign key(match_id,tic)
      references doom_match_tic(match_id,tic) on delete cascade
      deferrable initially deferred]';
  end if;
end;
/

create table doom_match_worker_control (
  match_id varchar2(32) not null,
  generation number(12) not null,
  membership_epoch number(12) not null,
  job_name varchar2(64) not null,
  worker_mode varchar2(16) default 'LOCKSTEP' not null,
  worker_status varchar2(16) not null,
  request_status varchar2(16) not null,
  requested_tic number(12),
  worker_sid number,
  worker_serial number,
  heartbeat timestamp with time zone,
  last_error varchar2(2000),
  route_diagnostics number(1) default 0 not null,
  checkpoint_test_hook number(1) default 0 not null,
  route_status_tic number(12),
  route_status varchar2(4000),
  worker_cpu_cs number,
  cpu_sample_tic number(12),
  cpu_sample_at timestamp with time zone,
  cpu_window_ms number,
  cpu_percent number,
  busy_until timestamp with time zone,
  stop_requested number(1) default 0 not null,
  constraint doom_match_worker_control_pk primary key(match_id),
  constraint doom_match_worker_control_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_worker_mode_ck check(
    worker_mode in('LOCKSTEP','PACED_INPUT')),
  constraint doom_match_worker_control_fence_ck check(
    generation>0 and membership_epoch>0 and
    (requested_tic is null or requested_tic>0)),
  constraint doom_match_worker_cpu_ck check(
    (worker_cpu_cs is null or worker_cpu_cs>=0) and
    (cpu_sample_tic is null or cpu_sample_tic>=0) and
    (cpu_window_ms is null or cpu_window_ms>0) and
    (cpu_percent is null or cpu_percent between 0 and 100)),
  constraint doom_match_worker_control_status_ck check(
    worker_status in('STARTING','READY','FAILED','STOPPED') and
    request_status in('IDLE','QUEUED','PROCESSING','FAILED') and
    stop_requested in(0,1) and route_diagnostics in(0,1) and
    checkpoint_test_hook in(0,1))
);

create index doom_match_worker_request_ix on doom_match_worker_control(
  worker_status,request_status,requested_tic,heartbeat);

-- One exact-configuration warm MLE context may shadow an active match. It is
-- session-private until a fenced generation promotion transfers worker
-- ownership; it never publishes authority while in READY state.
create table doom_match_standby_control (
  match_id varchar2(32) not null,
  base_generation number(12) not null,
  job_name varchar2(64) not null,
  standby_status varchar2(16) not null,
  worker_sid number,
  heartbeat timestamp with time zone not null,
  promote_generation number(12),
  last_error varchar2(2000),
  stop_requested number(1) default 0 not null,
  constraint doom_match_standby_pk primary key(match_id),
  constraint doom_match_standby_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_standby_status_ck check(
    standby_status in('STARTING','READY','PROMOTING','FAILED','STOPPED')),
  constraint doom_match_standby_generation_ck check(
    base_generation>0 and
    (promote_generation is null or promote_generation=base_generation+1)),
  constraint doom_match_standby_stop_ck check(stop_requested in(0,1))
);

create index doom_match_standby_status_ix on doom_match_standby_control(
  standby_status,heartbeat);

-- Sparse, fail-closed observability for the final retained-worker soak.
-- Ordinary tics do not write this table; a row is emitted only after a
-- complete authority transaction (including COMMIT) exceeds 100 ms.
create table doom_match_slow_call (
  slow_call_id number generated always as identity,
  match_id varchar2(32) not null,
  tic number(12) not null,
  generation number(12) not null,
  worker_sid number not null,
  started_at timestamp with time zone not null,
  ended_at timestamp with time zone not null,
  elapsed_ms number not null,
  pre_mle_ms number,
  mle_ms number,
  post_mle_ms number,
  commit_ms number,
  checkpoint_save_ms number,
  checkpoint_publish_ms number,
  stage varchar2(32) not null,
  constraint doom_match_slow_call_pk primary key(slow_call_id),
  constraint doom_match_slow_call_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_slow_call_elapsed_ck check(elapsed_ms>100)
);

create index doom_match_slow_call_match_ix on doom_match_slow_call(
  match_id,generation,tic);

-- Sparse cadence evidence. Rows exist only when private route diagnostics are
-- enabled and only at checkpoint-opportunity probes, never on ordinary tics.
create table doom_match_checkpoint_probe (
  match_id varchar2(32) not null,
  tic number(12) not null,
  generation number(12) not null,
  previous_checkpoint_tic number(12) not null,
  checkpoint_distance number(12) not null,
  awake_monsters number(12) not null,
  checkpoint_decision varchar2(16) not null,
  observed_at timestamp with time zone default
    (localtimestamp at time zone 'UTC') not null,
  constraint doom_match_checkpoint_probe_pk primary key(match_id,tic),
  constraint doom_match_checkpoint_probe_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_checkpoint_probe_decision_ck check(
    checkpoint_decision in('LOW_AWAKE','FORCED_MAX','DEFER_HIGH'))
);

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
);

create index doom_match_liveness_probe_ix on doom_match_liveness_probe(
  match_id,generation,observed_at);

commit;
