create table doom_match_transition (
  match_id varchar2(32) not null,
  tic number(12) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  previous_chain_sha varchar2(64) not null,
  chain_sha varchar2(64) not null,
  payload_bytes number(8) not null,
  payload_blob blob not null,
  committed_at timestamp with time zone not null,
  constraint doom_match_transition_pk primary key(match_id,tic),
  constraint doom_match_transition_tic_fk foreign key(match_id,tic)
    references doom_match_tic(match_id,tic) on delete cascade,
  constraint doom_match_transition_fence_ck check(
    tic>=1 and membership_epoch>0 and generation>0 and payload_bytes>=150),
  constraint doom_match_transition_sha_ck check(
    regexp_like(previous_chain_sha,'^[0-9a-f]{64}$') and
    regexp_like(chain_sha,'^[0-9a-f]{64}$'))
) lob(payload_blob) store as securefile(cache logging retention none);

create index doom_match_transition_poll_ix on doom_match_transition(
  match_id,membership_epoch,tic,generation);

create table doom_match_poll_capacity (
  capacity_id number(1) not null,
  max_held_polls number(2) not null,
  long_poll_enabled number(1) default 0 not null,
  constraint doom_match_poll_capacity_pk primary key(capacity_id),
  constraint doom_match_poll_capacity_singleton_ck check(
    capacity_id=1 and max_held_polls=4 and long_poll_enabled in(0,1))
);

insert into doom_match_poll_capacity(capacity_id,max_held_polls) values(1,4);

create table doom_match_poll_lease (
  match_id varchar2(32) not null,
  player_slot number(1) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  poll_token raw(16) not null,
  started_at timestamp with time zone not null,
  expires_at timestamp with time zone not null,
  constraint doom_match_poll_lease_pk primary key(match_id,player_slot),
  constraint doom_match_poll_lease_member_fk foreign key(match_id,player_slot)
    references doom_match_member(match_id,player_slot) on delete cascade,
  constraint doom_match_poll_lease_fence_ck check(
    player_slot between 0 and 3 and membership_epoch>0 and generation>0 and
    expires_at>=started_at)
);

commit;
