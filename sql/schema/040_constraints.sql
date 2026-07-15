alter table doom_map_thing add constraint doom_map_thing_type_fk
  foreign key (thing_type) references doom_thing_type_def (thing_type);
alter table doom_map_linedef add constraint doom_map_linedef_special_fk
  foreign key (special) references doom_linedef_special_def (special_id);
alter table doom_linedef add constraint doom_linedef_special_fk
  foreign key (special) references doom_linedef_special_def (special_id);
alter table doom_map_sector add constraint doom_map_sector_special_fk
  foreign key (special) references doom_sector_special_def (special_id);

create index doom_map_thing_type_ix on doom_map_thing (thing_type);
create index doom_map_sidedef_sector_ix on doom_map_sidedef (sector_id);
create index doom_map_linedef_vertices_ix on doom_map_linedef (start_vertex_id, end_vertex_id);
create index doom_map_seg_line_ix on doom_map_seg (linedef_id);
create index at_xy_ix on at (a, y, x);
create index mobjs_position_ix on mobjs (session_token, x, y);
create index tic_commands_tic_ix on tic_commands (session_token, tic);
create index game_events_type_ix on game_events (session_token, event_type, tic);
