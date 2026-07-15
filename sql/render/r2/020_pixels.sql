whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- T5.2's renderer is a single relational pipeline.  DOOM_R2_PORTAL_HITS and
-- DOOM_R2_SECTOR_INTERVALS are the reviewed public names for the canonical
-- backing relations consumed below; no per-pixel procedural loop is used.
-- Animation groups are project-owned render definitions.  A missing optional
-- frame is rejected naturally by the asset join rather than silently borrowing
-- a frame from another group.
create or replace view doom_r2_animation_frames as
select 'flat' asset_kind, 'NUKAGE' group_name, 'NUKAGE1' frame_name,
  0 frame_ordinal, 8 tic_period, 3 frame_count from dual union all
select 'flat', 'NUKAGE', 'NUKAGE2', 1, 8, 3 from dual union all
select 'flat', 'NUKAGE', 'NUKAGE3', 2, 8, 3 from dual union all
select 'flat', 'FWATER', 'FWATER1', 0, 8, 4 from dual union all
select 'flat', 'FWATER', 'FWATER2', 1, 8, 4 from dual union all
select 'flat', 'FWATER', 'FWATER3', 2, 8, 4 from dual union all
select 'flat', 'FWATER', 'FWATER4', 3, 8, 4 from dual union all
select 'wall_texture', 'SFALL', 'SFALL1', 0, 4, 4 from dual union all
select 'wall_texture', 'SFALL', 'SFALL2', 1, 4, 4 from dual union all
select 'wall_texture', 'SFALL', 'SFALL3', 2, 4, 4 from dual union all
select 'wall_texture', 'SFALL', 'SFALL4', 3, 4, 4 from dual;

