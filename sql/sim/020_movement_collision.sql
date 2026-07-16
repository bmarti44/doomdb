whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

alter table players add (
  noclip number(1) default 0 not null,
  constraint players_noclip_ck check (noclip in (0, 1))
);

merge into doom_config d
using (
  select 'PLAYER_RADIUS' config_key, 16 number_value from dual union all
  select 'PLAYER_HEIGHT', 56 from dual union all
  select 'PLAYER_STEP_HEIGHT', 24 from dual union all
  select 'PLAYER_VIEW_HEIGHT', 41 from dual union all
  select 'PLAYER_MAX_CONTACTS', 2 from dual
) s
on (d.config_key = s.config_key)
when matched then update set d.number_value=s.number_value,d.text_value=null
when not matched then insert(config_key,number_value,text_value)
values(s.config_key,s.number_value,null);

-- Narrow Doom-compatible exception for a one-sided jamb endpoint shared by a
-- crossed, currently open portal into a sub-diameter sector with a second
-- parallel open portal. Ordinary endpoint tangency remains blocking.
create or replace function doom_thin_portal_graze(
  p_session varchar2,p_blocking_linedef number,p_vertex_id number,
  p_x number,p_y number,p_dx number,p_dy number,p_z number,
  p_radius number,p_height number,p_step number
) return number
is
  l_count number;
begin
  select count(*) into l_count
  from doom_map_linedef jamb
  join doom_map_sidedef jamb_side on jamb_side.sidedef_id=jamb.right_sidedef_id
  join doom_map_vertex jamb_vertex on jamb_vertex.vertex_id=p_vertex_id
  where jamb.linedef_id=p_blocking_linedef
    and jamb.left_sidedef_id is null
    and exists (
      select 1
      from doom_map_linedef portal
      join doom_linedef pg on pg.linedef_id=portal.linedef_id
      join doom_map_vertex pv on pv.vertex_id=portal.start_vertex_id
      join doom_map_sidedef pr on pr.sidedef_id=portal.right_sidedef_id
      join doom_map_sidedef pl on pl.sidedef_id=portal.left_sidedef_id
      join doom_map_sector prm on prm.sector_id=pr.sector_id
      join doom_map_sector plm on plm.sector_id=pl.sector_id
      left join sector_state prs on prs.session_token=p_session and prs.sector_id=pr.sector_id
      left join sector_state pls on pls.session_token=p_session and pls.sector_id=pl.sector_id
      where portal.linedef_id<>jamb.linedef_id
        and p_vertex_id in(portal.start_vertex_id,portal.end_vertex_id)
        and jamb_side.sector_id in(pr.sector_id,pl.sector_id)
        and bitand(portal.flags,1)=0
        and greatest(coalesce(prs.floor_height,prm.floor_height),
                     coalesce(pls.floor_height,plm.floor_height))-p_z<=p_step
        and least(coalesce(prs.ceiling_height,prm.ceiling_height),
                  coalesce(pls.ceiling_height,plm.ceiling_height))
             -greatest(p_z,greatest(coalesce(prs.floor_height,prm.floor_height),
                                    coalesce(pls.floor_height,plm.floor_height)))>=p_height
        and ((p_x-pv.x)*(-pg.direction_y)+(p_y-pv.y)*pg.direction_x)
            *((p_x+p_dx-pv.x)*(-pg.direction_y)
              +(p_y+p_dy-pv.y)*pg.direction_x)<=0
        and exists (
          select 1
          from doom_map_linedef paired
          join doom_linedef qg on qg.linedef_id=paired.linedef_id
          join doom_map_vertex qv on qv.vertex_id=paired.start_vertex_id
          join doom_map_sidedef qr on qr.sidedef_id=paired.right_sidedef_id
          join doom_map_sidedef ql on ql.sidedef_id=paired.left_sidedef_id
          join doom_map_sector qrm on qrm.sector_id=qr.sector_id
          join doom_map_sector qlm on qlm.sector_id=ql.sector_id
          left join sector_state qrs on qrs.session_token=p_session and qrs.sector_id=qr.sector_id
          left join sector_state qls on qls.session_token=p_session and qls.sector_id=ql.sector_id
          where paired.linedef_id not in(portal.linedef_id,jamb.linedef_id)
            and paired.left_sidedef_id is not null
            and (qr.sector_id in(pr.sector_id,pl.sector_id)
                 or ql.sector_id in(pr.sector_id,pl.sector_id))
            and bitand(paired.flags,1)=0
            and abs(pg.direction_x*qg.direction_x+pg.direction_y*qg.direction_y)>.999999999
            and power(jamb_vertex.x-(qv.x+greatest(0,least(qg.length,
                   (jamb_vertex.x-qv.x)*qg.direction_x+
                   (jamb_vertex.y-qv.y)*qg.direction_y))*qg.direction_x),2)
               +power(jamb_vertex.y-(qv.y+greatest(0,least(qg.length,
                   (jamb_vertex.x-qv.x)*qg.direction_x+
                   (jamb_vertex.y-qv.y)*qg.direction_y))*qg.direction_y),2)
                  <power(2*p_radius,2)
            and greatest(coalesce(qrs.floor_height,qrm.floor_height),
                         coalesce(qls.floor_height,qlm.floor_height))-p_z<=p_step
            and least(coalesce(qrs.ceiling_height,qrm.ceiling_height),
                      coalesce(qls.ceiling_height,qlm.ceiling_height))
                 -greatest(p_z,greatest(coalesce(qrs.floor_height,qrm.floor_height),
                                        coalesce(qls.floor_height,qlm.floor_height)))>=p_height
        )
    );
  return case when l_count>0 then 1 else 0 end;
