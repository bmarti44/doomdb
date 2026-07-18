-- Save slots are immutable pointers into an exact-command lineage. LOAD forks
-- that prefix into a new lineage; the global public command sequence continues.
create table doom_mocha_save_slot (
  session_token varchar2(32) not null,
  slot_number number(2) not null,
  source_lineage varchar2(64) not null,
  saved_tic number(12) not null,
  saved_command_seq number(12) not null,
  rng_cursor number(3) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  saved_at timestamp with time zone default systimestamp not null,
  constraint doom_mocha_save_slot_pk primary key(session_token,slot_number),
  constraint doom_mocha_save_slot_lineage_fk foreign key(
    session_token,source_lineage) references doom_mocha_lineage(
      session_token,save_lineage) on delete cascade,
  constraint doom_mocha_save_slot_value_ck check(
    slot_number between 0 and 99 and saved_tic>=0 and
    saved_command_seq>=0 and rng_cursor between 0 and 255),
  constraint doom_mocha_save_slot_sha_ck check(
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$'))
);
