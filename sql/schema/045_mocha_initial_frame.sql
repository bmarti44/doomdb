-- Immutable tic-zero payload for each exact-command lineage.  The mutable
-- frame cache is intentionally only the latest reconstruction frontier; replay
-- needs a durable tic-zero frame even after save/load creates another lineage.
create table doom_mocha_initial_frame (
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  response_blob blob not null,
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_mocha_initial_frame_pk primary key(
    session_token,save_lineage),
  constraint doom_mocha_initial_frame_lineage_fk foreign key(
    session_token,save_lineage) references doom_mocha_lineage(
      session_token,save_lineage) on delete cascade,
  constraint doom_mocha_initial_frame_sha_ck check(
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$'))
) lob(response_blob) store as securefile(cache logging retention none);
