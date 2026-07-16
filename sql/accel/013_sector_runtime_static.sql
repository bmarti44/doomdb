whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

create table doom_sector_runtime_static (
  sector_id number(10) not null,
  min_neighbor_light number(3) not null,
  constraint doom_sector_runtime_static_pk primary key (sector_id),
  constraint doom_sector_runtime_static_sector_fk foreign key (sector_id)
    references doom_map_sector (sector_id),
  constraint doom_sector_runtime_static_light_ck check
    (min_neighbor_light between 0 and 255)
);

insert into doom_sector_runtime_static (sector_id, min_neighbor_light)
with neighbors (source_sector_id, target_sector_id) as (
  select rs.sector_id, ls.sector_id
  from doom_map_linedef ml
  join doom_map_sidedef rs on rs.sidedef_id = ml.right_sidedef_id
  join doom_map_sidedef ls on ls.sidedef_id = ml.left_sidedef_id
  union all
  select ls.sector_id, rs.sector_id
  from doom_map_linedef ml
  join doom_map_sidedef rs on rs.sidedef_id = ml.right_sidedef_id
  join doom_map_sidedef ls on ls.sidedef_id = ml.left_sidedef_id
)
select source.sector_id,
  coalesce(min(target.light_level), source.light_level)
from doom_map_sector source
left join neighbors edge on edge.source_sector_id = source.sector_id
left join doom_map_sector target on target.sector_id = edge.target_sector_id
group by source.sector_id, source.light_level;

begin
  dbms_stats.gather_table_stats(user, 'DOOM_SECTOR_RUNTIME_STATIC', cascade => true);
end;
/

commit;
