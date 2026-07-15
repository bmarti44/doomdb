whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- R1 deliberately uses the nearest solid hit's facing sector for all three
-- layers.  Later portal rendering replaces that documented first-light limit.
create or replace view doom_r1_pixel_rows as
with
-- Oracle does not permit an analytic expression directly in WHERE.  The
-- public DOOM_R1_NEAREST macro supplies this same stable selection; this view
-- keeps the relational dependency explicit and gives it a query-block name.
selected as (
  select /*+ materialize */ pick.session_token,pick.column_no,pick.player_x,pick.player_y,
    pick.player_z,p.view_height,pick.angle_degrees,pick.ray_x,pick.ray_y,pick.hit_t,pick.hit_u,
    seg.offset seg_offset,sv.x seg_start_x,sv.y seg_start_y,
    ev.x seg_end_x,ev.y seg_end_y,line.flags linedef_flags,
    side_row.x_offset,side_row.y_offset,side_row.upper_texture,
    side_row.lower_texture,side_row.middle_texture,
    facing_sector.floor_height,facing_sector.ceiling_height,
    facing_sector.floor_flat,facing_sector.ceiling_flat,
    facing_sector.light_level,
    opposite_sector.floor_height opposite_floor_height,
    opposite_sector.ceiling_height opposite_ceiling_height
  from (
    select h.*,
      row_number() over (
        partition by h.session_token,h.column_no
        order by h.hit_t,h.linedef_id,h.seg_id,h.facing_side
      ) as pixel_hit_ordinal
    from doom_r1_hit_rows h where h.is_solid=1
  ) pick
  join players p on p.session_token=pick.session_token and p.player_id=pick.player_id
  join doom_map_seg seg on seg.seg_id=pick.seg_id
  join doom_map_vertex sv on sv.vertex_id=seg.start_vertex_id
  join doom_map_vertex ev on ev.vertex_id=seg.end_vertex_id
  join doom_map_linedef line on line.linedef_id=pick.linedef_id
  join doom_map_sidedef side_row on side_row.sidedef_id=pick.sidedef_id
  join doom_map_sector facing_sector on facing_sector.sector_id=side_row.sector_id
  left join doom_map_sidedef opposite_side on opposite_side.sidedef_id=pick.opposite_sidedef_id
  left join doom_map_sector opposite_sector on opposite_sector.sector_id=opposite_side.sector_id
  where pick.pixel_hit_ordinal=1
),
sample_rays as (
  select selected.*,
    selected.player_z+selected.view_height as eye_z,
    cast(320 as binary_double)/2
      /tan(cast(90 as binary_double)*cast(acos(-1) as binary_double)/360)
      as projection_k,
    cos(cast(selected.angle_degrees as binary_double)*cast(acos(-1) as binary_double)/180)
      -sin(cast(selected.angle_degrees as binary_double)*cast(acos(-1) as binary_double)/180)
       *tan(cast(90 as binary_double)*cast(acos(-1) as binary_double)/360)
       *(2*(cast(selected.column_no as binary_double)+0.5)/320-1) as sample_ray_x,
    sin(cast(selected.angle_degrees as binary_double)*cast(acos(-1) as binary_double)/180)
      +cos(cast(selected.angle_degrees as binary_double)*cast(acos(-1) as binary_double)/180)
       *tan(cast(90 as binary_double)*cast(acos(-1) as binary_double)/360)
       *(2*(cast(selected.column_no as binary_double)+0.5)/320-1) as sample_ray_y
  from selected
),
sample_intersections as (
  select sample_rays.*,
    sample_ray_x*(seg_end_y-seg_start_y)
      -sample_ray_y*(seg_end_x-seg_start_x) as sample_determinant
  from sample_rays
),
projected as (
  select sample_intersections.*,
    ((seg_start_x-player_x)*(seg_end_y-seg_start_y)
      -(seg_start_y-player_y)*(seg_end_x-seg_start_x))
      /sample_determinant as sample_hit_t,
    ((seg_start_x-player_x)*sample_ray_y
      -(seg_start_y-player_y)*sample_ray_x)
      /sample_determinant as sample_hit_u,
    100-(ceiling_height-eye_z)*projection_k
      /(((seg_start_x-player_x)*(seg_end_y-seg_start_y)
        -(seg_start_y-player_y)*(seg_end_x-seg_start_x))/sample_determinant) as y_top,
    100-(floor_height-eye_z)*projection_k
      /(((seg_start_x-player_x)*(seg_end_y-seg_start_y)
        -(seg_start_y-player_y)*(seg_end_x-seg_start_x))/sample_determinant) as y_bottom,
    greatest(0,least(31,floor((255-light_level)/8))) as light_band
  from sample_intersections
),
pixels as (
  select projected.*, screen_rows.row_no, screen_rows.row_no+0.5 as row_center,
    case when screen_rows.row_no+0.5>=projected.y_top
               and screen_rows.row_no+0.5<projected.y_bottom then 10
         when screen_rows.row_no+0.5<projected.y_top then 1 else 0 end layer_ordinal,
    projected.eye_z+(100-(screen_rows.row_no+0.5))*projected.sample_hit_t/projected.projection_k as wall_world_z
  from projected
  cross join (select level-1 row_no from dual connect by level<=200) screen_rows
),
classified as (
  select pixels.*,
    case when layer_ordinal=1 then ceiling_flat
         when layer_ordinal=0 then floor_flat
         when opposite_ceiling_height is null then middle_texture
         when wall_world_z>=opposite_ceiling_height and upper_texture!='-' then upper_texture
         when wall_world_z< opposite_ceiling_height and lower_texture!='-' then lower_texture
         when upper_texture!='-' then upper_texture
         when lower_texture!='-' then lower_texture else middle_texture end asset_name,
    case when layer_ordinal=10 then 'wall_texture' else 'flat' end asset_kind,
    case
      when layer_ordinal=1 then
        (ceiling_height-eye_z)*projection_k/(100-row_center)
      when layer_ordinal=0 then
        (eye_z-floor_height)*projection_k/(row_center-100)
    end plane_distance,
    case
      when opposite_ceiling_height is null then 'middle'
      when wall_world_z>=opposite_ceiling_height and upper_texture!='-' then 'upper'
      when wall_world_z< opposite_ceiling_height and lower_texture!='-' then 'lower'
      when upper_texture!='-' then 'upper'
      when lower_texture!='-' then 'lower' else 'middle'
    end wall_role
  from pixels
),
with_asset as (
  select classified.*, asset.asset_id,asset.width asset_width,asset.height asset_height,
    case when layer_ordinal=10 then
      seg_offset+x_offset+sample_hit_u*sqrt(
        power(seg_end_x-seg_start_x,2)+power(seg_end_y-seg_start_y,2))
    else player_x+sample_ray_x*plane_distance end sample_world_x,
    case when layer_ordinal=10 then
      case wall_role
        when 'upper' then
          case when bitand(linedef_flags,8)!=0
            then opposite_ceiling_height+asset.height else ceiling_height end
        when 'lower' then
          case when bitand(linedef_flags,16)!=0
            then ceiling_height else opposite_floor_height end
        else case when bitand(linedef_flags,16)!=0
          then floor_height+asset.height else ceiling_height end
      end-wall_world_z+y_offset
    else player_y+sample_ray_y*plane_distance end sample_world_y
  from classified
  join doom_asset asset
    on asset.asset_kind=classified.asset_kind
   and asset.asset_name=classified.asset_name
),
raw_texels as (
  select /*+ leading(with_asset) use_nl(texel) index(texel at_pk) */
    with_asset.*, texel.c raw_palette_index
  from with_asset
  join at texel on texel.a=with_asset.asset_id
   -- The renderer math is BINARY_DOUBLE, but AT coordinates are NUMBER.  Cast
   -- the integral floor-mod result once so all three AT primary-key columns
   -- remain index access predicates instead of scanning every texel per asset.
   and texel.x=cast(floor(sample_world_x)
     -asset_width*floor(floor(sample_world_x)/asset_width) as number)
   and texel.y=cast(floor(sample_world_y)
     -asset_height*floor(floor(sample_world_y)/asset_height) as number)
)
select raw_texels.session_token,raw_texels.column_no,raw_texels.row_no,
  colormap.mapped_index palette_index,raw_texels.layer_ordinal
from raw_texels
join doom_colormap_texel colormap
  on colormap.map_index=raw_texels.light_band
 and colormap.palette_index=raw_texels.raw_palette_index
where raw_texels.raw_palette_index>=0
order by raw_texels.column_no,raw_texels.row_no;

create or replace function doom_r1_pixels(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select pixel.session_token,pixel.column_no,pixel.row_no,
      pixel.palette_index,pixel.layer_ordinal
    from doom_r1_pixel_rows pixel
    join game_sessions session_row
      on session_row.session_token=pixel.session_token
    where pixel.session_token=p_session
    order by pixel.column_no,pixel.row_no
  ~';
end;
/

commit;
