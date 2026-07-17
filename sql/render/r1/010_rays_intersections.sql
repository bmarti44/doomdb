whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- Shared relational camera source. Public SQL macros only apply the bound
-- session bind to these canonical rows, avoiding nested SQL-macro parameters.
create or replace view doom_r1_ray_rows as
select
  player.session_token,
  player.player_id,
  columns.column_no,
  player.x as player_x,
  player.y as player_y,
  player.z as player_z,
  player.angle as angle_degrees,
  cast(player.angle * acos(-1) / 180 as binary_double) as angle_radians,
  cos(cast(player.angle * acos(-1) / 180 as binary_double)) as direction_x,
  sin(cast(player.angle * acos(-1) / 180 as binary_double)) as direction_y,
  -sin(cast(player.angle * acos(-1) / 180 as binary_double))
    * tan(cast((90 * acos(-1) / 180) / 2 as binary_double)) as plane_x,
  cos(cast(player.angle * acos(-1) / 180 as binary_double))
    * tan(cast((90 * acos(-1) / 180) / 2 as binary_double)) as plane_y,
  2 * (columns.column_no + 0.5) / frame.number_value - 1 as cam_x,
  cos(cast(player.angle * acos(-1) / 180 as binary_double))
    + (-sin(cast(player.angle * acos(-1) / 180 as binary_double))
      * tan(cast((90 * acos(-1) / 180) / 2 as binary_double)))
      * (2 * (columns.column_no + 0.5) / frame.number_value - 1) as ray_x,
  sin(cast(player.angle * acos(-1) / 180 as binary_double))
    + (cos(cast(player.angle * acos(-1) / 180 as binary_double))
      * tan(cast((90 * acos(-1) / 180) / 2 as binary_double)))
      * (2 * (columns.column_no + 0.5) / frame.number_value - 1) as ray_y,
  power(
    cos(cast(player.angle * acos(-1) / 180 as binary_double))
      + (-sin(cast(player.angle * acos(-1) / 180 as binary_double))
        * tan(cast((90 * acos(-1) / 180) / 2 as binary_double)))
        * (2 * (columns.column_no + 0.5) / frame.number_value - 1), 2)
  + power(
    sin(cast(player.angle * acos(-1) / 180 as binary_double))
      + (cos(cast(player.angle * acos(-1) / 180 as binary_double))
        * tan(cast((90 * acos(-1) / 180) / 2 as binary_double)))
        * (2 * (columns.column_no + 0.5) / frame.number_value - 1), 2)
    as ray_length_squared,
  far_config.number_value as far_distance
from game_sessions session_row
join players player
  on player.session_token = session_row.session_token
 and player.player_id = session_row.current_player_id
cross join doom_config frame
cross join doom_config far_config
cross join (
  select level - 1 as column_no
  from dual
  connect by level <= 320
) columns
where frame.config_key = 'FRAME_WIDTH'
  and frame.number_value = 320
  and far_config.config_key = 'FAR_DISTANCE';

