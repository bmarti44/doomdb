whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

-- Read-only, bounded dashboard payload for a bound live session. This reports
-- real database-authored camera and intersection rows; it creates no fixtures.
select json_object(
  'schema' value 1,
  'kind' value 'doomdb-r1-ray-diagnostic',
  'width' value 320,
  'columns' value json_arrayagg(
    json_object(
      'column' value ray.column_no,
      'camX' value ray.cam_x,
      'rayX' value ray.ray_x,
      'rayY' value ray.ray_y,
      'hitCount' value coalesce(hit_count.hit_count, 0),
      'nearestT' value nearest.hit_t,
      'nearestU' value nearest.hit_u,
      'linedefId' value nearest.linedef_id,
      'segId' value nearest.seg_id,
      'facingSide' value nearest.facing_side
      absent on null returning clob
    ) order by ray.column_no returning clob
  ) returning clob
) as diagnostic_json
from table(doom_r1_rays(:p_session)) ray
left join (
  select column_no, count(*) as hit_count
  from table(doom_r1_hits(:p_session))
  group by column_no
) hit_count
  on hit_count.column_no = ray.column_no
left join table(doom_r1_nearest(:p_session)) nearest
  on nearest.column_no = ray.column_no;
