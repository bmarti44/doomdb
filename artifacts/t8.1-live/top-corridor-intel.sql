set pagesize 100 linesize 220 feedback off
select l.linedef_id,l.flags,l.special,v1.x x1,v1.y y1,v2.x x2,v2.y y2,
       rs.sector_id rs,ls.sector_id ls
from doom_map_linedef l
join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
left join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
where greatest(v1.x,v2.x)>=620 and least(v1.x,v2.x)<=820
  and greatest(v1.y,v2.y)>=2180 and least(v1.y,v2.y)<=2320
order by l.linedef_id;
rollback;
