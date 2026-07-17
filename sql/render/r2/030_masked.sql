whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- T5.3 composes transparent two-sided middle textures and current world MOBJS.
-- DOOM_R2_SECTOR_INTERVALS is the public macro for the canonical interval rows
-- consumed here; using its backing relation keeps this view mergeable.
-- The catalog is driven by DOOM_STATE_DEF and DOOM_ASSET.  Thing categories
-- include decoration, pickup, weapon_pickup, monster, barrel, PROJECTILE, and
-- EFFECT rows; projectile/effect states therefore remain world sprites and are
-- never borrowed from the first-person weapon overlay.
-- Sprite origin offsets are immutable WAD patch metadata.  Keeping the reviewed
-- values relational preserves asymmetric billboard placement without runtime
-- binary parsing or name-specific rendering branches.
create or replace view doom_r2_sprite_patch_metrics as
select 'AMMOA0' asset_name,8 left_offset,16 top_offset from dual union all
select 'BAL1A0' asset_name,8 left_offset,11 top_offset from dual union all
select 'ARM1A0' asset_name,18 left_offset,28 top_offset from dual union all
select 'ARM2A0' asset_name,18 left_offset,24 top_offset from dual union all
select 'BAR1A0' asset_name,11 left_offset,30 top_offset from dual union all
select 'BAR1B0' asset_name,11 left_offset,30 top_offset from dual union all
select 'BKEYA0' asset_name,7 left_offset,19 top_offset from dual union all
select 'BON1A0' asset_name,5 left_offset,15 top_offset from dual union all
select 'BON2A0' asset_name,6 left_offset,19 top_offset from dual union all
select 'BPAKA0' asset_name,13 left_offset,30 top_offset from dual union all
select 'BROKA0' asset_name,27 left_offset,20 top_offset from dual union all
select 'CELLA0' asset_name,8 left_offset,12 top_offset from dual union all
select 'CELPA0' asset_name,15 left_offset,20 top_offset from dual union all
select 'CHGGA0' asset_name,-107 left_offset,-117 top_offset from dual union all
select 'CHGGB0' asset_name,-107 left_offset,-121 top_offset from dual union all
select 'CLIPA0' asset_name,4 left_offset,12 top_offset from dual union all
select 'COLUA0' asset_name,9 left_offset,45 top_offset from dual union all
select 'CSAWA0' asset_name,22 left_offset,20 top_offset from dual union all
select 'ELECA0' asset_name,13 left_offset,128 top_offset from dual union all
select 'GOR1A0' asset_name,12 left_offset,67 top_offset from dual union all
select 'GOR2A0' asset_name,15 left_offset,81 top_offset from dual union all
select 'GOR4A0' asset_name,19 left_offset,67 top_offset from dual union all
select 'HEADL0' asset_name,38 left_offset,28 top_offset from dual union all
select 'LAUNA0' asset_name,30 left_offset,20 top_offset from dual union all
select 'MEDIA0' asset_name,14 left_offset,20 top_offset from dual union all
select 'MGUNA0' asset_name,25 left_offset,25 top_offset from dual union all
select 'MISGA0' asset_name,-111 left_offset,-104 top_offset from dual union all
select 'MISGB0' asset_name,-107 left_offset,-106 top_offset from dual union all
select 'PISGA0' asset_name,-125 left_offset,-97 top_offset from dual union all
select 'PISGB0' asset_name,-125 left_offset,-82 top_offset from dual union all
select 'PLASA0' asset_name,29 left_offset,16 top_offset from dual union all
select 'PLAYN0' asset_name,17 left_offset,15 top_offset from dual union all
select 'PLAYW0' asset_name,27 left_offset,14 top_offset from dual union all
select 'PLSGA0' asset_name,-115 left_offset,-104 top_offset from dual union all
select 'PLSGB0' asset_name,-50 left_offset,-100 top_offset from dual union all
select 'POL5A0' asset_name,27 left_offset,5 top_offset from dual union all
select 'POL6A0' asset_name,14 left_offset,62 top_offset from dual union all
select 'POSSA1' asset_name,22 left_offset,53 top_offset from dual union all
select 'POSSA2' asset_name,21 left_offset,53 top_offset from dual union all
select 'POSSA3' asset_name,21 left_offset,53 top_offset from dual union all
select 'POSSA4' asset_name,26 left_offset,53 top_offset from dual union all
select 'POSSA5' asset_name,18 left_offset,52 top_offset from dual union all
select 'POSSA6' asset_name,14 left_offset,52 top_offset from dual union all
select 'POSSA7' asset_name,18 left_offset,52 top_offset from dual union all
select 'POSSA8' asset_name,14 left_offset,52 top_offset from dual union all
select 'POSSB1' asset_name,21 left_offset,53 top_offset from dual union all
select 'POSSB2' asset_name,21 left_offset,53 top_offset from dual union all
select 'POSSB3' asset_name,24 left_offset,53 top_offset from dual union all
select 'POSSB4' asset_name,26 left_offset,53 top_offset from dual union all
select 'POSSB5' asset_name,18 left_offset,52 top_offset from dual union all
select 'POSSB6' asset_name,11 left_offset,52 top_offset from dual union all
select 'POSSB7' asset_name,20 left_offset,52 top_offset from dual union all
select 'POSSB8' asset_name,15 left_offset,52 top_offset from dual union all
select 'POSSG1' asset_name,19 left_offset,51 top_offset from dual union all
select 'POSSG2' asset_name,18 left_offset,51 top_offset from dual union all
select 'POSSG3' asset_name,20 left_offset,50 top_offset from dual union all
select 'POSSG4' asset_name,20 left_offset,48 top_offset from dual union all
select 'POSSG5' asset_name,17 left_offset,49 top_offset from dual union all
select 'POSSG6' asset_name,20 left_offset,48 top_offset from dual union all
select 'POSSG7' asset_name,19 left_offset,50 top_offset from dual union all
select 'POSSG8' asset_name,19 left_offset,53 top_offset from dual union all
select 'POSSL0' asset_name,25 left_offset,15 top_offset from dual union all
select 'PSTRA0' asset_name,16 left_offset,18 top_offset from dual union all
select 'PUNGA0' asset_name,-96 left_offset,-128 top_offset from dual union all
select 'PUNGB0' asset_name,-64 left_offset,-144 top_offset from dual union all
select 'ROCKA0' asset_name,5 left_offset,24 top_offset from dual union all
select 'SARGA1' asset_name,17 left_offset,55 top_offset from dual union all
select 'SARGA2A8' asset_name,25 left_offset,54 top_offset from dual union all
select 'SARGA3A7' asset_name,29 left_offset,53 top_offset from dual union all
select 'SARGA4A6' asset_name,25 left_offset,53 top_offset from dual union all
select 'SARGA5' asset_name,18 left_offset,54 top_offset from dual union all
select 'SARGB1' asset_name,17 left_offset,56 top_offset from dual union all
select 'SARGB2B8' asset_name,25 left_offset,55 top_offset from dual union all
select 'SARGB3B7' asset_name,26 left_offset,55 top_offset from dual union all
select 'SARGB4B6' asset_name,24 left_offset,52 top_offset from dual union all
select 'SARGB5' asset_name,15 left_offset,51 top_offset from dual union all
select 'SARGG1' asset_name,15 left_offset,57 top_offset from dual union all
select 'SARGG2G8' asset_name,14 left_offset,53 top_offset from dual union all
select 'SARGG3G7' asset_name,20 left_offset,53 top_offset from dual union all
select 'SARGG4G6' asset_name,19 left_offset,53 top_offset from dual union all
select 'SARGG5' asset_name,12 left_offset,51 top_offset from dual union all
select 'SARGN0' asset_name,22 left_offset,24 top_offset from dual union all
select 'SAWGA0' asset_name,-176 left_offset,-60 top_offset from dual union all
select 'SAWGB0' asset_name,-176 left_offset,-59 top_offset from dual union all
select 'SBOXA0' asset_name,17 left_offset,12 top_offset from dual union all
select 'SHOTA0' asset_name,21 left_offset,13 top_offset from dual union all
select 'SHTGA0' asset_name,-122 left_offset,-107 top_offset from dual union all
select 'SHTGB0' asset_name,-78 left_offset,-40 top_offset from dual union all
select 'SKULK0' asset_name,30 left_offset,46 top_offset from dual union all
select 'SOULA0' asset_name,12 left_offset,39 top_offset from dual union all
select 'SPOSA1' asset_name,17 left_offset,50 top_offset from dual union all
select 'SPOSA2A8' asset_name,15 left_offset,50 top_offset from dual union all
select 'SPOSA3A7' asset_name,17 left_offset,48 top_offset from dual union all
select 'SPOSA4A6' asset_name,22 left_offset,45 top_offset from dual union all
select 'SPOSA5' asset_name,17 left_offset,46 top_offset from dual union all
select 'SPOSB1' asset_name,17 left_offset,50 top_offset from dual union all
select 'SPOSB2B8' asset_name,13 left_offset,50 top_offset from dual union all
select 'SPOSB3B7' asset_name,16 left_offset,52 top_offset from dual union all
select 'SPOSB4B6' asset_name,20 left_offset,49 top_offset from dual union all
select 'SPOSB5' asset_name,17 left_offset,49 top_offset from dual union all
select 'SPOSG1' asset_name,16 left_offset,50 top_offset from dual union all
select 'SPOSG2G8' asset_name,16 left_offset,49 top_offset from dual union all
select 'SPOSG3G7' asset_name,21 left_offset,48 top_offset from dual union all
select 'SPOSG4G6' asset_name,17 left_offset,47 top_offset from dual union all
select 'SPOSG5' asset_name,17 left_offset,49 top_offset from dual union all
select 'SPOSL0' asset_name,26 left_offset,20 top_offset from dual union all
select 'STIMA0' asset_name,10 left_offset,10 top_offset from dual union all
select 'TRE2A0' asset_name,76 left_offset,120 top_offset from dual union all
select 'TROOA1' asset_name,23 left_offset,56 top_offset from dual union all
select 'TROOA2A8' asset_name,17 left_offset,57 top_offset from dual union all
select 'TROOA3A7' asset_name,16 left_offset,56 top_offset from dual union all
select 'TROOA4A6' asset_name,21 left_offset,58 top_offset from dual union all
select 'TROOA5' asset_name,25 left_offset,56 top_offset from dual union all
select 'TROOB1' asset_name,24 left_offset,58 top_offset from dual union all
select 'TROOB2B8' asset_name,23 left_offset,57 top_offset from dual union all
select 'TROOB3B7' asset_name,23 left_offset,59 top_offset from dual union all
select 'TROOB4B6' asset_name,18 left_offset,60 top_offset from dual union all
select 'TROOB5' asset_name,25 left_offset,58 top_offset from dual union all
select 'TROOG1' asset_name,37 left_offset,60 top_offset from dual union all
select 'TROOG2G8' asset_name,35 left_offset,59 top_offset from dual union all
select 'TROOG3G7' asset_name,37 left_offset,59 top_offset from dual union all
select 'TROOG4G6' asset_name,28 left_offset,58 top_offset from dual union all
select 'TROOG5' asset_name,32 left_offset,60 top_offset from dual union all
select 'TROOM0' asset_name,29 left_offset,22 top_offset from dual
;

