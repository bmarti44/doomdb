-- Private deploy-time E1M1 origin bank and two retained warm MLE slots.
-- The bank loader compares every BLOB SHA inside Oracle before a slot may use it.
create table doom_mle_tic0_checkpoint (
  game_mode varchar2(16) not null,
  skill number(1) not null,
  episode number(1) not null,
  map number(2) not null,
  active_players number(1) not null,
  checkpoint_blob blob not null,
  checkpoint_bytes number not null,
  checkpoint_sha256 varchar2(64) not null,
  state_sha256 varchar2(64) not null,
  authority_sha256 varchar2(64) not null,
  loaded_at timestamp with time zone default
    (localtimestamp at time zone 'UTC') not null,
  constraint doom_mle_tic0_checkpoint_pk primary key(
    game_mode,skill,episode,map,active_players),
  constraint doom_mle_tic0_checkpoint_mode_ck check(
    game_mode in('COOP','DEATHMATCH')),
  constraint doom_mle_tic0_checkpoint_shape_ck check(
    skill between 1 and 5 and episode=1 and map=1 and active_players=2 and
    checkpoint_bytes>0 and
    regexp_like(checkpoint_sha256,'^[0-9a-f]{64}$') and
    regexp_like(state_sha256,'^[0-9a-f]{64}$') and
    regexp_like(authority_sha256,'^[0-9a-f]{64}$'))
);

create table doom_mle_warm_slot (
  slot_id number(1) not null,
  job_name varchar2(64) not null,
  slot_status varchar2(16) not null,
  assigned_match varchar2(32),
  assigned_role varchar2(16),
  worker_sid number,
  heartbeat timestamp with time zone not null,
  state_sha256 varchar2(64),
  last_error varchar2(2000),
  stop_requested number(1) default 0 not null,
  constraint doom_mle_warm_slot_pk primary key(slot_id),
  constraint doom_mle_warm_slot_job_uq unique(job_name),
  constraint doom_mle_warm_slot_id_ck check(slot_id in(1,2)),
  constraint doom_mle_warm_slot_status_ck check(
    slot_status in('WARMING','READY','CLAIMED','RUNNING','FAILED','STOPPED')),
  constraint doom_mle_warm_slot_assignment_ck check(
    (assigned_match is null and assigned_role is null) or
    (regexp_like(assigned_match,'^[0-9a-f]{32}$') and
     assigned_role in('AUTHORITY','STANDBY'))),
  constraint doom_mle_warm_slot_stop_ck check(stop_requested in(0,1))
);

insert into doom_mle_warm_slot(
  slot_id,job_name,slot_status,heartbeat)
select level,'DOOM_MLE_WARM_'||to_char(level,'FM00'),'STOPPED',
  (localtimestamp at time zone 'UTC')
from dual connect by level<=2;

commit;