create or replace function doom_r1_rays(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select ray.*
    from doom_r1_ray_rows ray
    where ray.session_token = p_session
  ~';
end;
/

-- All hit behavior is implemented once in this view. SDO_FILTER is only the
-- indexed MBR candidate stage; exact determinant, t, and inclusive u tests
-- remain mandatory for every accepted seg.
create or replace view doom_r1_hit_rows as
with
pose as (
  select distinct
    session_token, player_id, player_x, player_y, player_z,
    angle_degrees, angle_radians, direction_x, direction_y,
    plane_x, plane_y, far_distance
  from doom_r1_ray_rows
),
frustum as (
  select
    pose.*,
    mdsys.sdo_geometry(
      2003, null, null,
      mdsys.sdo_elem_info_array(1, 1003, 1),
      mdsys.sdo_ordinate_array(
        player_x, player_y,
        player_x + far_distance * (direction_x - plane_x),
        player_y + far_distance * (direction_y - plane_y),
        player_x + far_distance * (direction_x + plane_x),
        player_y + far_distance * (direction_y + plane_y),
        player_x, player_y
      )
    ) as geom
  from pose
),
candidate_linedefs as (
  select frustum.session_token, spatial_line.*
  from frustum
  join doom_linedef spatial_line
    on sdo_filter(spatial_line.geom, frustum.geom) = 'TRUE'
),
segment_inputs as (
  select
    candidate.session_token,
    candidate.linedef_id,
    candidate.right_sidedef_id,
    candidate.left_sidedef_id,
    line_start.x as line_start_x,
    line_start.y as line_start_y,
    line_end.x as line_end_x,
    line_end.y as line_end_y,
    seg.seg_id,
    seg.direction as seg_direction,
    seg_start.x as seg_start_x,
    seg_start.y as seg_start_y,
    seg_end.x as seg_end_x,
    seg_end.y as seg_end_y
  from candidate_linedefs candidate
  join doom_map_seg seg
    on seg.linedef_id = candidate.linedef_id
  join doom_map_vertex seg_start
    on seg_start.vertex_id = seg.start_vertex_id
  join doom_map_vertex seg_end
    on seg_end.vertex_id = seg.end_vertex_id
  join doom_map_linedef map_line
    on map_line.linedef_id = candidate.linedef_id
  join doom_map_vertex line_start
    on line_start.vertex_id = map_line.start_vertex_id
  join doom_map_vertex line_end
    on line_end.vertex_id = map_line.end_vertex_id
),
intersection_terms as (
  select
    ray.session_token, ray.player_id, ray.column_no,
    ray.player_x, ray.player_y, ray.player_z,
    ray.angle_degrees, ray.angle_radians,
    ray.direction_x, ray.direction_y, ray.plane_x, ray.plane_y,
    ray.cam_x, ray.ray_x, ray.ray_y,
    segment.linedef_id, segment.seg_id, segment.seg_direction,
    ray.ray_x * (segment.seg_end_y - segment.seg_start_y)
      - ray.ray_y * (segment.seg_end_x - segment.seg_start_x)
      as determinant,
    (segment.seg_start_x - ray.player_x)
      * (segment.seg_end_y - segment.seg_start_y)
      - (segment.seg_start_y - ray.player_y)
      * (segment.seg_end_x - segment.seg_start_x) as t_numerator,
    (segment.seg_start_x - ray.player_x) * ray.ray_y
      - (segment.seg_start_y - ray.player_y) * ray.ray_x as u_numerator,
    case
      when (ray.player_x - segment.line_start_x)
             * (segment.line_end_y - segment.line_start_y)
           - (ray.player_y - segment.line_start_y)
             * (segment.line_end_x - segment.line_start_x) > 0
      then 0 else 1
    end as facing_side,
    segment.right_sidedef_id,
    segment.left_sidedef_id
  from doom_r1_ray_rows ray
  join segment_inputs segment
    on segment.session_token = ray.session_token
),
analytic as (
  select intersection_terms.*,
    t_numerator / nullif(determinant, 0) as hit_t,
    u_numerator / nullif(determinant, 0) as hit_u
  from intersection_terms
  where abs(determinant) >= 1e-12
),
accepted as (
  select analytic.*,
    case facing_side when 0 then right_sidedef_id else left_sidedef_id end
      as sidedef_id,
    case facing_side when 0 then left_sidedef_id else right_sidedef_id end
      as opposite_sidedef_id
  from analytic
  where hit_t > 1e-9
    and hit_u >= 0
    and hit_u <= 1
),
classified as (
  select accepted.*,
    case
      when accepted.sidedef_id is null
        or accepted.opposite_sidedef_id is null then 1
      when least(coalesce(facing_state.ceiling_height,facing_sector.ceiling_height),
                 coalesce(opposite_state.ceiling_height,opposite_sector.ceiling_height))
           - greatest(coalesce(facing_state.floor_height,facing_sector.floor_height),
                      coalesce(opposite_state.floor_height,opposite_sector.floor_height)) <= 0 then 1
      else 0
    end as is_solid
  from accepted
  left join doom_map_sidedef facing_sidedef
    on facing_sidedef.sidedef_id = accepted.sidedef_id
  left join doom_map_sector facing_sector
    on facing_sector.sector_id = facing_sidedef.sector_id
  left join sector_state facing_state
    on facing_state.session_token=accepted.session_token
   and facing_state.sector_id=facing_sidedef.sector_id
  left join doom_map_sidedef opposite_sidedef
    on opposite_sidedef.sidedef_id = accepted.opposite_sidedef_id
  left join doom_map_sector opposite_sector
    on opposite_sector.sector_id = opposite_sidedef.sector_id
  left join sector_state opposite_state
    on opposite_state.session_token=accepted.session_token
   and opposite_state.sector_id=opposite_sidedef.sector_id
)
select classified.*,
  row_number() over (
    partition by classified.session_token, classified.column_no
    order by classified.hit_t, classified.linedef_id,
             classified.seg_id, classified.facing_side
  ) as hit_ordinal
from classified;

create or replace function doom_r1_hits(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select hit.*
    from doom_r1_hit_rows hit
    where hit.session_token = p_session
  ~';
end;
/

create or replace function doom_r1_nearest(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select nearest.*
    from (
      select solid_hit.*,
        row_number() over (
          partition by solid_hit.session_token, solid_hit.column_no
          order by solid_hit.hit_t, solid_hit.linedef_id,
                   solid_hit.seg_id, solid_hit.facing_side
        ) as solid_ordinal
      from doom_r1_hit_rows solid_hit
      where solid_hit.session_token = p_session
        and solid_hit.is_solid = 1
    ) nearest
    where nearest.solid_ordinal = 1
  ~';
end;
/

commit;
