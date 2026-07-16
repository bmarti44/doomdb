whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

create table doom_collision_segment (
  linedef_id number(10) not null,
  flags number(10) not null,
  left_sector_id number(10),
  right_sector_id number(10) not null,
  start_vertex_id number(10) not null,
  end_vertex_id number(10) not null,
  x1 number not null,
  y1 number not null,
  x2 number not null,
  y2 number not null,
  min_x number not null,
  max_x number not null,
  min_y number not null,
  max_y number not null,
  segment_length number not null,
  direction_x number not null,
  direction_y number not null,
  constraint doom_collision_segment_pk primary key (linedef_id),
  constraint doom_collision_segment_line_fk foreign key (linedef_id)
    references doom_map_linedef (linedef_id),
  constraint doom_collision_segment_left_fk foreign key (left_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_collision_segment_right_fk foreign key (right_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_collision_segment_start_fk foreign key (start_vertex_id)
    references doom_map_vertex (vertex_id),
  constraint doom_collision_segment_end_fk foreign key (end_vertex_id)
    references doom_map_vertex (vertex_id),
  constraint doom_collision_segment_length_ck check (segment_length > 0),
  constraint doom_collision_segment_bounds_ck check
    (min_x <= max_x and min_y <= max_y)
);

insert into doom_collision_segment (
  linedef_id, flags, left_sector_id, right_sector_id,
  start_vertex_id, end_vertex_id, x1, y1, x2, y2,
  min_x, max_x, min_y, max_y, segment_length, direction_x, direction_y
)
select l.linedef_id,
  l.flags,
  ls.sector_id,
  rs.sector_id,
  ml.start_vertex_id,
  ml.end_vertex_id,
  sv.x,
  sv.y,
  ev.x,
  ev.y,
  least(sv.x, ev.x),
  greatest(sv.x, ev.x),
  least(sv.y, ev.y),
  greatest(sv.y, ev.y),
  l.length,
  l.direction_x,
  l.direction_y
from doom_linedef l
join doom_map_linedef ml on ml.linedef_id = l.linedef_id
join doom_map_vertex sv on sv.vertex_id = ml.start_vertex_id
join doom_map_vertex ev on ev.vertex_id = ml.end_vertex_id
join doom_map_sidedef rs on rs.sidedef_id = ml.right_sidedef_id
left join doom_map_sidedef ls on ls.sidedef_id = ml.left_sidedef_id;

commit;
