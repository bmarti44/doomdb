-- Production MLE framebuffer transport.
--
-- The renderer and coordinator sources are staged as hash-fenced BLOBs by the
-- @mle-live-frame-module bootstrap boundary.  The per-match table is a bounded
-- 64-entry ring for each POV; the production entry contains six complete
-- frames, so storage remains bounded while locator crossings are amortized.

create table doom_mle_live_frame_source (
  artifact_id number(1) not null,
  authority_bytes number(10) not null,
  authority_sha256 varchar2(64) not null,
  renderer_source blob not null,
  coordinator_source blob not null,
  world_pack blob not null,
  compositor_pack blob not null,
  wall_asset blob not null,
  flat_asset blob not null,
  sprite_asset blob not null,
  ui_asset blob not null,
  renderer_bytes number(10) not null,
  renderer_sha256 varchar2(64) not null,
  coordinator_bytes number(10) not null,
  coordinator_sha256 varchar2(64) not null,
  world_pack_bytes number(10) not null,
  world_pack_sha256 varchar2(64) not null,
  compositor_pack_bytes number(10) not null,
  compositor_pack_sha256 varchar2(64) not null,
  wall_asset_bytes number(10) not null,
  wall_asset_sha256 varchar2(64) not null,
  flat_asset_bytes number(10) not null,
  flat_asset_sha256 varchar2(64) not null,
  sprite_asset_bytes number(10) not null,
  sprite_asset_sha256 varchar2(64) not null,
  ui_asset_bytes number(10) not null,
  ui_asset_sha256 varchar2(64) not null,
  constraint doom_mle_live_frame_source_pk primary key(artifact_id),
  constraint doom_mle_live_frame_source_singleton_ck check(artifact_id=1),
  constraint doom_mle_live_frame_source_bytes_ck check(
    authority_bytes>0 and renderer_bytes>0 and coordinator_bytes>0 and
    world_pack_bytes>0 and compositor_pack_bytes>0 and
    wall_asset_bytes>0 and flat_asset_bytes>0 and
    sprite_asset_bytes>0 and ui_asset_bytes>0),
  constraint doom_mle_live_frame_source_sha_ck check(
    regexp_like(authority_sha256,'^[0-9a-f]{64}$') and
    regexp_like(renderer_sha256,'^[0-9a-f]{64}$') and
    regexp_like(coordinator_sha256,'^[0-9a-f]{64}$') and
    regexp_like(world_pack_sha256,'^[0-9a-f]{64}$') and
    regexp_like(compositor_pack_sha256,'^[0-9a-f]{64}$') and
    regexp_like(wall_asset_sha256,'^[0-9a-f]{64}$') and
    regexp_like(flat_asset_sha256,'^[0-9a-f]{64}$') and
    regexp_like(sprite_asset_sha256,'^[0-9a-f]{64}$') and
    regexp_like(ui_asset_sha256,'^[0-9a-f]{64}$'))
) lob(renderer_source) store as securefile(cache logging retention none)
  lob(coordinator_source) store as securefile(cache logging retention none)
  lob(world_pack) store as securefile(cache logging retention none)
  lob(compositor_pack) store as securefile(cache logging retention none)
  lob(wall_asset) store as securefile(cache logging retention none)
  lob(flat_asset) store as securefile(cache logging retention none)
  lob(sprite_asset) store as securefile(cache logging retention none)
  lob(ui_asset) store as securefile(cache logging retention none);

create table doom_match_live_frame (
  match_id varchar2(32) not null,
  player_slot number(1) not null,
  ring_slot number(2) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  tic number(12) default -1 not null,
  palette_index number(2) default 0 not null,
  payload_bytes number(8) default 0 not null,
  payload_blob blob not null,
  published_at timestamp with time zone,
  constraint doom_match_live_frame_pk
    primary key(match_id,player_slot,ring_slot),
  constraint doom_match_live_frame_member_fk
    foreign key(match_id,player_slot)
    references doom_match_member(match_id,player_slot) on delete cascade,
  constraint doom_match_live_frame_slot_ck check(
    player_slot between 0 and 3 and ring_slot between 0 and 63
    and palette_index between 0 and 13),
  constraint doom_match_live_frame_fence_ck check(
    membership_epoch>0 and generation>0 and tic>=-1 and
    ((tic=-1 and payload_bytes=0 and published_at is null) or
     (tic>=0 and payload_bytes=64000 and published_at is not null)))
) lob(payload_blob) store as securefile(cache logging retention none);

create index doom_match_live_frame_poll_ix on doom_match_live_frame(
  match_id,player_slot,membership_epoch,generation,tic);

-- Six complete uncompressed DPB2 frames share one persistent locator
-- crossing. The legacy per-frame ring above remains during migration so a
-- rollback artifact retains its original schema.
create table doom_match_live_frame_batch (
  match_id varchar2(32) not null,
  player_slot number(1) not null,
  ring_slot number(2) not null,
  membership_epoch number(12) not null,
  generation number(12) not null,
  first_tic number(12) default -1 not null,
  last_tic number(12) default -1 not null,
  frame_count number(2) default 0 not null,
  payload_bytes number(8) default 0 not null,
  payload_blob blob not null,
  published_at timestamp with time zone,
  constraint doom_match_live_frame_batch_pk
    primary key(match_id,player_slot,ring_slot),
  constraint doom_match_live_frame_batch_member_fk
    foreign key(match_id,player_slot)
    references doom_match_member(match_id,player_slot) on delete cascade,
  constraint doom_match_live_frame_batch_slot_ck check(
    player_slot between 0 and 3 and ring_slot between 0 and 63),
  constraint doom_match_live_frame_batch_fence_ck check(
    membership_epoch>0 and generation>0 and
    ((first_tic=-1 and last_tic=-1 and frame_count=0
       and payload_bytes=0 and published_at is null) or
     (first_tic>=0 and last_tic=first_tic+frame_count-1
       and frame_count between 1 and 6
       and payload_bytes=8+frame_count*64008
       and published_at is not null)))
) lob(payload_blob) store as securefile(cache logging retention none);

create index doom_match_live_frame_batch_poll_ix
  on doom_match_live_frame_batch(
    match_id,player_slot,membership_epoch,generation,first_tic,last_tic);

commit;
