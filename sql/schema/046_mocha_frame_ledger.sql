-- Exact rendered payloads already live durably in DOOM_WORKER_RESULT.  This
-- lineage index references that immutable BLOB instead of copying ~10 KB per
-- tic into a second SecureFile; LOAD can share the prefix without extra I/O.
create table doom_mocha_frame_ledger (
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  command_seq number(12) not null,
  tic number(12) not null,
  request_id varchar2(32) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  response_sha varchar2(64) not null,
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_mocha_frame_ledger_pk primary key(
    session_token,save_lineage,tic),
  constraint doom_mocha_frame_ledger_command_uq unique(
    session_token,save_lineage,command_seq),
  constraint doom_mocha_frame_ledger_lineage_fk foreign key(
    session_token,save_lineage) references doom_mocha_lineage(
      session_token,save_lineage) on delete cascade,
  constraint doom_mocha_frame_ledger_command_fk foreign key(
    session_token,save_lineage,command_seq) references doom_mocha_command(
      session_token,save_lineage,command_seq) on delete cascade,
  constraint doom_mocha_frame_ledger_result_fk foreign key(request_id)
    references doom_worker_result(request_id) on delete cascade,
  constraint doom_mocha_frame_ledger_frontier_ck check(
    command_seq>0 and tic>0),
  constraint doom_mocha_frame_ledger_sha_ck check(
    regexp_like(request_id,'^[0-9a-f]{32}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$') and
    regexp_like(response_sha,'^[0-9a-f]{64}$'))
);

-- Required for bounded lineage deletion. Without this child-FK index, every
-- DOOM_WORKER_RESULT row removed by an expired session scans the entire frame
-- ledger, making a long played route block NEW_GAME for many minutes.
create index doom_mocha_frame_ledger_result_ix
  on doom_mocha_frame_ledger(request_id);