create or replace view doom_r2_world_sprite_catalog as
with
state_rotations as (
  select state.state_id,state.sprite_prefix,state.sprite_frame,
    case when state.rotations='0' then 0 else rotation_no end rotation_no
  from doom_state_def state
  cross join (
    select level rotation_no from dual connect by level <= 8
  ) rotation_numbers
  where state.sprite_prefix is not null
    and state.sprite_frame is not null
    and (state.rotations <> '0' or rotation_no = 1)
),
asset_matches as (
  select state_rotations.state_id,state_rotations.rotation_no,
    asset.asset_id,asset.asset_name,asset.width,asset.height,
    metrics.left_offset,metrics.top_offset,
    case when substr(asset.asset_name,8,1)=to_char(state_rotations.rotation_no)
      then 1 else 0 end flip_x,
    row_number() over (
      partition by state_rotations.state_id,state_rotations.rotation_no
      order by
        case when substr(asset.asset_name,1,6)=
          state_rotations.sprite_prefix||state_rotations.sprite_frame||
          to_char(state_rotations.rotation_no)
          or substr(asset.asset_name,7,2)=state_rotations.sprite_frame||
          to_char(state_rotations.rotation_no) then 0 else 1 end,
        asset.asset_id
    ) match_ordinal
  from state_rotations
  join doom_asset asset
    on asset.asset_kind = 'sprite_patch'
   and substr(asset.asset_name,1,4)=state_rotations.sprite_prefix
   and (substr(asset.asset_name,6,1)=to_char(state_rotations.rotation_no)
     or substr(asset.asset_name,8,1)=to_char(state_rotations.rotation_no))
  join doom_r2_sprite_patch_metrics metrics
    on metrics.asset_name=asset.asset_name
),
rotation_zero as (
  select state.state_id,0 rotation_no,asset.asset_id,asset.asset_name,
    asset.width,asset.height,metrics.left_offset,metrics.top_offset,
    0 flip_x,
    row_number() over(partition by state.state_id order by
      case when asset.asset_name=state.sprite_prefix||state.sprite_frame||'0'
        then 0 else 1 end,asset.asset_id) match_ordinal
  from doom_state_def state
  join doom_asset asset
    on asset.asset_kind='sprite_patch'
   and substr(asset.asset_name,1,4)=state.sprite_prefix
   and substr(asset.asset_name,6,1)='0'
  join doom_r2_sprite_patch_metrics metrics
    on metrics.asset_name=asset.asset_name
  where state.sprite_prefix is not null
    and state.sprite_frame is not null
    and state.rotations='0'
),
resolved as (
  select * from asset_matches where match_ordinal=1
  union all
  select * from rotation_zero where match_ordinal=1
)
select resolved.state_id,resolved.rotation_no,resolved.asset_id,
  resolved.asset_name,resolved.width,resolved.height,
  resolved.left_offset,resolved.top_offset,resolved.flip_x