end;
/

-- One exact relational sweep. DOOM_COLLISION_SEGMENT is the bootstrap-packed
-- projection of DOOM_MAP_LINEDEF, DOOM_MAP_SIDEDEF, DOOM_LINEDEF, and their
-- endpoint vertices. Its swept-circle AABB is a mathematically conservative
-- broad phase: every finite segment that touches the moving circle overlaps
-- this box, so candidate reduction cannot remove a true contact. DOOM_BLOCK_LINE
-- remains the independent WAD acceleration oracle but is not needed here.
create or replace function doom_sweep_contact(
  p_session varchar2, p_x number, p_y number, p_z number,
  p_dx number, p_dy number, p_radius number, p_height number,
  p_step number, p_exclude_linedef number
) return varchar2
is
  l_contact varchar2(4000);
begin
  select json_object(
           'linedef_id' value winner.linedef_id,
           'contact_t' value winner.contact_t,
           'direction_x' value winner.direction_x,
           'direction_y' value winner.direction_y
           returning varchar2
         )
    into l_contact
    from (
      select exact_line.*,
             row_number() over(order by contact_t, linedef_id) contact_rank
      from (
        select roots.linedef_id, roots.direction_x, roots.direction_y,
               min(roots.contact_t) contact_t
        from (
          -- The two signed-distance roots cover the finite segment body.
          select body.linedef_id, body.direction_x, body.direction_y, body.contact_t
          from (
            select geom.*, side.side,
                   ((side.side*p_radius)
                     - ((p_x-geom.x1)*(-geom.direction_y)
                       +(p_y-geom.y1)*geom.direction_x))
                   / nullif(p_dx*(-geom.direction_y)+p_dy*geom.direction_x,0) contact_t
            from (
              select l.linedef_id,l.flags,l.left_sector_id left_sidedef_id,
                     l.x1,l.y1,l.x2,l.y2,
                     l.segment_length length,l.direction_x,l.direction_y,
                     sr.floor_height right_floor,sr.ceiling_height right_ceiling,
                     sl.floor_height left_floor,sl.ceiling_height left_ceiling
              from doom_collision_segment l
              join sector_state sr on sr.session_token=p_session
                and sr.sector_id=l.right_sector_id
              left join sector_state sl on sl.session_token=p_session
                and sl.sector_id=l.left_sector_id
              where (p_exclude_linedef is null or l.linedef_id<>p_exclude_linedef)
                and l.min_x<=greatest(p_x,p_x+p_dx)+p_radius
                and l.max_x>=least(p_x,p_x+p_dx)-p_radius
                and l.min_y<=greatest(p_y,p_y+p_dy)+p_radius
                and l.max_y>=least(p_y,p_y+p_dy)-p_radius
                and (l.left_sector_id is null
                  or bitand(l.flags,1)<>0
                  -- Portal bottom is GREATEST live FLOOR_HEIGHT; portal top is
                  -- LEAST live CEILING_HEIGHT, never static map heights.
                  or greatest(sr.floor_height,sl.floor_height)-p_z>p_step
                  or least(sr.ceiling_height,sl.ceiling_height)
                       -greatest(sr.floor_height,sl.floor_height)<p_height
                  or least(sr.ceiling_height,sl.ceiling_height)
                       -greatest(p_z,greatest(sr.floor_height,sl.floor_height))<p_height)
            ) geom
            cross join (select -1 side from dual union all select 1 from dual) side
          ) body
          where body.contact_t between 0 and 1
            and ((p_x+body.contact_t*p_dx-body.x1)*body.direction_x
               +(p_y+body.contact_t*p_dy-body.y1)*body.direction_y)
                  between 0 and body.length
            and body.side*(p_dx*(-body.direction_y)+p_dy*body.direction_x)<0
          union all
          -- Quadratic entry roots cover both circular endpoint caps.
          select cap.linedef_id,cap.direction_x,cap.direction_y,cap.contact_t
          from (
            select disc.*,
                   (-disc.qb-sqrt(greatest(0,disc.discriminant)))
                     /nullif(2*disc.qa,0) contact_t
            from (
              select coeff.*,
                     power(coeff.qb,2)-4*coeff.qa*
                       (power(p_x-coeff.ex,2)+power(p_y-coeff.ey,2)-power(p_radius,2)) discriminant
              from (
                select geom.*,endpoint.endpoint_no,
                       case endpoint.endpoint_no when 0 then geom.start_vertex_id else geom.end_vertex_id end endpoint_vertex_id,
                       case endpoint.endpoint_no when 0 then geom.x1 else geom.x2 end ex,
                       case endpoint.endpoint_no when 0 then geom.y1 else geom.y2 end ey,
                       power(p_dx,2)+power(p_dy,2) qa,
                       2*((p_x-case endpoint.endpoint_no when 0 then geom.x1 else geom.x2 end)*p_dx
                         +(p_y-case endpoint.endpoint_no when 0 then geom.y1 else geom.y2 end)*p_dy) qb
                from (
                  select l.linedef_id,l.flags,l.left_sector_id left_sidedef_id,
                         l.start_vertex_id,l.end_vertex_id,
                         l.x1,l.y1,l.x2,l.y2,
                         l.segment_length length,l.direction_x,l.direction_y,
                         sr.floor_height right_floor,sr.ceiling_height right_ceiling,
                         sl.floor_height left_floor,sl.ceiling_height left_ceiling
                  from doom_collision_segment l
                  join sector_state sr on sr.session_token=p_session
                    and sr.sector_id=l.right_sector_id
                  left join sector_state sl on sl.session_token=p_session
                    and sl.sector_id=l.left_sector_id
                  where (p_exclude_linedef is null or l.linedef_id<>p_exclude_linedef)
                    and l.min_x<=greatest(p_x,p_x+p_dx)+p_radius
                    and l.max_x>=least(p_x,p_x+p_dx)-p_radius
                    and l.min_y<=greatest(p_y,p_y+p_dy)+p_radius
                    and l.max_y>=least(p_y,p_y+p_dy)-p_radius
                    and (l.left_sector_id is null or bitand(l.flags,1)<>0
                      or greatest(sr.floor_height,sl.floor_height)-p_z>p_step
                      or least(sr.ceiling_height,sl.ceiling_height)
                           -greatest(sr.floor_height,sl.floor_height)<p_height
                      or least(sr.ceiling_height,sl.ceiling_height)
                           -greatest(p_z,greatest(sr.floor_height,sl.floor_height))<p_height)
                ) geom
                cross join (select 0 endpoint_no from dual union all select 1 from dual) endpoint
              ) coeff
              where coeff.qa>0
            ) disc
            where disc.discriminant>=0
          ) cap
          where cap.contact_t between 0 and 1
            and (
              ((p_x+cap.contact_t*p_dx-cap.ex)*p_dx
                +(p_y+cap.contact_t*p_dy-cap.ey)*p_dy)<0
              or (
                ((p_x+cap.contact_t*p_dx-cap.ex)*p_dx
                  +(p_y+cap.contact_t*p_dy-cap.ey)*p_dy)=0
                and doom_thin_portal_graze(p_session,cap.linedef_id,
                      cap.endpoint_vertex_id,p_x,p_y,p_dx,p_dy,p_z,
                      p_radius,p_height,p_step)=0
              )
            )
        ) roots
        group by roots.linedef_id,roots.direction_x,roots.direction_y
      ) exact_line
    ) winner
   where winner.contact_rank=1;
  return l_contact;
