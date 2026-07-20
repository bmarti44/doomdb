-- P13 database-authoritative multiplayer contracts. Public bearer values are
-- never stored: only per-capability salts and SHA-256 hashes enter Oracle.

create table doom_match (
  match_id varchar2(32) not null,
  match_state varchar2(16) not null,
  game_mode varchar2(16) not null,
  skill number(1) not null,
  episode number(2) not null,
  map number(2) not null,
  max_players number(1) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  current_tic number(12) not null,
  host_capability_salt raw(32) not null,
  host_capability_hash varchar2(64) not null,
  join_capability_salt raw(32) not null,
  join_capability_hash varchar2(64) not null,
  created_at timestamp with time zone not null,
  last_activity_at timestamp with time zone not null,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  expires_at timestamp with time zone not null,
  constraint doom_match_pk primary key(match_id),
  constraint doom_match_id_ck check(regexp_like(match_id,'^[0-9a-f]{32}$')),
  constraint doom_match_state_ck check(
    match_state in('LOBBY','ACTIVE','FINISHED','CANCELLED')),
  constraint doom_match_mode_ck check(game_mode in('COOP','DEATHMATCH')),
  constraint doom_match_map_ck check(
    skill between 1 and 5 and episode between 1 and 9 and map between 1 and 99),
  constraint doom_match_players_ck check(max_players between 2 and 4),
  constraint doom_match_fence_ck check(
    membership_epoch>0 and generation>=0 and current_tic>=0),
  constraint doom_match_capability_ck check(
    vsize(host_capability_salt)=32 and vsize(join_capability_salt)=32 and
    regexp_like(host_capability_hash,'^[0-9a-f]{64}$') and
    regexp_like(join_capability_hash,'^[0-9a-f]{64}$') and
    host_capability_hash<>join_capability_hash),
  constraint doom_match_time_ck check(
    last_activity_at>=created_at and expires_at>created_at and
    (started_at is null or started_at>=created_at) and
    (finished_at is null or finished_at>=created_at))
);

create index doom_match_lifecycle_ix
  on doom_match(match_state,expires_at,last_activity_at);

create table doom_match_member (
  match_id varchar2(32) not null,
  player_slot number(1) not null,
  member_state varchar2(16) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  capability_epoch number(12) not null,
  capability_salt raw(32) not null,
  capability_hash varchar2(64) not null,
  display_name varchar2(32) not null,
  joined_at timestamp with time zone not null,
  last_seen_at timestamp with time zone not null,
  ready_at timestamp with time zone,
  disconnected_at timestamp with time zone,
  leave_tic number(12),
  constraint doom_match_member_pk primary key(match_id,player_slot),
  constraint doom_match_member_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_member_slot_ck check(player_slot between 0 and 3),
  constraint doom_match_member_state_ck check(member_state in(
    'JOINED','READY','ACTIVE','DISCONNECTED','LEFT')),
  constraint doom_match_member_fence_ck check(
    membership_epoch>0 and generation>=0 and capability_epoch>0 and
    (leave_tic is null or leave_tic>=0)),
  constraint doom_match_member_cap_ck check(
    vsize(capability_salt)=32 and
    regexp_like(capability_hash,'^[0-9a-f]{64}$')),
  constraint doom_match_member_name_ck check(
    length(display_name) between 1 and 32 and
    display_name=trim(display_name)),
  constraint doom_match_member_time_ck check(
    last_seen_at>=joined_at and
    (ready_at is null or ready_at>=joined_at) and
    (disconnected_at is null or disconnected_at>=joined_at)),
  constraint doom_match_member_cap_uq unique(capability_hash)
);

create index doom_match_member_state_ix
  on doom_match_member(match_id,membership_epoch,generation,member_state);

create table doom_match_command (
  match_id varchar2(32) not null,
  tic number(12) not null,
  player_slot number(1) not null,
  command_seq number(12) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  command_source varchar2(16) not null,
  ticcmd_raw raw(8) not null,
  command_sha varchar2(64) not null,
  submitted_at timestamp with time zone not null,
  accepted_at timestamp with time zone not null,
  constraint doom_match_command_pk primary key(match_id,tic,player_slot),
  constraint doom_match_command_member_fk foreign key(match_id,player_slot)
    references doom_match_member(match_id,player_slot) on delete cascade,
  constraint doom_match_command_seq_uq unique(match_id,player_slot,command_seq),
  constraint doom_match_command_frontier_ck check(
    tic>0 and command_seq>0 and membership_epoch>0 and generation>0),
  constraint doom_match_command_slot_ck check(player_slot between 0 and 3),
  constraint doom_match_command_source_ck check(
    command_source in('SUBMITTED','NEUTRAL_DEADLINE','NEUTRAL_LEFT')),
  constraint doom_match_command_raw_ck check(vsize(ticcmd_raw)=8),
  constraint doom_match_command_sha_ck check(
    regexp_like(command_sha,'^[0-9a-f]{64}$')),
  constraint doom_match_command_time_ck check(accepted_at>=submitted_at)
);

