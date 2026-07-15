-- T8.2 staged workflow state. Apply after T7.1/T7.2 and T6.4 history.
-- These columns are authoritative state and therefore must be added to the
-- canonical T6.4 serializer/restorer in the ordered integration turn.
alter table game_sessions add (
  menu_selection number(2) default 0 not null,
  god_mode number(1) default 0 not null,
  fullmap number(1) default 0 not null,
  workflow_generation number(12) default 0 not null,
  intermission_kills number(10),
  intermission_items number(10),
  intermission_secrets number(10),
  intermission_time_tics number(12),
  intermission_state_sha varchar2(64),
  intermission_frame_sha varchar2(64),
  constraint game_sessions_workflow_bool_ck check (
    god_mode in (0,1) and fullmap in (0,1)),
  constraint game_sessions_menu_selection_ck check (menu_selection between 0 and 4),
  constraint game_sessions_generation_ck check (workflow_generation >= 0),
  constraint game_sessions_intermission_ck check (
    (map_status <> 'DONE' and intermission_kills is null
      and intermission_items is null and intermission_secrets is null
      and intermission_time_tics is null and intermission_state_sha is null
      and intermission_frame_sha is null)
    or
    (map_status = 'DONE' and intermission_kills >= 0
      and intermission_items >= 0 and intermission_secrets >= 0
      and intermission_time_tics >= 0
      and ((intermission_state_sha is null and intermission_frame_sha is null)
        or (regexp_like(intermission_state_sha,'^[0-9a-f]{64}$')
          and regexp_like(intermission_frame_sha,'^[0-9a-f]{64}$')))))
);

-- Discovery is relational and session-scoped. The browser submits only the
-- automap toggle; it never submits projected coordinates or pixels.
create table automap_discovery (
  session_token varchar2(32) not null,
  linedef_id number(10) not null,
  discovered_tic number(12) not null,
  constraint automap_discovery_pk primary key(session_token,linedef_id),
  constraint automap_discovery_session_fk foreign key(session_token)
    references game_sessions(session_token) on delete cascade,
  constraint automap_discovery_line_fk foreign key(linedef_id)
    references doom_map_linedef(linedef_id),
  constraint automap_discovery_tic_ck check(discovered_tic >= 0)
);
