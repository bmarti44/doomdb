-- T3.4 relational acceleration structures.
-- Source data is the checked-in WAD byte relations; no map-specific values are
-- embedded here.  BLOCKMAP words are unsigned little-endian except for its
-- signed origin coordinates.

create table doom_block_cell (
  cell_id number(10) not null,
  block_x number(10) not null,
  block_y number(10) not null,
  world_min_x number(10) not null,
  world_min_y number(10) not null,
  list_word_offset number(10) not null,
  constraint doom_block_cell_pk primary key (cell_id),
  constraint doom_block_cell_xy_uq unique (block_x, block_y),
  constraint doom_block_cell_id_ck check (cell_id >= 0),
  constraint doom_block_cell_xy_ck check (block_x >= 0 and block_y >= 0),
  constraint doom_block_cell_list_ck check (list_word_offset >= 0)
);

create table doom_block_line (
  cell_id number(10) not null,
  line_ordinal number(10) not null,
  linedef_id number(10) not null,
  constraint doom_block_line_pk primary key (cell_id, line_ordinal),
  constraint doom_block_line_cell_fk foreign key (cell_id)
    references doom_block_cell (cell_id),
  constraint doom_block_line_linedef_fk foreign key (linedef_id)
    references doom_map_linedef (linedef_id),
  constraint doom_block_line_ord_ck check (line_ordinal >= 0)
);

