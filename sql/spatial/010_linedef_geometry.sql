-- Materialize the directed E1M1 linedefs only after the constrained seed load.
merge into doom_linedef target
using (
  select l.linedef_id,
         a.x start_x,
         a.y start_y,
         b.x end_x,
         b.y end_y,
         b.x - a.x dx,
         b.y - a.y dy,
         sqrt(power(b.x - a.x, 2) + power(b.y - a.y, 2)) unrounded_length
    from doom_linedef l
    join doom_vertex a on a.vertex_id = l.start_vertex_id
    join doom_vertex b on b.vertex_id = l.end_vertex_id
) source
on (target.linedef_id = source.linedef_id)
when matched then update set
  target.geom = mdsys.sdo_geometry(
    2002,
    null,
    null,
    mdsys.sdo_elem_info_array(1, 2, 1),
    mdsys.sdo_ordinate_array(
      source.start_x, source.start_y, source.end_x, source.end_y)),
  target.length = round(source.unrounded_length, 12),
  target.direction_x = round(source.dx / source.unrounded_length, 12),
  target.direction_y = round(source.dy / source.unrounded_length, 12);

alter table doom_linedef modify (
  geom not null,
  length not null,
  direction_x not null,
  direction_y not null
);

alter table doom_linedef add constraint doom_linedef_metric_ck check (
  length > 0 and
  direction_x between -1 and 1 and
  direction_y between -1 and 1
) enable validate;

delete from user_sdo_geom_metadata
 where table_name = 'DOOM_LINEDEF'
   and column_name = 'GEOM';

insert into user_sdo_geom_metadata (table_name, column_name, diminfo, srid)
with vertex_bounds as (
  select min(x) min_x, max(x) max_x, min(y) min_y, max(y) max_y
    from doom_vertex
), configured_margin as (
  select max(case when config_key = 'FAR_DISTANCE' then number_value end) far_distance,
         max(case when config_key = 'PLAYER_RADIUS' then number_value end) player_radius
    from doom_config
   where config_key in ('FAR_DISTANCE', 'PLAYER_RADIUS')
)
select 'DOOM_LINEDEF',
       'GEOM',
       mdsys.sdo_dim_array(
         mdsys.sdo_dim_element(
           'X',
           bounds.min_x - margin.far_distance - margin.player_radius,
           bounds.max_x + margin.far_distance + margin.player_radius,
           0.005),
         mdsys.sdo_dim_element(
           'Y',
           bounds.min_y - margin.far_distance - margin.player_radius,
           bounds.max_y + margin.far_distance + margin.player_radius,
           0.005)),
       null
  from vertex_bounds bounds
 cross join configured_margin margin;

create index doom_linedef_sidx on doom_linedef (geom)
  indextype is mdsys.spatial_index_v2;

-- Exercise the deployed index through both candidate and exact stages. This is
-- also the production example for rejecting broad-filter false positives.
declare
  l_exact_matches number;
begin
  select count(*)
    into l_exact_matches
    from doom_linedef candidate
   where sdo_filter(
           candidate.geom,
           (select probe.geom from doom_linedef probe where probe.linedef_id = 0)) = 'TRUE'
     and sdo_relate(
           candidate.geom,
           (select probe.geom from doom_linedef probe where probe.linedef_id = 0),
           'mask=ANYINTERACT') = 'TRUE';

  if l_exact_matches < 1 then
    raise_application_error(-20932, 'DOOM_LINEDEF_SIDX exact-predicate health probe failed');
  end if;
end;
/

commit;
