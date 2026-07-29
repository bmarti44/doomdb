whenever sqlerror exit failure rollback
set define off

-- Diagnostic-only, windowed decomposition of database frame generation and
-- persistent-locator publication. Ordinary matches never write this table.
create table doom_match_frame_stage_window (
  match_id varchar2(32) not null,
  generation number(12) not null,
  window_first_tic number(12) not null,
  window_last_tic number(12) not null,
  rendered_tics number(6) not null,
  rendered_views number(8) not null,
  render_total_ms number not null,
  render_max_ms number not null,
  publish_total_ms number not null,
  publish_max_ms number not null,
  recorded_at timestamp with time zone default
    (localtimestamp at time zone 'UTC') not null,
  constraint doom_match_frame_stage_window_pk primary key(
    match_id,generation,window_last_tic),
  constraint doom_match_frame_stage_window_match_fk foreign key(match_id)
    references doom_match(match_id) on delete cascade,
  constraint doom_match_frame_stage_window_tics_ck check(
    window_first_tic>=1 and window_last_tic>=window_first_tic and
    rendered_tics between 1 and 100 and rendered_views>=rendered_tics),
  constraint doom_match_frame_stage_window_ms_ck check(
    render_total_ms>=0 and render_max_ms>=0 and
    publish_total_ms>=0 and publish_max_ms>=0)
);

commit;
