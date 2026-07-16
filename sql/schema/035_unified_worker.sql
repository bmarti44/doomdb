-- Durable rendezvous and transaction ledger for the retained unified worker.
-- Runtime execution remains disabled until UNIFIED_WORKER_ENABLED is set to 1.

create table doom_worker_control (
  worker_slot number(2) not null,
  target_session varchar2(32),
  target_lineage varchar2(64),
  generation number(12) default 0 not null,
  ready number(1) default 0 not null,
  stop_requested number(1) default 0 not null,
  worker_sid number,
  heartbeat timestamp with time zone,
  last_error varchar2(4000),
  constraint doom_worker_control_pk primary key(worker_slot),
  constraint doom_worker_control_slot_ck check(worker_slot between 1 and 4),
  constraint doom_worker_control_target_uq unique(target_session),
  constraint doom_worker_control_bool_ck check(
    ready in(0,1) and stop_requested in(0,1)),
  constraint doom_worker_control_gen_ck check(generation>=0),
  constraint doom_worker_control_target_ck check(
    (target_session is null and target_lineage is null) or
    (regexp_like(target_session,'^[0-9a-f]{32}$') and
     regexp_like(target_lineage,'^[0-9a-f]{64}$')))
);

insert into doom_worker_control(worker_slot) select level from dual connect by level<=4;

create table doom_worker_request (
  request_id varchar2(32) not null,
  worker_slot number(2) not null,
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  generation number(12) not null,
  expected_tic number(12) not null,
  expected_command_seq number(12) not null,
  command_version number(3) not null,
  command_count number(3) not null,
  command_bytes number(4) not null,
  command_sha varchar2(64) not null,
  command_pack raw(2000) not null,
  request_status varchar2(16) not null,
  response_generation number(12),
  error_text varchar2(4000),
  created_at timestamp with time zone not null,
  completed_at timestamp with time zone,
  constraint doom_worker_request_pk primary key(request_id),
  constraint doom_worker_request_control_fk foreign key(worker_slot)
    references doom_worker_control(worker_slot),
  constraint doom_worker_request_session_fk foreign key(session_token)
    references game_sessions(session_token) on delete cascade,
  constraint doom_worker_request_id_ck check(
    regexp_like(request_id,'^[0-9a-f]{32}$')),
  constraint doom_worker_request_lineage_ck check(
    regexp_like(save_lineage,'^[0-9a-f]{64}$')),
  constraint doom_worker_request_frontier_ck check(
    generation>0 and expected_tic>=0 and expected_command_seq>=0),
  constraint doom_worker_request_pack_ck check(
    command_version between 1 and 255 and command_count between 1 and 255 and
    command_bytes between 1 and 2000),
  constraint doom_worker_request_sha_ck check(
    regexp_like(command_sha,'^[0-9a-f]{64}$')),
  constraint doom_worker_request_status_ck check(
    request_status in('QUEUED','PROCESSING','COMMITTED','ROLLED_BACK','FAILED'))
);

create index doom_worker_request_status_ix
  on doom_worker_request(request_status,created_at);

create table doom_worker_result (
  request_id varchar2(32) not null,
  committed_tic number(12) not null,
  committed_command_seq number(12) not null,
  delta_version number(3) not null,
  delta_count number(3) not null,
  delta_bytes number(8) not null,
  delta_sha varchar2(64) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  response_bytes number(8) not null,
  response_sha varchar2(64) not null,
  delta_blob blob not null,
  response_blob blob not null,
  constraint doom_worker_result_pk primary key(request_id),
  constraint doom_worker_result_request_fk foreign key(request_id)
    references doom_worker_request(request_id) on delete cascade,
  constraint doom_worker_result_frontier_ck check(
    committed_tic>=0 and committed_command_seq>=0),
  constraint doom_worker_result_delta_ck check(
    delta_version between 1 and 255 and delta_count between 0 and 255 and
    delta_bytes>=0 and response_bytes>=0),
  constraint doom_worker_result_sha_ck check(
    regexp_like(delta_sha,'^[0-9a-f]{64}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$') and
    regexp_like(response_sha,'^[0-9a-f]{64}$'))
) lob(delta_blob) store as securefile(cache)
  lob(response_blob) store as securefile(cache);

create table doom_worker_audit (
  audit_id number generated always as identity not null,
  request_id varchar2(32),
  worker_slot number(2),
  generation number(12),
  audit_event varchar2(32) not null,
  detail varchar2(4000),
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_worker_audit_pk primary key(audit_id),
  constraint doom_worker_audit_slot_ck check(worker_slot between 1 and 4)
);

create index doom_worker_audit_request_ix
  on doom_worker_audit(request_id,audit_event);

begin
  dbms_aqadm.create_queue_table(
    queue_table=>'DOOM_UNIFIED_REQUEST_QT',queue_payload_type=>'RAW');
  dbms_aqadm.create_queue_table(
    queue_table=>'DOOM_UNIFIED_RESPONSE_QT',queue_payload_type=>'RAW');
  dbms_aqadm.create_queue(
    queue_name=>'DOOM_UNIFIED_REQUEST_Q',queue_table=>'DOOM_UNIFIED_REQUEST_QT');
  dbms_aqadm.create_queue(
    queue_name=>'DOOM_UNIFIED_RESPONSE_Q',queue_table=>'DOOM_UNIFIED_RESPONSE_QT');
  dbms_aqadm.start_queue('DOOM_UNIFIED_REQUEST_Q');
  dbms_aqadm.start_queue('DOOM_UNIFIED_RESPONSE_Q');
end;
/

commit;
