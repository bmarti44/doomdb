insert into doom_render_profile(profile_id,width,height,horizontal_fov)
values('CANONICAL_320X200',320,200,90);

insert into doom_screen_column(profile_id,column_no,camera_x)
select 'CANONICAL_320X200',level-1,2*((level-1)+0.5)/320-1
from dual connect by level<=320;

insert into doom_screen_row(profile_id,row_no,row_center)
select 'CANONICAL_320X200',level-1,(level-1)+0.5
from dual connect by level<=200;

insert into doom_render_ray(
  profile_id,orientation_ordinal,column_no,angle_degrees,angle_radians,
  direction_x,direction_y,plane_x,plane_y,cam_x,ray_x,ray_y,
  ray_length_squared)
with orientations as (
  select level-1 orientation_ordinal,(level-1)*5.625 angle_degrees
  from dual connect by level<=64
), coefficients as (
  select axis.profile_id,orientation.orientation_ordinal,axis.column_no,
    orientation.angle_degrees,
    cast(orientation.angle_degrees*acos(-1)/180 as binary_double) angle_radians,
    axis.camera_x cam_x
  from orientations orientation
  cross join doom_screen_column axis
  where axis.profile_id='CANONICAL_320X200'
), vectors as (
  select coefficients.*,
    cos(angle_radians) direction_x,sin(angle_radians) direction_y,
    -sin(angle_radians)*tan(cast((90*acos(-1)/180)/2 as binary_double)) plane_x,
    cos(angle_radians)*tan(cast((90*acos(-1)/180)/2 as binary_double)) plane_y
  from coefficients
), rays as (
  select vectors.*,direction_x+plane_x*cam_x ray_x,
    direction_y+plane_y*cam_x ray_y
  from vectors
)
select profile_id,orientation_ordinal,column_no,angle_degrees,angle_radians,
  direction_x,direction_y,plane_x,plane_y,cam_x,ray_x,ray_y,
  ray_x*ray_x+ray_y*ray_y
from rays;

commit;
