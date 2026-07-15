whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- One pose-dependent row per seg, materialized once by DOOM_API.  Projection
-- bounds are conservative; the exact determinant/t/u predicates remain the
-- only authority for accepting a ray hit.
create or replace view doom_r1_staged_segment_bound_rows as
with
pose as (
  select player.session_token,player.player_id,player.x player_x,
    player.y player_y,player.z player_z,player.angle angle_degrees,
    ray.angle_radians,ray.direction_x,ray.direction_y,ray.plane_x,ray.plane_y,
    ray.plane_x*ray.plane_x+ray.plane_y*ray.plane_y plane_squared
  from game_sessions session_row
  join players player
    on player.session_token=session_row.session_token
   and player.player_id=session_row.current_player_id
  join doom_render_ray ray
    on ray.profile_id='CANONICAL_320X200'
   and ray.angle_degrees=player.angle and ray.column_no=0
),
segments as (
  select pose.*,line.linedef_id,line.right_sidedef_id,line.left_sidedef_id,
    line_start.x line_start_x,line_start.y line_start_y,
    line_end.x line_end_x,line_end.y line_end_y,
    seg.seg_id,seg.direction seg_direction,
    seg_start.x seg_start_x,seg_start.y seg_start_y,
    seg_end.x seg_end_x,seg_end.y seg_end_y,
    (seg_start.x-pose.player_x)*pose.direction_x+
      (seg_start.y-pose.player_y)*pose.direction_y start_depth,
    (seg_end.x-pose.player_x)*pose.direction_x+
      (seg_end.y-pose.player_y)*pose.direction_y end_depth,
    (seg_start.x-pose.player_x)*pose.plane_x+
      (seg_start.y-pose.player_y)*pose.plane_y start_plane,
    (seg_end.x-pose.player_x)*pose.plane_x+
      (seg_end.y-pose.player_y)*pose.plane_y end_plane
  from pose
  cross join doom_map_seg seg
  join doom_map_linedef line on line.linedef_id=seg.linedef_id
  join doom_map_vertex seg_start on seg_start.vertex_id=seg.start_vertex_id
  join doom_map_vertex seg_end on seg_end.vertex_id=seg.end_vertex_id
  join doom_map_vertex line_start on line_start.vertex_id=line.start_vertex_id
  join doom_map_vertex line_end on line_end.vertex_id=line.end_vertex_id
),
projected as (
  select segments.*,
    case when start_depth>1e-9 then start_plane/(start_depth*plane_squared)
      else (start_plane+(1e-9-start_depth)*(end_plane-start_plane)/
        nullif(end_depth-start_depth,0))/(1e-9*plane_squared) end start_cam_x,
    case when end_depth>1e-9 then end_plane/(end_depth*plane_squared)
      else (end_plane+(1e-9-end_depth)*(start_plane-end_plane)/
        nullif(start_depth-end_depth,0))/(1e-9*plane_squared) end end_cam_x
  from segments
  where greatest(start_depth,end_depth)>1e-9
)
select session_token,player_id,player_x,player_y,player_z,angle_degrees,
  angle_radians,direction_x,direction_y,plane_x,plane_y,
  linedef_id,seg_id,seg_direction,right_sidedef_id,left_sidedef_id,
  line_start_x,line_start_y,line_end_x,line_end_y,
  seg_start_x,seg_start_y,seg_end_x,seg_end_y,
  least(start_cam_x,end_cam_x)-1e-7 min_cam_x,
  greatest(start_cam_x,end_cam_x)+1e-7 max_cam_x
from projected;

create or replace view doom_r1_staged_hit_rows as
with intersection_terms as (
  select /*+ leading(segment ray) use_nl(ray) index(ray doom_render_ray_cam_ix) */
    segment.session_token,segment.player_id,ray.column_no,
    segment.player_x,segment.player_y,segment.player_z,
    segment.angle_degrees,segment.angle_radians,
    segment.direction_x,segment.direction_y,segment.plane_x,segment.plane_y,
    ray.cam_x,ray.ray_x,ray.ray_y,
    segment.linedef_id,segment.seg_id,segment.seg_direction,
    ray.ray_x*(segment.seg_end_y-segment.seg_start_y)-
      ray.ray_y*(segment.seg_end_x-segment.seg_start_x) determinant,
    (segment.seg_start_x-segment.player_x)*(segment.seg_end_y-segment.seg_start_y)-
      (segment.seg_start_y-segment.player_y)*(segment.seg_end_x-segment.seg_start_x)
      t_numerator,
    (segment.seg_start_x-segment.player_x)*ray.ray_y-
      (segment.seg_start_y-segment.player_y)*ray.ray_x u_numerator,
    case when (segment.player_x-segment.line_start_x)*
      (segment.line_end_y-segment.line_start_y)-
      (segment.player_y-segment.line_start_y)*
      (segment.line_end_x-segment.line_start_x)>0 then 0 else 1 end facing_side,
    segment.right_sidedef_id,segment.left_sidedef_id
  from frame_render_seg_bound segment
  join doom_render_ray ray
    on ray.profile_id='CANONICAL_320X200'
   and ray.angle_degrees=segment.angle_degrees
   and ray.cam_x between segment.min_cam_x and segment.max_cam_x
), analytic as (
  select intersection_terms.*,
    t_numerator/nullif(determinant,0) hit_t,
    u_numerator/nullif(determinant,0) hit_u
  from intersection_terms
  where abs(determinant)>=1e-12
), accepted as (
  select analytic.*,
    case facing_side when 0 then right_sidedef_id else left_sidedef_id end sidedef_id,
    case facing_side when 0 then left_sidedef_id else right_sidedef_id end opposite_sidedef_id
  from analytic
  where hit_t>1e-9 and hit_u>=0 and hit_u<=1
), classified as (
  select accepted.*,
    case when accepted.sidedef_id is null or accepted.opposite_sidedef_id is null
      then 1
      when least(facing_sector.ceiling_height,opposite_sector.ceiling_height)-
        greatest(facing_sector.floor_height,opposite_sector.floor_height)<=0
      then 1 else 0 end is_solid
  from accepted
  left join doom_map_sidedef facing_sidedef
    on facing_sidedef.sidedef_id=accepted.sidedef_id
  left join doom_map_sector facing_sector
    on facing_sector.sector_id=facing_sidedef.sector_id
  left join doom_map_sidedef opposite_sidedef
    on opposite_sidedef.sidedef_id=accepted.opposite_sidedef_id
  left join doom_map_sector opposite_sector
    on opposite_sector.sector_id=opposite_sidedef.sector_id
)
select classified.*,
  row_number() over(partition by session_token,column_no
    order by hit_t,linedef_id,seg_id,facing_side) hit_ordinal
from classified;

commit;
