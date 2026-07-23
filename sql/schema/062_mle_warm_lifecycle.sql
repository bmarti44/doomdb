-- Incarnation-fenced lifecycle records for retained MLE worker sessions.
-- Slot state is written only by RUN_WARM_SLOT and the bounded janitor.
alter table doom_mle_warm_slot add (
  incarnation_token varchar2(32),
  worker_serial number,
  worker_spid varchar2(24),
  worker_job_run varchar2(64)
);

create table doom_mle_warm_launch (
  slot_id number(1) not null,
  job_name varchar2(64) not null,
  incarnation_token varchar2(32) not null,
  requested_at timestamp with time zone not null,
  launch_status varchar2(16) not null,
  constraint doom_mle_warm_launch_pk primary key(slot_id),
  constraint doom_mle_warm_launch_slot_ck check(slot_id in(1,2)),
  constraint doom_mle_warm_launch_token_ck check(
    regexp_like(incarnation_token,'^[0-9a-f]{32}$')),
  constraint doom_mle_warm_launch_status_ck check(
    launch_status in('REQUESTED','RUNNING','READY','FAILED','STOPPED'))
);

create table doom_mle_warm_assignment (
  assignment_id number generated always as identity,
  slot_id number(1) not null,
  job_name varchar2(64) not null,
  incarnation_token varchar2(32) not null,
  worker_sid number not null,
  worker_serial number not null,
  worker_spid varchar2(24) not null,
  worker_job_run varchar2(64) not null,
  match_id varchar2(32) not null,
  assigned_role varchar2(16) not null,
  assignment_status varchar2(16) not null,
  requested_at timestamp with time zone not null,
  accepted_at timestamp with time zone,
  finished_at timestamp with time zone,
  failure_detail varchar2(2000),
  active_slot number generated always as (
    case when assignment_status in('PENDING','ACCEPTED') then slot_id end
  ) virtual,
  constraint doom_mle_warm_assignment_pk primary key(assignment_id),
  constraint doom_mle_warm_assignment_active_uq unique(active_slot),
  constraint doom_mle_warm_assignment_slot_ck check(slot_id in(1,2)),
  constraint doom_mle_warm_assignment_token_ck check(
    regexp_like(incarnation_token,'^[0-9a-f]{32}$')),
  constraint doom_mle_warm_assignment_match_ck check(
    regexp_like(match_id,'^[0-9a-f]{32}$')),
  constraint doom_mle_warm_assignment_role_ck check(
    assigned_role in('AUTHORITY','STANDBY')),
  constraint doom_mle_warm_assignment_status_ck check(
    assignment_status in('PENDING','ACCEPTED','FINISHED','REJECTED','FAILED'))
);

create table doom_worker_stop_intent (
  intent_id number generated always as identity,
  job_name varchar2(128) not null,
  slot_id number(1),
  incarnation_token varchar2(32),
  target_sid number,
  target_serial number,
  target_spid varchar2(24),
  target_job_run varchar2(64),
  requestor varchar2(128) not null,
  reason varchar2(1000) not null,
  requested_at timestamp with time zone not null,
  honor_deadline timestamp with time zone not null,
  intent_status varchar2(16) not null,
  resolved_at timestamp with time zone,
  resolution_detail varchar2(2000),
  constraint doom_worker_stop_intent_pk primary key(intent_id),
  constraint doom_worker_stop_intent_slot_ck check(
    slot_id is null or slot_id in(1,2)),
  constraint doom_worker_stop_intent_token_ck check(
    incarnation_token is null or
    regexp_like(incarnation_token,'^[0-9a-f]{32}$')),
  constraint doom_worker_stop_intent_status_ck check(
    intent_status in('PENDING','HONORED','FORCED','REJECTED','STALE'))
);

create index doom_worker_stop_intent_target_ix on doom_worker_stop_intent(
  slot_id,incarnation_token,intent_status);

create table doom_mle_prewarm_run (
  prewarm_id number generated always as identity,
  started_at timestamp with time zone not null,
  authority_ready_at timestamp with time zone,
  standby_ready_at timestamp with time zone,
  completed_at timestamp with time zone,
  prewarm_status varchar2(16) not null,
  failure_detail varchar2(2000),
  constraint doom_mle_prewarm_run_pk primary key(prewarm_id),
  constraint doom_mle_prewarm_run_status_ck check(
    prewarm_status in('STARTING','AUTHORITY_READY','READY','FAILED'))
);

commit;