exception when no_data_found then return null;
end;
/

-- A center may change sectors only by crossing the finite span of a currently
-- open two-sided portal. Two hops cover a sub-diameter throat crossed in one
-- movement (for example E1M1 sector 81) without accepting a phantom BSP
-- partition transition beyond the finite map boundary.
create or replace function doom_portal_transition_ok(
  p_session varchar2,p_x number,p_y number,p_z number,
  p_dest_x number,p_dest_y number,p_radius number,p_height number,p_step number,
  p_start_sector number,p_dest_sector number
) return number
is
  l_count number;
begin
  if p_start_sector=p_dest_sector then return 1;end if;
  with crossed as (
    select l.linedef_id,r.sector_id right_sector,le.sector_id left_sector
    from doom_map_linedef l
    join doom_map_vertex v1 on v1.vertex_id=l.start_vertex_id
    join doom_map_vertex v2 on v2.vertex_id=l.end_vertex_id
    join doom_map_sidedef r on r.sidedef_id=l.right_sidedef_id
    join doom_map_sidedef le on le.sidedef_id=l.left_sidedef_id
    join doom_map_sector rm on rm.sector_id=r.sector_id
    join doom_map_sector lm on lm.sector_id=le.sector_id
    left join sector_state rs on rs.session_token=p_session and rs.sector_id=r.sector_id
    left join sector_state ls on ls.session_token=p_session and ls.sector_id=le.sector_id
    where bitand(l.flags,1)=0
      and (r.sector_id in(p_start_sector,p_dest_sector)
           or le.sector_id in(p_start_sector,p_dest_sector))
      and greatest(v1.x,v2.x)>=least(p_x,p_dest_x)
      and least(v1.x,v2.x)<=greatest(p_x,p_dest_x)
      and greatest(v1.y,v2.y)>=least(p_y,p_dest_y)
      and least(v1.y,v2.y)<=greatest(p_y,p_dest_y)
      and greatest(coalesce(rs.floor_height,rm.floor_height),
                   coalesce(ls.floor_height,lm.floor_height))-p_z<=p_step
      and least(coalesce(rs.ceiling_height,rm.ceiling_height),
                coalesce(ls.ceiling_height,lm.ceiling_height))
           -greatest(p_z,greatest(coalesce(rs.floor_height,rm.floor_height),
                                  coalesce(ls.floor_height,lm.floor_height)))>=p_height
      and ((v2.x-v1.x)*(p_y-v1.y)-(v2.y-v1.y)*(p_x-v1.x))
          *((v2.x-v1.x)*(p_dest_y-v1.y)
             -(v2.y-v1.y)*(p_dest_x-v1.x))<=0
      and ((p_dest_x-p_x)*(v1.y-p_y)-(p_dest_y-p_y)*(v1.x-p_x))
          *((p_dest_x-p_x)*(v2.y-p_y)
             -(p_dest_y-p_y)*(v2.x-p_x))<=0
  ), edges as (
    select right_sector from_sector,left_sector to_sector from crossed
    union all
    select left_sector,right_sector from crossed
  )
  select count(*) into l_count from dual
  where exists(select 1 from edges
                where from_sector=p_start_sector and to_sector=p_dest_sector)
     or exists(select 1 from edges a join edges b
                 on b.from_sector=a.to_sector
                where a.from_sector=p_start_sector
                  and b.to_sector=p_dest_sector);
  if l_count=0 then
    select count(*) into l_count
    from doom_map_linedef l
    cross join lateral (
      select l.start_vertex_id vertex_id from dual union all
      select l.end_vertex_id from dual
    ) endpoint
    join doom_map_vertex ev on ev.vertex_id=endpoint.vertex_id
    cross join lateral (
      select -((p_x-ev.x)*(p_dest_x-p_x)+(p_y-ev.y)*(p_dest_y-p_y))
             /(power(p_dest_x-p_x,2)+power(p_dest_y-p_y,2)) contact_t
      from dual
    ) tangent
    where l.left_sidedef_id is null
      and power(p_dest_x-p_x,2)+power(p_dest_y-p_y,2)>0
      and ev.x between least(p_x,p_dest_x)-p_radius
                   and greatest(p_x,p_dest_x)+p_radius
      and ev.y between least(p_y,p_dest_y)-p_radius
                   and greatest(p_y,p_dest_y)+p_radius
      and case when tangent.contact_t between 0 and 1
                 and abs(power(p_x+tangent.contact_t*(p_dest_x-p_x)-ev.x,2)
                        +power(p_y+tangent.contact_t*(p_dest_y-p_y)-ev.y,2)
                        -power(p_radius,2))<0.0000000001
               then doom_thin_portal_graze(p_session,l.linedef_id,
                      endpoint.vertex_id,p_x,p_y,p_dest_x-p_x,p_dest_y-p_y,
                      p_z,p_radius,p_height,p_step)
               else 0 end=1;
  end if;
  return case when l_count>0 then 1 else 0 end;
