set pagesize 1000 linesize 240 trimspool on feedback off heading on
select thing_id,thing_type,x,y,angle,flags
from doom_map_thing
where thing_type in (5,6,13,38,2011,2012,2015,2018,2019,2022,2023,2028,2048,8,2001,2002,2005)
order by thing_type,thing_id;

select l.linedef_id,l.special,l.tag,v1.x x1,v1.y y1,v2.x x2,v2.y y2,
       f.sector_id front_sector,b.sector_id back_sector,
       sf.floor_height front_floor,sb.floor_height back_floor
from doom_map_linedef l
join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
left join doom_map_sidedef f on f.sidedef_id=l.right_sidedef_id
left join doom_map_sidedef b on b.sidedef_id=l.left_sidedef_id
left join doom_map_sector sf on sf.sector_id=f.sector_id
left join doom_map_sector sb on sb.sector_id=b.sector_id
where l.special<>0
order by l.special,l.linedef_id;

select sector_id,floor_height,ceiling_height,special,tag
from doom_map_sector
where special<>0 or tag<>0
order by sector_id;
rollback;