from resolved;

create or replace view doom_r2_masked_candidate_rows as
with
pose as (
  select /*+ materialize */ session_row.session_token,player.player_id,
    player.x player_x,player.y player_y,
    player.z+player.view_height+player.view_bob eye_z,player.angle,
    cos(player.angle*acos(-1)/180) forward_x,
    sin(player.angle*acos(-1)/180) forward_y,
    cast(160 as binary_double) projection_k
  from game_sessions session_row
  join players player
    on player.session_token=session_row.session_token
   and player.player_id=session_row.current_player_id
),
screen_pixels as (
  select /*+ materialize */ screen_columns.column_no,screen_rows.row_no,
    screen_rows.row_no+0.5 row_center
  from (select level-1 column_no from dual connect by level<=320) screen_columns
  cross join (select level-1 row_no from dual connect by level<=200) screen_rows
),
active_hits as (
  select /*+ materialize */ hit.*,
    row_number() over (
      partition by hit.session_token,hit.column_no
      order by hit.hit_t,hit.linedef_id,hit.seg_id,hit.facing_side
    )-1 active_ordinal
  from doom_r2_portal_hit_rows hit
  where hit.is_active=1
),
-- Reuse the active portal stream for interval ownership instead of expanding
-- DOOM_R2_SECTOR_INTERVAL_ROWS and its portal traversal again.
interval_hits as (
  select hit.*,
    hit.active_ordinal interval_ordinal,
    lag(hit.hit_t,1,0) over (
      partition by hit.session_token,hit.column_no
      order by hit.hit_t,hit.linedef_id,hit.seg_id,hit.facing_side
    ) t_start,
    lag(hit.to_sector_id,1,hit.from_sector_id) over (
      partition by hit.session_token,hit.column_no
      order by hit.hit_t,hit.linedef_id,hit.seg_id,hit.facing_side
    ) interval_sector_id
  from active_hits hit
),
closed_intervals as (
  select session_token,column_no,interval_ordinal,t_start,hit_t t_end,
    interval_sector_id sector_id,linedef_id terminating_linedef_id,0 is_final
  from interval_hits
),
last_active as (
  select interval_hits.*,
    row_number() over (
      partition by session_token,column_no
      order by hit_t desc,linedef_id desc,seg_id desc,facing_side desc
    ) reverse_ordinal
  from interval_hits
),
final_intervals as (
  select hit.session_token,hit.column_no,hit.interval_ordinal+1 interval_ordinal,
    hit.hit_t t_start,config.number_value t_end,hit.to_sector_id sector_id,
    cast(null as number) terminating_linedef_id,1 is_final
  from last_active hit
  join doom_config config on config.config_key='FAR_DISTANCE'
  where hit.reverse_ordinal=1 and hit.is_termination=0
),
sector_intervals as (
  select * from closed_intervals
  union all
  select * from final_intervals
),
hit_projection as (
  select hit.*,pose.eye_z,pose.projection_k,
    100-(hit.opening_top-pose.eye_z)*pose.projection_k/nullif(hit.hit_t,0)
      opening_top_y,
    100-(hit.opening_bottom-pose.eye_z)*pose.projection_k/nullif(hit.hit_t,0)
      opening_bottom_y
  from active_hits hit
  join pose on pose.session_token=hit.session_token
),
hit_windows as (
  select /*+ materialize */ hit_projection.*,
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
  from hit_projection
),
interval_windows as (
  select interval_row.session_token,interval_row.column_no,
    interval_row.interval_ordinal,interval_row.t_start,interval_row.t_end,
    interval_row.sector_id,coalesce(prior_hit.clip_top_after,0) clip_top,
    coalesce(prior_hit.clip_bottom_after,200) clip_bottom
  from sector_intervals interval_row
  left join hit_windows prior_hit
    on prior_hit.session_token=interval_row.session_token
   and prior_hit.column_no=interval_row.column_no
   and prior_hit.active_ordinal=interval_row.interval_ordinal-1
),
solid_depths as (
  select /*+ materialize */ session_token,column_no,min(hit_t) wall_depth
  from hit_windows
  where is_termination=1
  group by session_token,column_no
),
masked_geometry as (
  select hit.session_token,hit.column_no,hit.linedef_id source_id,
    hit.hit_t depth,hit.from_sector_id sector_id,side_row.middle_texture asset_name,
    side_row.x_offset,side_row.y_offset,seg.offset seg_offset,hit.hit_u,
    sqrt(power(v_end.x-v_start.x,2)+power(v_end.y-v_start.y,2)) seg_length,
    coalesce(live_sector.floor_height,map_sector.floor_height) floor_height,
    coalesce(live_sector.ceiling_height,map_sector.ceiling_height) ceiling_height,
    pose.eye_z,pose.projection_k,hit.clip_top_before,hit.clip_bottom_before
  from hit_windows hit
  join pose on pose.session_token=hit.session_token
  join doom_map_sidedef side_row on side_row.sidedef_id=hit.facing_sidedef_id
  join doom_map_seg seg on seg.seg_id=hit.seg_id
  join doom_map_vertex v_start on v_start.vertex_id=seg.start_vertex_id
  join doom_map_vertex v_end on v_end.vertex_id=seg.end_vertex_id
  join doom_map_sector map_sector on map_sector.sector_id=hit.from_sector_id
  left join sector_state live_sector
    on live_sector.session_token=hit.session_token
   and live_sector.sector_id=hit.from_sector_id
  where hit.is_transition=1 and side_row.middle_texture<>'-'
),
masked_samples as (
  select geometry.session_token,geometry.column_no,pixel.row_no,
    'MASKED' source_kind,geometry.source_id,geometry.depth,geometry.sector_id,
    asset.asset_name,
    cast(floor(geometry.seg_offset+geometry.x_offset+
      geometry.hit_u*geometry.seg_length)-asset.width*floor(
      floor(geometry.seg_offset+geometry.x_offset+
        geometry.hit_u*geometry.seg_length)/asset.width) as number) asset_x,
    cast(floor(geometry.ceiling_height-
      (geometry.eye_z+(100-pixel.row_center)*geometry.depth/
       geometry.projection_k)+geometry.y_offset)-asset.height*floor(
      floor(geometry.ceiling_height-
        (geometry.eye_z+(100-pixel.row_center)*geometry.depth/
         geometry.projection_k)+geometry.y_offset)/asset.height) as number) asset_y,
    asset.asset_id,0 rotation_no,0 flip_x,
    1 screen_visible,
    case when pixel.row_center>=geometry.clip_top_before
       and pixel.row_center<geometry.clip_bottom_before then 1 else 0 end
      sector_visible,
    case when wall.wall_depth is null
       or geometry.depth<wall.wall_depth-0.000000001 then 1 else 0 end wall_visible
  from masked_geometry geometry
  join screen_pixels pixel on pixel.column_no=geometry.column_no
  join doom_asset asset
    on asset.asset_kind='wall_texture'
   and asset.asset_name=geometry.asset_name
  left join solid_depths wall
    on wall.session_token=geometry.session_token
   and wall.column_no=geometry.column_no
),
sprite_geometry as (
  select mobj.session_token,mobj.mobj_id source_id,mobj.thing_type,
    mobj.state_id,mobj.x,mobj.y,mobj.z,mobj.angle,
    type_def.category,pose.player_x,pose.player_y,pose.eye_z,pose.angle view_angle,
    pose.forward_x,pose.forward_y,pose.projection_k,
    (mobj.x-pose.player_x)*pose.forward_x+
      (mobj.y-pose.player_y)*pose.forward_y depth,
    -(mobj.x-pose.player_x)*pose.forward_y+
      (mobj.y-pose.player_y)*pose.forward_x lateral,
    mod(floor((mod(atan2(pose.player_y-mobj.y,pose.player_x-mobj.x)*
      180/acos(-1)-mobj.angle+720,360)+22.5)/45),8)+1 rotation_no
  from mobjs mobj
  join pose on pose.session_token=mobj.session_token
  join doom_thing_type_def type_def on type_def.thing_type=mobj.thing_type
  join doom_state_def state_def on state_def.state_id=mobj.state_id
  where state_def.sprite_prefix is not null
),
sprite_assets as (
  select geometry.*,catalog.asset_id,catalog.asset_name,catalog.width,
    catalog.height,catalog.left_offset,catalog.top_offset,catalog.flip_x,
    160+geometry.lateral*geometry.projection_k/geometry.depth screen_center,
    geometry.projection_k/geometry.depth sprite_scale
  from sprite_geometry geometry
  join doom_r2_world_sprite_catalog catalog
    on catalog.state_id=geometry.state_id
   and catalog.rotation_no=case
     when exists(select 1 from doom_r2_world_sprite_catalog zero_frame
       where zero_frame.state_id=geometry.state_id
         and zero_frame.rotation_no=0) then 0 else geometry.rotation_no end
  -- The camera near plane prevents an object on the eye plane from expanding
  -- into an unbounded screen rectangle.  Analytic depth remains unrounded.
  where geometry.depth>1
),
sprite_bounds as (
  select sprite_assets.*,
    floor(screen_center-left_offset*sprite_scale) left_column,
    ceil(screen_center+(width-left_offset)*sprite_scale)-1 right_column,
    floor(100-(z+top_offset-eye_z)*sprite_scale) top_row,
    ceil(100-(z+top_offset-height-eye_z)*sprite_scale)-1 bottom_row
  from sprite_assets
),
sprite_samples as (
  select sprite.session_token,pixel.column_no,pixel.row_no,
    'SPRITE' source_kind,sprite.source_id,sprite.depth,interval.sector_id,
    sprite.asset_name,
    cast(least(sprite.width-1,greatest(0,floor(
      (pixel.column_no-sprite.left_column)*sprite.width/
      nullif(sprite.right_column-sprite.left_column+1,0)))) as number) asset_x,
    cast(least(sprite.height-1,greatest(0,floor(
      (pixel.row_no-sprite.top_row)*sprite.height/
      nullif(sprite.bottom_row-sprite.top_row+1,0)))) as number) asset_y,
    sprite.asset_id,sprite.rotation_no,sprite.flip_x,1 screen_visible,
    case when interval.sector_id is not null
       and pixel.row_no+0.5>=interval.clip_top
       and pixel.row_no+0.5<interval.clip_bottom then 1 else 0 end
      sector_visible,
    case when wall.wall_depth is null
       or sprite.depth<wall.wall_depth-0.000000001 then 1 else 0 end wall_visible
  from sprite_bounds sprite
  join screen_pixels pixel
    on pixel.column_no between greatest(0,sprite.left_column)
                           and least(319,sprite.right_column)
   and pixel.row_no between greatest(0,sprite.top_row)
                       and least(199,sprite.bottom_row)
  left join interval_windows interval
    on interval.session_token=sprite.session_token
   and interval.column_no=pixel.column_no
   and sprite.depth>=interval.t_start and sprite.depth<interval.t_end
  left join solid_depths wall
    on wall.session_token=sprite.session_token
   and wall.column_no=pixel.column_no
),
asset_first_opaque as (
  select asset_id,x,y
  from (
    select texel.a asset_id,texel.x,texel.y,
      row_number() over(partition by texel.a order by texel.y,texel.x) ordinal
    from at texel where texel.c>=0
  ) where ordinal=1
),
-- A fully off-screen billboard still exposes one representative opaque sample
-- so SCREEN_VISIBLE remains an observable clip fact without materializing an
-- unbounded rectangle for an object arbitrarily close to the camera plane.
sprite_offscreen_samples as (
  select sprite.session_token,
    cast(floor(sprite.left_column+(opaque.x+0.5)*
      (sprite.right_column-sprite.left_column+1)/sprite.width) as number)
      column_no,
    cast(floor(sprite.top_row+(opaque.y+0.5)*
      (sprite.bottom_row-sprite.top_row+1)/sprite.height) as number) row_no,
    'SPRITE' source_kind,sprite.source_id,sprite.depth,
    cast(null as number) sector_id,sprite.asset_name,
    case when sprite.flip_x=1 then sprite.width-1-opaque.x else opaque.x end
      asset_x,
    opaque.y asset_y,sprite.asset_id,sprite.rotation_no,
    sprite.flip_x,0 screen_visible,0 sector_visible,1 wall_visible
  from sprite_bounds sprite
  join asset_first_opaque opaque on opaque.asset_id=sprite.asset_id
  where sprite.right_column<0 or sprite.left_column>319
     or sprite.bottom_row<0 or sprite.top_row>199
),
opaque_candidates as (
  select sample.*,texel.c palette_index
  from (
    select * from masked_samples
    union all
    select * from sprite_samples
    union all
    select * from sprite_offscreen_samples
  ) sample
  join at texel
    on texel.a=sample.asset_id
   and texel.x=case when sample.flip_x=1
     then (select width from doom_asset where asset_id=sample.asset_id)-1-
       sample.asset_x else sample.asset_x end
   and texel.y=sample.asset_y
   and texel.c>=0
),
ranked as (
  select opaque_candidates.*,
    row_number() over (
      partition by session_token,column_no,row_no
      order by
        case when screen_visible=1 and sector_visible=1 and wall_visible=1
             then 0 else 1 end,
        depth,
        case source_kind when 'MASKED' then 0 else 1 end,
        source_id,asset_y,asset_x
    ) winner_ordinal
  from opaque_candidates
)
select session_token,column_no,row_no,source_kind,source_id,depth,sector_id,
  asset_name,asset_x,asset_y,palette_index,rotation_no,flip_x,
  screen_visible,sector_visible,wall_visible,
  case when screen_visible=1 and sector_visible=1 and wall_visible=1
         and winner_ordinal=1 then 1 else 0 end is_selected
from ranked;

create or replace function doom_r2_masked_candidates(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select candidate.*
    from doom_r2_masked_candidate_rows candidate
    where candidate.session_token=p_session
  ~';
end;
/

create or replace function doom_r2_masked_pixels(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select candidate.*
    from doom_r2_masked_candidate_rows candidate
    where candidate.session_token=p_session
      and candidate.is_selected=1
    order by candidate.column_no,candidate.row_no
  ~';
end;
/

commit;