end;
/

-- Fixed two-contact orchestration. Each contact itself is selected by one
-- set-based exact query; no procedural geometry iteration or dynamic SQL exists.
create or replace function doom_player_move_payload(
  p_session varchar2,p_delta_x number,p_delta_y number
) return clob
is
  l_player_id number;l_start_x number;l_start_y number;l_start_z number;l_noclip number;
  l_radius number;l_height number;l_step number;l_view number;l_max_contacts number;
  l_x number;l_y number;l_rem_x number;l_rem_y number;
  l_first varchar2(4000);l_second varchar2(4000);
  l_first_id number;l_first_t number;l_first_ux number;l_first_uy number;
  l_second_id number;l_second_t number;l_sector number;l_start_sector number;
  l_floor number;
begin
  select p.player_id,p.x,p.y,p.z,p.noclip,
         max(case when c.config_key='PLAYER_RADIUS' then c.number_value end),
         max(case when c.config_key='PLAYER_HEIGHT' then c.number_value end),
         max(case when c.config_key='PLAYER_STEP_HEIGHT' then c.number_value end),
         max(case when c.config_key='PLAYER_VIEW_HEIGHT' then c.number_value end),
         max(case when c.config_key='PLAYER_MAX_CONTACTS' then c.number_value end)
    into l_player_id,l_start_x,l_start_y,l_start_z,l_noclip,
         l_radius,l_height,l_step,l_view,l_max_contacts
    from game_sessions g
    join players p on p.session_token=g.session_token and p.player_id=g.current_player_id
    cross join doom_config c
   where g.session_token=p_session
     and c.config_key in('PLAYER_RADIUS','PLAYER_HEIGHT','PLAYER_STEP_HEIGHT',
                         'PLAYER_VIEW_HEIGHT','PLAYER_MAX_CONTACTS')
   group by p.player_id,p.x,p.y,p.z,p.noclip;

  l_x:=l_start_x;l_y:=l_start_y;l_rem_x:=p_delta_x;l_rem_y:=p_delta_y;
  select sector_id into l_start_sector
    from table(doom_bsp_locate(l_start_x,l_start_y)) where rownum=1;
  if l_noclip=0 and (l_rem_x<>0 or l_rem_y<>0) then
    l_first:=doom_sweep_contact(p_session,l_x,l_y,l_start_z,l_rem_x,l_rem_y,
                                l_radius,l_height,l_step,null);
  end if;
  if l_first is not null then
    l_first_id:=json_value(l_first,'$.linedef_id' returning number);
    l_first_t:=json_value(l_first,'$.contact_t' returning number);
    l_first_ux:=json_value(l_first,'$.direction_x' returning number);
    l_first_uy:=json_value(l_first,'$.direction_y' returning number);
    l_x:=l_x+p_delta_x*l_first_t;l_y:=l_y+p_delta_y*l_first_t;
    l_rem_x:=(p_delta_x*(1-l_first_t)*l_first_ux
             +p_delta_y*(1-l_first_t)*l_first_uy)*l_first_ux;
    l_rem_y:=(p_delta_x*(1-l_first_t)*l_first_ux
             +p_delta_y*(1-l_first_t)*l_first_uy)*l_first_uy;
    if l_max_contacts>=2 and (l_rem_x<>0 or l_rem_y<>0) then
      l_second:=doom_sweep_contact(p_session,l_x,l_y,l_start_z,l_rem_x,l_rem_y,
                                   l_radius,l_height,l_step,l_first_id);
    end if;
  end if;
  if l_second is not null then
    l_second_id:=json_value(l_second,'$.linedef_id' returning number);
    l_second_t:=json_value(l_second,'$.contact_t' returning number);
    l_x:=l_x+l_rem_x*l_second_t;l_y:=l_y+l_rem_y*l_second_t;
  elsif l_first is not null then
    l_x:=l_x+l_rem_x;l_y:=l_y+l_rem_y;
  else
    l_x:=l_x+l_rem_x;l_y:=l_y+l_rem_y;
  end if;

  select sector_id into l_sector from table(doom_bsp_locate(l_x,l_y)) where rownum=1;
  if l_noclip=0 and doom_portal_transition_ok(p_session,l_start_x,l_start_y,
       l_start_z,l_x,l_y,l_radius,l_height,l_step,l_start_sector,l_sector)=0 then
    l_x:=l_start_x;l_y:=l_start_y;l_sector:=l_start_sector;
    l_first_id:=null;l_first_t:=null;l_second_id:=null;l_second_t:=null;
  end if;
  select coalesce(ss.floor_height,ms.floor_height) into l_floor
    from doom_map_sector ms
    left join sector_state ss
      on ss.session_token=p_session and ss.sector_id=ms.sector_id
   where ms.sector_id=l_sector;
  return json_object(
    'session_token' value p_session,'player_id' value l_player_id,
    'start_x' value l_start_x,'start_y' value l_start_y,'start_z' value l_start_z,
    'dest_x' value l_x,'dest_y' value l_y,'dest_z' value l_floor,
    'destination_sector_id' value l_sector,'view_height' value l_view,
    'eye_z' value l_floor+l_view,
    'contact_count' value case when l_first_id is null then 0 when l_second_id is null then 1 else 2 end,
    'first_blocker_id' value l_first_id,'first_fraction' value l_first_t,
    'second_blocker_id' value l_second_id,'second_fraction' value l_second_t
  );
end;
/

-- The public SQL_MACRO is intentionally a shallow SELECT. Oracle 23 expands
-- formal parameters correctly here; the payload remains database-owned.
create or replace function doom_player_move(
  p_session varchar2,p_delta_x number,p_delta_y number
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select movement.*
    from json_table(
      doom_player_move_payload(p_session,p_delta_x,p_delta_y), '$'
      columns(
        session_token varchar2(32) path '$.session_token',
        player_id number path '$.player_id',
        start_x number path '$.start_x',start_y number path '$.start_y',start_z number path '$.start_z',
        dest_x number path '$.dest_x',dest_y number path '$.dest_y',dest_z number path '$.dest_z',
        destination_sector_id number path '$.destination_sector_id',
        view_height number path '$.view_height',eye_z number path '$.eye_z',
        contact_count number path '$.contact_count',
        first_blocker_id number path '$.first_blocker_id',first_fraction number path '$.first_fraction',
        second_blocker_id number path '$.second_blocker_id',second_fraction number path '$.second_fraction'
      )
    ) movement
  ~';
end;
/

commit;