create table doom_sector_reject (
  source_sector_id number(10) not null,
  target_sector_id number(10) not null,
  rejected number(1) not null,
  byte_offset number(10) not null,
  bit_offset number(1) not null,
  constraint doom_sector_reject_pk primary key (source_sector_id, target_sector_id),
  constraint doom_sector_reject_source_fk foreign key (source_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_sector_reject_target_fk foreign key (target_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_sector_reject_bit_ck check (rejected in (0, 1)),
  constraint doom_sector_reject_address_ck check (byte_offset >= 0 and bit_offset between 0 and 7)
);

create table doom_sector_edge (
  edge_id number(10) not null,
  source_sector_id number(10) not null,
  target_sector_id number(10) not null,
  linedef_id number(10) not null,
  sound_block number(1) not null,
  opening number not null,
  constraint doom_sector_edge_pk primary key (edge_id),
  constraint doom_sector_edge_source_fk foreign key (source_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_sector_edge_target_fk foreign key (target_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_sector_edge_linedef_fk foreign key (linedef_id)
    references doom_map_linedef (linedef_id),
  constraint doom_sector_edge_direction_ck check (edge_id in (linedef_id * 2, linedef_id * 2 + 1)),
  constraint doom_sector_edge_distinct_ck check (source_sector_id != target_sector_id),
  constraint doom_sector_edge_sound_ck check (sound_block in (0, 1)),
  constraint doom_sector_edge_opening_ck check (opening > 0)
);

-- Exact immutable reachability over non-sound-blocking sector edges. Runtime
-- monster perception consults this closure instead of executing one procedural
-- breadth-first traversal (and thousands of SQL statements) per sleeping actor.
create table doom_sector_sound_reach (
  source_sector_id number(10) not null,
  target_sector_id number(10) not null,
  constraint doom_sector_sound_reach_pk
    primary key (source_sector_id, target_sector_id),
  constraint doom_sector_sound_reach_source_fk foreign key (source_sector_id)
    references doom_map_sector (sector_id),
  constraint doom_sector_sound_reach_target_fk foreign key (target_sector_id)
    references doom_map_sector (sector_id)
);

-- Immutable determinant inputs for exact simulation line-of-sight. Dynamic
-- floor/ceiling values remain session rows joined by the two sector IDs.
create table doom_los_segment (
  linedef_id number(10) not null,
  vx number not null,
  vy number not null,
  sx number not null,
  sy number not null,
  right_sector_id number(10) not null,
  left_sector_id number(10),
  constraint doom_los_segment_pk primary key(linedef_id),
  constraint doom_los_segment_line_fk foreign key(linedef_id)
    references doom_map_linedef(linedef_id),
  constraint doom_los_segment_right_fk foreign key(right_sector_id)
    references doom_map_sector(sector_id),
  constraint doom_los_segment_left_fk foreign key(left_sector_id)
    references doom_map_sector(sector_id)
);

create index doom_block_line_linedef_ix on doom_block_line (linedef_id);
create index doom_sector_reject_target_ix on doom_sector_reject (target_sector_id, source_sector_id);
create index doom_sector_edge_target_ix on doom_sector_edge (target_sector_id, source_sector_id);

insert into doom_block_cell (
  cell_id, block_x, block_y, world_min_x, world_min_y, list_word_offset
)
with
  wad_word as (
    select b0.byte_offset / 2 as word_offset,
           b0.byte_value + b1.byte_value * 256 as unsigned_word
      from doom_blockmap_byte b0
      join doom_blockmap_byte b1 on b1.byte_offset = b0.byte_offset + 1
     where mod(b0.byte_offset, 2) = 0
  ),
  block_header as (
    select case when ox.unsigned_word >= 32768 then ox.unsigned_word - 65536 else ox.unsigned_word end as origin_x,
           case when oy.unsigned_word >= 32768 then oy.unsigned_word - 65536 else oy.unsigned_word end as origin_y,
           cols.unsigned_word as column_count,
           rows_.unsigned_word as row_count
      from wad_word ox
      join wad_word oy on oy.word_offset = 1
      join wad_word cols on cols.word_offset = 2
      join wad_word rows_ on rows_.word_offset = 3
     where ox.word_offset = 0
  ),
  cell_number as (
    select level - 1 as cell_id
      from block_header
    connect by level <= column_count * row_count
  )
select n.cell_id,
       mod(n.cell_id, h.column_count) as block_x,
       floor(n.cell_id / h.column_count) as block_y,
       h.origin_x + mod(n.cell_id, h.column_count) * 128 as world_min_x,
       h.origin_y + floor(n.cell_id / h.column_count) * 128 as world_min_y,
       list_word.unsigned_word as list_word_offset
  from cell_number n
  cross join block_header h
  join wad_word list_word on list_word.word_offset = 4 + n.cell_id;

insert into doom_block_line (cell_id, line_ordinal, linedef_id)
with
  wad_word as (
    select b0.byte_offset / 2 as word_offset,
           b0.byte_value + b1.byte_value * 256 as unsigned_word,
           min(case when b0.byte_value + b1.byte_value * 256 = 65535 then b0.byte_offset / 2 end)
             over (order by b0.byte_offset rows between current row and unbounded following) as next_terminator
      from doom_blockmap_byte b0
      join doom_blockmap_byte b1 on b1.byte_offset = b0.byte_offset + 1
     where mod(b0.byte_offset, 2) = 0
  )
select c.cell_id,
       member_word.word_offset - c.list_word_offset - 1 as line_ordinal,
       member_word.unsigned_word as linedef_id
  from doom_block_cell c
  join wad_word list_header on list_header.word_offset = c.list_word_offset
  join wad_word member_word
    on member_word.word_offset > c.list_word_offset
   and member_word.word_offset < list_header.next_terminator
 where list_header.unsigned_word = 0;

insert into doom_sector_reject (
  source_sector_id, target_sector_id, rejected, byte_offset, bit_offset
)
with
  sector_count as (select count(*) as n from doom_map_sector),
  pair_address as (
    select source.sector_id as source_sector_id,
           target.sector_id as target_sector_id,
           source.sector_id * count_.n + target.sector_id as bit_address
      from doom_map_sector source
      cross join doom_map_sector target
      cross join sector_count count_
  )
select p.source_sector_id,
       p.target_sector_id,
       bitand(b.byte_value, power(2, mod(p.bit_address, 8))) /
         power(2, mod(p.bit_address, 8)) as rejected,
       floor(p.bit_address / 8) as byte_offset,
       mod(p.bit_address, 8) as bit_offset
  from pair_address p
  join doom_reject_byte b on b.byte_offset = floor(p.bit_address / 8);

insert into doom_sector_edge (
  edge_id, source_sector_id, target_sector_id, linedef_id, sound_block, opening
)
with eligible_connection as (
  select l.linedef_id,
         right_side.sector_id as right_sector_id,
         left_side.sector_id as left_sector_id,
         case when bitand(l.flags, 64) = 64 then 1 else 0 end as sound_block,
         least(right_sector.ceiling_height, left_sector.ceiling_height) -
           greatest(right_sector.floor_height, left_sector.floor_height) as opening
    from doom_map_linedef l
    join doom_map_sidedef right_side on right_side.sidedef_id = l.right_sidedef_id
    join doom_map_sidedef left_side on left_side.sidedef_id = l.left_sidedef_id
    join doom_map_sector right_sector on right_sector.sector_id = right_side.sector_id
    join doom_map_sector left_sector on left_sector.sector_id = left_side.sector_id
   where l.left_sidedef_id is not null
     and right_side.sector_id != left_side.sector_id
     and least(right_sector.ceiling_height, left_sector.ceiling_height) -
           greatest(right_sector.floor_height, left_sector.floor_height) > 0
), direction_ (direction) as (
  select 0 from dual union all select 1 from dual
)
select c.linedef_id * 2 + d.direction as edge_id,
       case d.direction when 0 then c.right_sector_id else c.left_sector_id end as source_sector_id,
       case d.direction when 0 then c.left_sector_id else c.right_sector_id end as target_sector_id,
       c.linedef_id,
       c.sound_block,
       c.opening
  from eligible_connection c
  cross join direction_ d;

insert into doom_sector_sound_reach(source_sector_id,target_sector_id)
select sector_id,sector_id from doom_map_sector
union
select source_sector_id,target_sector_id
from doom_sector_edge where sound_block=0;

declare
  l_added pls_integer;
begin
  loop
    merge into doom_sector_sound_reach d
    using (
      select distinct r.source_sector_id,e.target_sector_id
      from doom_sector_sound_reach r
      join doom_sector_edge e on e.source_sector_id=r.target_sector_id
      where e.sound_block=0
    ) s
    on (d.source_sector_id=s.source_sector_id
        and d.target_sector_id=s.target_sector_id)
    when not matched then insert(source_sector_id,target_sector_id)
      values(s.source_sector_id,s.target_sector_id);
    l_added:=sql%rowcount;
    exit when l_added=0;
  end loop;
end;
/

insert into doom_los_segment(
  linedef_id,vx,vy,sx,sy,right_sector_id,left_sector_id
)
select l.linedef_id,v1.x,v1.y,v2.x-v1.x,v2.y-v1.y,
  rs.sector_id,ls.sector_id
from doom_map_linedef l
join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
left join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id;

create property graph doom_sector_graph
  vertex tables (
    doom_map_sector
      key (sector_id)
      label sector
      properties (sector_id, floor_height, ceiling_height, light_level, special, tag)
  )
  edge tables (
    doom_sector_edge
      key (edge_id)
      source key (source_sector_id) references doom_map_sector (sector_id)
      destination key (target_sector_id) references doom_map_sector (sector_id)
      label passable
      properties (edge_id, linedef_id, sound_block, opening)
  );

-- Exercise the graph through its SQL interface during installation.  This is
-- also a fail-closed capability check: an unsupported or invalid graph aborts.
select count(*)
  from graph_table(
    doom_sector_graph
    match (source is sector)-[connection is passable]->(target is sector)
    columns (connection.edge_id as edge_id)
  );

commit;
