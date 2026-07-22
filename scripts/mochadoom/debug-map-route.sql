set serveroutput on size unlimited
set feedback off heading off pagesize 0 linesize 4000

declare
  l_source number;
  l_target number;
  type number_map is table of pls_integer index by pls_integer;
  l_queue number_map;l_parent number_map;l_seen number_map;
  l_head pls_integer:=1;l_tail pls_integer:=1;l_current pls_integer;
  l_path varchar2(4000);l_child pls_integer;l_guard pls_integer:=0;
  l_line number;l_x1 number;l_y1 number;l_x2 number;l_y2 number;
  l_special number;l_flags number;l_tag number;
begin
  dbms_output.put_line('START');
  select min(sector_id) into l_source from table(doom_bsp_locate(-176,426));
  select min(sector_id) into l_target from table(doom_bsp_locate(-384,1296));
  dbms_output.put_line('SOURCE_SECTOR '||l_source||' TARGET_SECTOR '||l_target);
  l_queue(1):=l_source;l_seen(l_source):=1;l_parent(l_source):=-1;
  while l_head<=l_tail loop
    l_current:=l_queue(l_head);l_head:=l_head+1;
    exit when l_current=l_target;
    for e in (
      select distinct case when rs.sector_id=l_current then ls.sector_id
                           else rs.sector_id end neighbor
      from doom_map_linedef l
      join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join doom_map_vertex sv on sv.vertex_id=l.start_vertex_id
      join doom_map_vertex ev on ev.vertex_id=l.end_vertex_id
      where l.left_sidedef_id is not null and bitand(l.flags,1)=0
        and power(ev.x-sv.x,2)+power(ev.y-sv.y,2)>=1600
        and l_current in(rs.sector_id,ls.sector_id)
    ) loop
      if not l_seen.exists(e.neighbor) then
        l_tail:=l_tail+1;l_queue(l_tail):=e.neighbor;
        l_seen(e.neighbor):=1;l_parent(e.neighbor):=l_current;
      end if;
    end loop;
  end loop;
  if not l_seen.exists(l_target) then
    raise_application_error(-20000,'target sector unreachable');
  end if;
  l_current:=l_target;
  while l_current<>-1 loop
    l_path:=case when l_path is null then to_char(l_current)
      else to_char(l_current)||','||l_path end;
    l_current:=l_parent(l_current);l_guard:=l_guard+1;
    if l_guard>1000 then raise_application_error(-20000,'parent cycle');end if;
  end loop;
  dbms_output.put_line('SECTOR_PATH '||l_path);
  for s in (select sector_id,floor_height,ceiling_height,special,tag
    from doom_map_sector where sector_id in
      (91,150,151,17,93,10,9,13,12,37,34,8,135,63,64,68,66,67)
    order by sector_id) loop
    dbms_output.put_line('SECTOR '||s.sector_id||' floor='||s.floor_height||
      ' ceiling='||s.ceiling_height||' special='||s.special||' tag='||s.tag);
  end loop;
  l_child:=l_target;
  while l_child<>l_source loop
    l_current:=l_parent(l_child);
    select linedef_id,x1,y1,x2,y2,special,flags,tag
      into l_line,l_x1,l_y1,l_x2,l_y2,l_special,l_flags,l_tag from (
      select l.linedef_id,sv.x x1,sv.y y1,ev.x x2,ev.y y2,
        l.special,l.flags,l.tag
      from doom_map_linedef l
      join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
      join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
      join doom_map_vertex sv on sv.vertex_id=l.start_vertex_id
      join doom_map_vertex ev on ev.vertex_id=l.end_vertex_id
      where bitand(l.flags,1)=0 and
        power(ev.x-sv.x,2)+power(ev.y-sv.y,2)>=1600 and
        ((rs.sector_id=l_current and ls.sector_id=l_child) or
         (rs.sector_id=l_child and ls.sector_id=l_current))
      order by l.linedef_id
    ) where rownum=1;
    dbms_output.put_line('PORTAL '||l_current||'->'||l_child||' line='||
      l_line||' mid=('||(l_x1+l_x2)/2||','||(l_y1+l_y2)/2||') segment=('||
      l_x1||','||l_y1||')->('||l_x2||','||l_y2||') special='||l_special||
      ' flags='||l_flags||' tag='||l_tag);
    l_child:=l_current;
  end loop;
  for r in (
    select l.linedef_id,l.special,l.flags,l.tag,
      rs.sector_id right_sector,ls.sector_id left_sector,
      sv.x x1,sv.y y1,ev.x x2,ev.y y2
    from doom_map_linedef l
    join doom_map_sidedef rs on rs.sidedef_id=l.right_sidedef_id
    left join doom_map_sidedef ls on ls.sidedef_id=l.left_sidedef_id
    join doom_map_vertex sv on sv.vertex_id=l.start_vertex_id
    join doom_map_vertex ev on ev.vertex_id=l.end_vertex_id
    where rs.sector_id in(l_source,l_target) or ls.sector_id in(l_source,l_target)
    order by l.linedef_id
  ) loop
    dbms_output.put_line('LINE '||r.linedef_id||' '||r.right_sector||'/'||
      nvl(to_char(r.left_sector),'-')||' ('||r.x1||','||r.y1||')->('||
      r.x2||','||r.y2||') special='||r.special||' flags='||r.flags||
      ' tag='||r.tag);
  end loop;
end;
/