create index doom_match_command_tic_ix on doom_match_command(
  match_id,membership_epoch,generation,tic,command_source,player_slot);

create table doom_match_tic (
  match_id varchar2(32) not null,
  tic number(12) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  membership_bitmap raw(1) not null,
  neutral_bitmap raw(1) not null,
  command_vector raw(32) not null,
  command_sha varchar2(64) not null,
  previous_state_sha varchar2(64) not null,
  state_sha varchar2(64) not null,
  event_sha varchar2(64) not null,
  deadline_at timestamp with time zone not null,
  committed_at timestamp with time zone not null,
  constraint doom_match_tic_pk primary key(match_id,tic),
  constraint doom_match_tic_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_tic_frontier_ck check(
    tic>=0 and membership_epoch>0 and generation>0),
  constraint doom_match_tic_bitmap_ck check(
    vsize(membership_bitmap)=1 and vsize(neutral_bitmap)=1),
  constraint doom_match_tic_vector_ck check(vsize(command_vector)=32),
  constraint doom_match_tic_sha_ck check(
    regexp_like(command_sha,'^[0-9a-f]{64}$') and
    regexp_like(previous_state_sha,'^[0-9a-f]{64}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(event_sha,'^[0-9a-f]{64}$')),
  constraint doom_match_tic_time_ck check(committed_at>=deadline_at)
);

create index doom_match_tic_fence_ix
  on doom_match_tic(match_id,membership_epoch,generation,tic);

create table doom_match_frame (
  match_id varchar2(32) not null,
  tic number(12) not null,
  player_slot number(1) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  frame_sha varchar2(64) not null,
  response_sha varchar2(64) not null,
  response_bytes number(8) not null,
  response_blob blob not null,
  created_at timestamp with time zone not null,
  constraint doom_match_frame_pk primary key(match_id,tic,player_slot),
  constraint doom_match_frame_member_fk foreign key(match_id,player_slot)
    references doom_match_member(match_id,player_slot) on delete cascade,
  constraint doom_match_frame_tic_fk foreign key(match_id,tic)
    references doom_match_tic(match_id,tic) on delete cascade
    deferrable initially deferred,
  constraint doom_match_frame_fence_ck check(
    tic>=0 and player_slot between 0 and 3 and
    membership_epoch>0 and generation>0 and response_bytes>0),
  constraint doom_match_frame_sha_ck check(
    regexp_like(frame_sha,'^[0-9a-f]{64}$') and
    regexp_like(response_sha,'^[0-9a-f]{64}$'))
) lob(response_blob) store as securefile(cache logging retention none);

create index doom_match_frame_poll_ix
  on doom_match_frame(match_id,player_slot,membership_epoch,generation,tic);

create table doom_match_checkpoint (
  match_id varchar2(32) not null,
  tic number(12) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  membership_bitmap raw(1) not null,
  command_sha varchar2(64) not null,
  state_sha varchar2(64) not null,
  checkpoint_sha varchar2(64) not null,
  checkpoint_bytes number(8) not null,
  checkpoint_blob blob not null,
  created_at timestamp with time zone not null,
  constraint doom_match_checkpoint_pk primary key(match_id,tic),
  constraint doom_match_checkpoint_tic_fk foreign key(match_id,tic)
    references doom_match_tic(match_id,tic) on delete cascade,
  constraint doom_match_checkpoint_fence_ck check(
    tic>=0 and membership_epoch>0 and generation>0 and checkpoint_bytes>0),
  constraint doom_match_checkpoint_bitmap_ck check(
    vsize(membership_bitmap)=1),
  constraint doom_match_checkpoint_sha_ck check(
    regexp_like(command_sha,'^[0-9a-f]{64}$') and
    regexp_like(state_sha,'^[0-9a-f]{64}$') and
    regexp_like(checkpoint_sha,'^[0-9a-f]{64}$'))
) lob(checkpoint_blob) store as securefile(cache logging retention none);

commit;
