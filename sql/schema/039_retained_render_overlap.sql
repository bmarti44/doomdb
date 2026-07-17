-- Durable control and staging for the default-off two-session retained-render
-- overlap. The public request row is committed before either worker sees it;
-- the renderer stages bytes independently, while simulation alone chooses
-- ACCEPT or DISCARD after its authoritative transaction outcome is known.

declare
  l_count number;
begin
  select count(*) into l_count from user_tables
    where table_name='DOOM_RENDER_WORKER_CONTROL';
  if l_count=0 then
    execute immediate q'~create table doom_render_worker_control (
      worker_slot number(2) not null,
      target_session varchar2(32),
      target_lineage varchar2(64),
      state_map_sha varchar2(64),
      generation number(12) default 0 not null,
      ready number(1) default 0 not null,
      stop_requested number(1) default 0 not null,
      worker_sid number,
      heartbeat timestamp with time zone,
      last_error varchar2(4000),
      constraint doom_render_worker_control_pk primary key(worker_slot),
      constraint doom_render_worker_slot_ck check(worker_slot between 1 and 4),
      constraint doom_render_worker_target_uq unique(target_session),
      constraint doom_render_worker_bool_ck check(
        ready in(0,1) and stop_requested in(0,1)),
      constraint doom_render_worker_gen_ck check(generation>=0),
      constraint doom_render_worker_target_ck check(
        (target_session is null and target_lineage is null and state_map_sha is null) or
        (regexp_like(target_session,'^[0-9a-f]{32}$') and
         regexp_like(target_lineage,'^[0-9a-f]{64}$') and
         regexp_like(state_map_sha,'^[0-9a-f]{64}$')))
    )~';
    execute immediate q'~insert into doom_render_worker_control(worker_slot)
      select level from dual connect by level<=4~';
  end if;
end;
/

declare
  l_count number;
begin
  select count(*) into l_count from user_tables
    where table_name='DOOM_RENDER_STAGE';
  if l_count=0 then
    execute immediate q'~create table doom_render_stage (
      request_id varchar2(32) not null,
      render_slot number(2) not null,
      session_token varchar2(32) not null,
      save_lineage varchar2(64) not null,
      simulation_generation number(12) not null,
      render_generation number(12) not null,
      expected_tic number(12) not null,
      expected_command_seq number(12) not null,
      state_sha varchar2(64) not null,
      render_pack_bytes number(5) not null,
      render_pack_sha varchar2(64) not null,
      stage_status varchar2(24) not null,
      frame_sha varchar2(64) not null,
      response_bytes number(8) not null,
      response_sha varchar2(64) not null,
      render_us number,
      render_kernel_us number,
      codec_us number,
      response_blob blob not null,
      error_text varchar2(4000),
      staged_at timestamp with time zone default systimestamp not null,
      decided_at timestamp with time zone,
      constraint doom_render_stage_pk primary key(request_id),
      constraint doom_render_stage_request_fk foreign key(request_id)
        references doom_worker_request(request_id) on delete cascade,
      constraint doom_render_stage_control_fk foreign key(render_slot)
        references doom_render_worker_control(worker_slot),
      constraint doom_render_stage_frontier_ck check(
        simulation_generation>0 and render_generation>0 and expected_tic>=0 and
        expected_command_seq>=0 and render_pack_bytes between 1 and 32671 and
        response_bytes>0),
      constraint doom_render_stage_status_ck check(stage_status in(
        'STAGED','ACCEPT_REQUESTED','DISCARD_REQUESTED','ACCEPTED','DISCARDED','FAILED')),
      constraint doom_render_stage_sha_ck check(
        regexp_like(state_sha,'^[0-9a-f]{64}$') and
        regexp_like(render_pack_sha,'^[0-9a-f]{64}$') and
        regexp_like(frame_sha,'^[0-9a-f]{64}$') and
        regexp_like(response_sha,'^[0-9a-f]{64}$'))
    ) lob(response_blob) store as securefile(cache logging retention none)~';
    execute immediate q'~create index doom_render_stage_decision_ix on
      doom_render_stage(render_slot,render_generation,stage_status,staged_at)~';
  end if;
end;
/

declare
  l_count number;
begin
  select count(*) into l_count from user_queue_tables
    where queue_table='DOOM_RENDER_TASK_QT';
  if l_count=0 then
    dbms_aqadm.create_queue_table(
      queue_table=>'DOOM_RENDER_TASK_QT',queue_payload_type=>'RAW');
    dbms_aqadm.create_queue(
      queue_name=>'DOOM_RENDER_TASK_Q',queue_table=>'DOOM_RENDER_TASK_QT');
    dbms_aqadm.start_queue('DOOM_RENDER_TASK_Q');
  end if;
end;
/

commit;
