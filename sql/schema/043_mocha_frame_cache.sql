-- Latest reconstructed frame published by the retained Scheduler/OJVM owner.
-- NEW_GAME reads this cache only after the matching generation is READY.
create table doom_mocha_frame_cache (
  session_token varchar2(32) not null,
  save_lineage varchar2(64) not null,
  generation number(12) not null,
  tic number(12) not null,
  state_sha varchar2(64) not null,
  frame_sha varchar2(64) not null,
  response_blob blob not null,
  created_at timestamp with time zone default systimestamp not null,
  constraint doom_mocha_frame_cache_pk primary key(session_token),
  constraint doom_mocha_frame_cache_lineage_fk foreign key(
    session_token,save_lineage) references doom_mocha_lineage(
      session_token,save_lineage) on delete cascade,
  constraint doom_mocha_frame_cache_frontier_ck check(generation>0 and tic>=0),
  constraint doom_mocha_frame_cache_sha_ck check(
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(frame_sha,'^[0-9a-f]{64}$'))
) lob(response_blob) store as securefile(cache logging retention none);
