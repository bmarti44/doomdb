set pagesize 100 linesize 240 feedback off
select l.linedef_id,l.flags,l.special,l.tag,v1.x x1,v1.y y1,v2.x x2,v2.y y2,
       rs.sector_id right_sector,ls.sector_id left_sector
from doom_map_linedef l
join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
left join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
where rs.sector_id=81 or ls.sector_id=81
order by l.linedef_id;
select config_key,number_value from doom_config
where config_key in ('PLAYER_RADIUS','PLAYER_HEIGHT','PLAYER_STEP_HEIGHT')
order by config_key;
rollback;
