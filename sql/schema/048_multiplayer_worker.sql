-- Private retained-match worker rendezvous. One Scheduler session owns one
-- authoritative Java engine; this table is never granted or AutoREST-enabled.
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
  worker_status varchar2(16) not null,
  request_status varchar2(16) not null,
  requested_tic number(12),
  worker_sid number,
  heartbeat timestamp with time zone,
  last_error varchar2(2000),
  route_diagnostics number(1) default 0 not null,
  route_status_tic number(12),
  route_status varchar2(4000),
  stop_requested number(1) default 0 not null,
  constraint doom_match_worker_control_pk primary key(match_id),
  constraint doom_match_worker_control_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_worker_control_job_uq unique(job_name),
  constraint doom_match_worker_control_fence_ck check(
    generation>0 and membership_epoch>0 and
    (requested_tic is null or requested_tic>0)),
  constraint doom_match_worker_control_status_ck check(
    worker_status in('STARTING','READY','FAILED','STOPPED') and
    request_status in('IDLE','QUEUED','PROCESSING','FAILED') and
    stop_requested in(0,1) and route_diagnostics in(0,1))
);

create index doom_match_worker_request_ix on doom_match_worker_control(
  worker_status,request_status,requested_tic,heartbeat);

commit;
