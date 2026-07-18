set pagesize 1000 linesize 220 feedback off
select l.linedef_id,l.flags,l.special,l.tag,v1.x x1,v1.y y1,v2.x x2,v2.y y2,
       r.sector_id rs,le.sector_id ls
from doom_map_linedef l
join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
join doom_map_sidedef r on r.sidedef_id=l.right_sidedef_id
left join doom_map_sidedef le on le.sidedef_id=l.left_sidedef_id
where (r.sector_id in (57,101,102,103,112,113,114,144) or le.sector_id in (57,101,102,103,112,113,114,144))
order by l.linedef_id;
select sector_id,floor_height,ceiling_height,special,tag
from doom_map_sector where sector_id in (57,101,102,103,112,113,114,144);
rollback;