create or replace view doom_r2_pixel_rows as
with
pose as (
  select session_row.session_token, session_row.current_tic,
    player.player_id, player.x player_x, player.y player_y,
    player.z + player.view_height + player.view_bob eye_z,
    cast(320 as binary_double) / 2 /
      tan(cast(90 as binary_double) * cast(acos(-1) as binary_double) / 360)
      projection_k
  from game_sessions session_row
  join players player
    on player.session_token = session_row.session_token
   and player.player_id = session_row.current_player_id
),
rays as (
  select pose.*, ray.column_no, ray.ray_x, ray.ray_y
  from pose
  join doom_r1_ray_rows ray
    on ray.session_token = pose.session_token
   and ray.player_id = pose.player_id
),
-- Live floor, ceiling, and light values override immutable map values.
sector_values as (
  select sessions.session_token, map_sector.sector_id,
    coalesce(live_sector.floor_height, map_sector.floor_height) floor_height,
    coalesce(live_sector.ceiling_height, map_sector.ceiling_height) ceiling_height,
    coalesce(live_sector.light_level, map_sector.light_level) light_level,
    map_sector.floor_flat, map_sector.ceiling_flat
  from game_sessions sessions
  cross join doom_map_sector map_sector
  left join sector_state live_sector
    on live_sector.session_token = sessions.session_token
   and live_sector.sector_id = map_sector.sector_id
),
active_hits as (
  select hit.*,
    row_number() over (
      partition by hit.session_token, hit.column_no
      order by hit.hit_t, hit.linedef_id, hit.seg_id, hit.facing_side
    ) - 1 active_ordinal
  from doom_r2_portal_hit_rows hit
  where hit.is_active = 1
),
hit_detail as (
  select hit.*, rays.eye_z, rays.projection_k,
    facing.floor_height facing_floor_height,
    facing.ceiling_height facing_ceiling_height,
    facing.ceiling_flat facing_ceiling_flat,
    opposite.floor_height opposite_floor_height,
    opposite.ceiling_height opposite_ceiling_height,
    opposite.ceiling_flat opposite_ceiling_flat,
    side_row.x_offset, side_row.y_offset,
    side_row.upper_texture, side_row.lower_texture, side_row.middle_texture,
    line.flags linedef_flags, seg.offset seg_offset,
    start_vertex.x seg_start_x, start_vertex.y seg_start_y,
    end_vertex.x seg_end_x, end_vertex.y seg_end_y,
    100 - (hit.opening_top-rays.eye_z)*rays.projection_k/nullif(hit.hit_t,0)
      opening_top_y,
    100 - (hit.opening_bottom-rays.eye_z)*rays.projection_k/nullif(hit.hit_t,0)
      opening_bottom_y
  from active_hits hit
  join rays
    on rays.session_token=hit.session_token and rays.column_no=hit.column_no
  join sector_values facing
    on facing.session_token=hit.session_token
   and facing.sector_id=hit.from_sector_id
  left join sector_values opposite
    on opposite.session_token=hit.session_token
   and opposite.sector_id=hit.to_sector_id
  join doom_map_sidedef side_row
    on side_row.sidedef_id=hit.facing_sidedef_id
  join doom_map_linedef line on line.linedef_id=hit.linedef_id
  join doom_map_seg seg on seg.seg_id=hit.seg_id
  join doom_map_vertex start_vertex on start_vertex.vertex_id=seg.start_vertex_id
  join doom_map_vertex end_vertex on end_vertex.vertex_id=seg.end_vertex_id
),
hit_clips as (
  select hit_detail.*,
    greatest(0,coalesce(max(opening_top_y) over (
      partition by session_token,column_no order by active_ordinal
      rows between unbounded preceding and 1 preceding),0)) clip_top_before,
    least(200,coalesce(min(opening_bottom_y) over (
      partition by session_token,column_no order by active_ordinal
      rows between unbounded preceding and 1 preceding),200)) clip_bottom_before,
    greatest(0,coalesce(max(opening_top_y) over (
      partition by session_token,column_no order by active_ordinal
      rows between unbounded preceding and current row),0)) clip_top_after,
    least(200,coalesce(min(opening_bottom_y) over (
      partition by session_token,column_no order by active_ordinal
      rows between unbounded preceding and current row),200)) clip_bottom_after
  from hit_detail
),
interval_detail as (
  select interval_row.*, rays.player_x, rays.player_y, rays.eye_z,
    rays.ray_x, rays.ray_y, rays.projection_k,
    sector.floor_height, sector.ceiling_height, sector.light_level,
    sector.floor_flat, sector.ceiling_flat,
    coalesce(prior_hit.clip_top_after,0) clip_top,
    coalesce(prior_hit.clip_bottom_after,200) clip_bottom
  from doom_r2_sector_interval_rows interval_row
  join rays
    on rays.session_token=interval_row.session_token
   and rays.column_no=interval_row.column_no
  join sector_values sector
    on sector.session_token=interval_row.session_token
   and sector.sector_id=interval_row.sector_id
  left join hit_clips prior_hit
    on prior_hit.session_token=interval_row.session_token
   and prior_hit.column_no=interval_row.column_no
   and prior_hit.active_ordinal=interval_row.interval_ordinal-1
),
screen_pixels as (
  select rays.session_token, rays.column_no, screen_rows.row_no,
    screen_rows.row_no + 0.5 row_center
  from rays
  cross join (select level-1 row_no from dual connect by level<=200) screen_rows
),
wall_candidates as (
  select pixel.session_token,pixel.column_no,pixel.row_no,
    case
      when hit.is_termination=1 then 10
      when pixel.row_center >= 100-(hit.lower_top-hit.eye_z)*hit.projection_k/hit.hit_t
       and pixel.row_center < 100-(hit.lower_bottom-hit.eye_z)*hit.projection_k/hit.hit_t then 11
      else 12
    end layer_ordinal,
    hit.active_ordinal sector_interval_ordinal,
    hit.hit_t sample_t, hit.from_sector_id sector_id,
    case
      when hit.is_termination=1 then
        case when hit.middle_texture!='-' then hit.middle_texture
             when hit.upper_texture!='-' then hit.upper_texture
             else hit.lower_texture end
      when pixel.row_center >= 100-(hit.lower_top-hit.eye_z)*hit.projection_k/hit.hit_t
       and pixel.row_center < 100-(hit.lower_bottom-hit.eye_z)*hit.projection_k/hit.hit_t
        then hit.lower_texture
      else hit.upper_texture
    end base_asset_name,
    'wall_texture' asset_kind,
    hit.seg_offset+hit.x_offset+hit.hit_u*sqrt(
      power(hit.seg_end_x-hit.seg_start_x,2)+power(hit.seg_end_y-hit.seg_start_y,2)) sample_x,
    case
      when hit.is_termination=1 then
        case when bitand(hit.linedef_flags,16)!=0
             then hit.facing_floor_height+128 else hit.facing_ceiling_height end
      when pixel.row_center >= 100-(hit.lower_top-hit.eye_z)*hit.projection_k/hit.hit_t
       and pixel.row_center < 100-(hit.lower_bottom-hit.eye_z)*hit.projection_k/hit.hit_t then
        case when bitand(hit.linedef_flags,16)!=0
             then hit.facing_ceiling_height else hit.opposite_floor_height end
      else case when bitand(hit.linedef_flags,8)!=0
                then hit.opposite_ceiling_height+128 else hit.facing_ceiling_height end
    end - (hit.eye_z+(100-pixel.row_center)*hit.hit_t/hit.projection_k)
      + hit.y_offset sample_y,
    facing.light_level light_level,
    row_number() over (
      partition by pixel.session_token,pixel.column_no,pixel.row_no
      order by hit.hit_t,hit.linedef_id,hit.seg_id,hit.facing_side
    ) candidate_ordinal
  from screen_pixels pixel
  join hit_clips hit
    on hit.session_token=pixel.session_token and hit.column_no=pixel.column_no
   and pixel.row_center>=hit.clip_top_before
   and pixel.row_center<hit.clip_bottom_before
  join sector_values facing
    on facing.session_token=hit.session_token and facing.sector_id=hit.from_sector_id
  where
    (hit.is_termination=1 and
      pixel.row_center>=100-(hit.facing_ceiling_height-hit.eye_z)*hit.projection_k/hit.hit_t and
      pixel.row_center<100-(hit.facing_floor_height-hit.eye_z)*hit.projection_k/hit.hit_t)
    or
    (hit.is_transition=1 and hit.lower_top>hit.lower_bottom and hit.lower_texture!='-' and
      pixel.row_center>=100-(hit.lower_top-hit.eye_z)*hit.projection_k/hit.hit_t and
      pixel.row_center<100-(hit.lower_bottom-hit.eye_z)*hit.projection_k/hit.hit_t)
    or
    (hit.is_transition=1 and hit.upper_top>hit.upper_bottom and hit.upper_texture!='-' and
      not (hit.facing_ceiling_flat='F_SKY1' and hit.opposite_ceiling_flat='F_SKY1') and
      pixel.row_center>=100-(hit.upper_top-hit.eye_z)*hit.projection_k/hit.hit_t and
      pixel.row_center<100-(hit.upper_bottom-hit.eye_z)*hit.projection_k/hit.hit_t)
),
plane_candidates as (
  select pixel.session_token,pixel.column_no,pixel.row_no,
    case when interval.ceiling_flat='F_SKY1' and pixel.row_center<100 then 3
         when pixel.row_center<100 then 1 else 0 end layer_ordinal,
    interval.interval_ordinal sector_interval_ordinal,
    case when pixel.row_center<100 then
      (interval.ceiling_height-interval.eye_z)*interval.projection_k/(100-pixel.row_center)
    else (interval.eye_z-interval.floor_height)*interval.projection_k/(pixel.row_center-100)
    end sample_t,
    interval.sector_id,
    case when interval.ceiling_flat='F_SKY1' and pixel.row_center<100 then 'SKY1'
         when pixel.row_center<100 then interval.ceiling_flat else interval.floor_flat end base_asset_name,
    case when interval.ceiling_flat='F_SKY1' and pixel.row_center<100
         then 'wall_texture' else 'flat' end asset_kind,
    case when interval.ceiling_flat='F_SKY1' and pixel.row_center<100
         then pixel.column_no/2
         else interval.player_x+interval.ray_x*(case when pixel.row_center<100 then
           (interval.ceiling_height-interval.eye_z)*interval.projection_k/(100-pixel.row_center)
           else (interval.eye_z-interval.floor_height)*interval.projection_k/(pixel.row_center-100) end)
    end sample_x,
    case when interval.ceiling_flat='F_SKY1' and pixel.row_center<100
         then pixel.row_center
         else interval.player_y+interval.ray_y*(case when pixel.row_center<100 then
           (interval.ceiling_height-interval.eye_z)*interval.projection_k/(100-pixel.row_center)
           else (interval.eye_z-interval.floor_height)*interval.projection_k/(pixel.row_center-100) end)
    end sample_y,
    case when interval.ceiling_flat='F_SKY1' and pixel.row_center<100
         then 255 else interval.light_level end light_level,
    row_number() over (
      partition by pixel.session_token,pixel.column_no,pixel.row_no
      order by interval.interval_ordinal
    ) candidate_ordinal
  from screen_pixels pixel
  join interval_detail interval
    on interval.session_token=pixel.session_token
   and interval.column_no=pixel.column_no
   and pixel.row_center>=interval.clip_top
   and pixel.row_center<interval.clip_bottom
  where (pixel.row_center<100 and interval.ceiling_height>interval.eye_z and
      (interval.ceiling_height-interval.eye_z)*interval.projection_k/(100-pixel.row_center)
        >=interval.t_start and
      (interval.ceiling_height-interval.eye_z)*interval.projection_k/(100-pixel.row_center)
        <interval.t_end)
     or (pixel.row_center>=100 and interval.floor_height<interval.eye_z and
      (interval.eye_z-interval.floor_height)*interval.projection_k/(pixel.row_center-100)
        >=interval.t_start and
      (interval.eye_z-interval.floor_height)*interval.projection_k/(pixel.row_center-100)
        <interval.t_end)
),
-- The exact horizon can have no finite reverse-projected plane.  It still has
-- interval ownership and is filled from the furthest visible interval.
horizon_candidates as (
  select pixel.session_token,pixel.column_no,pixel.row_no,4 layer_ordinal,
    interval.interval_ordinal sector_interval_ordinal,interval.t_end sample_t,
    interval.sector_id,
    case when pixel.row_center<100 then interval.ceiling_flat else interval.floor_flat end base_asset_name,
    'flat' asset_kind,
    interval.player_x+interval.ray_x*interval.t_end sample_x,
    interval.player_y+interval.ray_y*interval.t_end sample_y,
    interval.light_level,
    row_number() over (
      partition by pixel.session_token,pixel.column_no,pixel.row_no
      order by interval.interval_ordinal desc
    ) candidate_ordinal
  from screen_pixels pixel
  join interval_detail interval
    on interval.session_token=pixel.session_token
   and interval.column_no=pixel.column_no
   and pixel.row_center>=interval.clip_top
   and pixel.row_center<interval.clip_bottom
),
candidate_union as (
  select candidate.*,0 source_priority from wall_candidates candidate
  where candidate_ordinal=1
  union all
  select candidate.*,1 source_priority from plane_candidates candidate
  where candidate_ordinal=1
  union all
  select candidate.*,2 source_priority from horizon_candidates candidate
  where candidate_ordinal=1
),
ranked_candidates as (
  select candidate_union.*,
    row_number() over (
      partition by session_token,column_no,row_no
      order by source_priority,candidate_ordinal
    ) final_ordinal
  from candidate_union
),
selected_candidates as (
  select session_token,column_no,row_no,layer_ordinal,
    sector_interval_ordinal,sample_t,sector_id,base_asset_name,asset_kind,
    sample_x,sample_y,light_level,candidate_ordinal
  from ranked_candidates
  where final_ordinal=1
),
animated_candidates as (
  select selected_candidates.*,
    coalesce(animation_frame.frame_name,selected_candidates.base_asset_name) asset_name,
    greatest(0,least(31,floor((255-selected_candidates.light_level)/8))) light_band
  from selected_candidates
  join game_sessions session_row
    on session_row.session_token=selected_candidates.session_token
  left join doom_r2_animation_frames animation_base
    on animation_base.asset_kind=selected_candidates.asset_kind
   and animation_base.frame_name=selected_candidates.base_asset_name
  left join doom_r2_animation_frames animation_frame
    on animation_frame.asset_kind=animation_base.asset_kind
   and animation_frame.group_name=animation_base.group_name
   and animation_frame.frame_ordinal=animation_base.frame_ordinal
       + floor(session_row.current_tic/animation_base.tic_period)
       - animation_base.frame_count*floor(
           (animation_base.frame_ordinal
             + floor(session_row.current_tic/animation_base.tic_period))
           /animation_base.frame_count)
),
with_assets as (
  select animated_candidates.*,asset.asset_id,asset.width asset_width,
    asset.height asset_height
  from animated_candidates
  join doom_asset asset
    on asset.asset_kind=animated_candidates.asset_kind
   and asset.asset_name=animated_candidates.asset_name
),
raw_texels as (
  select /*+ leading(with_assets) use_nl(texel) index(texel at_pk) */
    with_assets.*,texel.c raw_palette_index
  from with_assets
  join at texel on texel.a=with_assets.asset_id
   and texel.x=cast(floor(sample_x)-asset_width*floor(floor(sample_x)/asset_width) as number)
   and texel.y=cast(floor(sample_y)-asset_height*floor(floor(sample_y)/asset_height) as number)
)
select raw_texels.session_token,raw_texels.column_no,raw_texels.row_no,
  colormap.mapped_index palette_index,raw_texels.layer_ordinal,
  raw_texels.sector_interval_ordinal
from raw_texels
join doom_colormap_texel colormap
  on colormap.map_index=raw_texels.light_band
 and colormap.palette_index=raw_texels.raw_palette_index
where raw_texels.raw_palette_index>=0;

create or replace function doom_r2_pixels(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select pixel.session_token,pixel.column_no,pixel.row_no,
      pixel.palette_index,pixel.layer_ordinal,pixel.sector_interval_ordinal
    from doom_r2_pixel_rows pixel
    where pixel.session_token=p_session
    order by pixel.column_no,pixel.row_no
  ~';
end;
/

commit;
