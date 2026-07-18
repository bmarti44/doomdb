-- A lineage root locks every replay-affecting external input. Save/rewind can
-- branch one browser session, so command identity includes save_lineage.
create table doom_mocha_lineage (
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  skill number(1) not null,
  episode number(2) not null,
  map number(2) not null,
  engine_revision varchar2(40) not null,
  iwad_sha varchar2(64) not null,
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_mocha_lineage_pk primary key(session_token,save_lineage),
  constraint doom_mocha_lineage_session_fk foreign key(session_token)
    references game_sessions(session_token) on delete cascade,
  constraint doom_mocha_lineage_value_ck check(
    skill between 1 and 5 and episode between 1 and 9 and map between 1 and 99),
  constraint doom_mocha_lineage_sha_ck check(
    regexp_like(save_lineage,'^[0-9a-f]{64}$') and
    regexp_like(engine_revision,'^[0-9a-f]{40}$') and
    regexp_like(iwad_sha,'^[0-9a-f]{64}$'))
);

-- The public API retains normalized controls. This append-only ledger stores
-- the exact ticcmd bytes actually executed by the retained engine so restart
-- reconstruction remains independent of later input-codec changes.
create table doom_mocha_command (
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  command_seq number(12) not null,
  tic number(12) not null,
  generation number(12) not null,
  ticcmd_raw raw(8) not null,
  ticcmd_sha varchar2(64) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_mocha_command_pk primary key(
    session_token,save_lineage,command_seq),
  constraint doom_mocha_command_lineage_fk foreign key(
    session_token,save_lineage) references doom_mocha_lineage(
      session_token,save_lineage) on delete cascade,
  constraint doom_mocha_command_frontier_ck check(
    command_seq>0 and tic>=0 and generation>0),
  constraint doom_mocha_command_bytes_ck check(vsize(ticcmd_raw)=8),
  constraint doom_mocha_command_sha_ck check(
    regexp_like(ticcmd_sha,'^[0-9a-f]{64}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$'))
);

create unique index doom_mocha_command_tic_uq
  on doom_mocha_command(session_token,save_lineage,tic);
