whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- R2 keeps the complete DOOM_R1_HITS analytic hit stream through its canonical
-- DOOM_R1_HIT_ROWS backing view.  The camera sector for each ordered ray is the
-- first facing sector; current sector heights prefer the live sector machine and
-- fall back to immutable map heights for sessions which have not started the
-- machine yet.
-- In Oracle scalar row comparisons, GREATEST/LEAST implement the opening's
-- mathematical MAX/MIN and preserves each ray hit's unrounded depth.
create or replace view doom_r2_hit_geometry as
with
resolved as (
  select
    hit.session_token,
    hit.column_no,
    hit.hit_ordinal,
    hit.hit_t,
    hit.hit_u,
    hit.linedef_id,
    hit.seg_id,
    hit.facing_side,
    hit.sidedef_id as facing_sidedef_id,
    hit.opposite_sidedef_id,
    facing_side.sector_id as facing_sector_id,
    opposite_side.sector_id as opposite_sector_id,
    first_value(facing_side.sector_id) over (
      partition by hit.session_token, hit.column_no
      order by hit.hit_t, hit.linedef_id, hit.seg_id, hit.facing_side
      rows between unbounded preceding and unbounded following
    ) as start_sector_id,
    coalesce(facing_state.floor_height, facing_map.floor_height)
      as facing_floor_height,
    coalesce(facing_state.ceiling_height, facing_map.ceiling_height)
      as facing_ceiling_height,
    coalesce(opposite_state.floor_height, opposite_map.floor_height)
      as opposite_floor_height,
    coalesce(opposite_state.ceiling_height, opposite_map.ceiling_height)
      as opposite_ceiling_height
  from doom_r1_hit_rows hit
  left join doom_map_sidedef facing_side
    on facing_side.sidedef_id = hit.sidedef_id
  left join doom_map_sidedef opposite_side
    on opposite_side.sidedef_id = hit.opposite_sidedef_id
  left join doom_map_sector facing_map
    on facing_map.sector_id = facing_side.sector_id
  left join doom_map_sector opposite_map
    on opposite_map.sector_id = opposite_side.sector_id
  left join sector_state facing_state
    on facing_state.session_token = hit.session_token
   and facing_state.sector_id = facing_side.sector_id
  left join sector_state opposite_state
    on opposite_state.session_token = hit.session_token
   and opposite_state.sector_id = opposite_side.sector_id
),
pieces as (
  select resolved.*,
    case when opposite_sector_id is not null
      then greatest(facing_floor_height, opposite_floor_height) end
      as opening_bottom,
    case when opposite_sector_id is not null
      then least(facing_ceiling_height, opposite_ceiling_height) end
      as opening_top,
    case when opposite_floor_height > facing_floor_height
      then facing_floor_height end as lower_bottom,
    case when opposite_floor_height > facing_floor_height
      then opposite_floor_height end as lower_top,
    case when opposite_ceiling_height < facing_ceiling_height
      then opposite_ceiling_height end as upper_bottom,
    case when opposite_ceiling_height < facing_ceiling_height
      then facing_ceiling_height end as upper_top,
    case
      when opposite_sector_id is null then 1
      when least(facing_ceiling_height, opposite_ceiling_height)
           <= greatest(facing_floor_height, opposite_floor_height) then 1
      else 0
    end as is_closed_base
  from resolved
)
select pieces.*,
  case when is_closed_base = 0 then opposite_sector_id end as next_sector_id,
  case when is_closed_base = 1 then 1 else 0 end as is_termination_base
from pieces;

-- MATCH_RECOGNIZE expresses the ordered finite-state walk without a recursive
-- render CTE or procedural iteration.  ACTIVE is tried before INACTIVE.  Its
-- previous occurrence supplies the current sector and the termination latch.
create or replace view doom_r2_portal_hit_rows as
select
  session_token,
  column_no,
  hit_ordinal,
  hit_t,
  hit_u,
  linedef_id,
  seg_id,
  facing_side,
  facing_sidedef_id,
  opposite_sidedef_id,
  facing_sector_id,
  opposite_sector_id,
  case match_class when 'ACTIVE' then 1 else 0 end as is_active,
  case match_class when 'ACTIVE' then facing_sector_id end as from_sector_id,
  case
    when match_class = 'ACTIVE' and is_closed_base = 0
      then opposite_sector_id
  end as to_sector_id,
  opening_bottom,
  opening_top,
  lower_bottom,
  lower_top,
  upper_bottom,
  upper_top,
  is_closed_base as is_closed,
  case when match_class = 'ACTIVE' and is_closed_base = 0 then 1 else 0 end
    as is_transition,
  case when match_class = 'ACTIVE' and is_closed_base = 1 then 1 else 0 end
    as is_termination
from doom_r2_hit_geometry
match_recognize (
  partition by session_token, column_no
  order by hit_t, linedef_id, seg_id, facing_side
  measures classifier() as match_class
  all rows per match
  after match skip past last row
  pattern ((active | inactive)*)
  define
    active as
      active.facing_sector_id = coalesce(
        last(active.next_sector_id, 1),
        active.start_sector_id
      )
      and coalesce(last(active.is_termination_base, 1), 0) = 0,
    inactive as 1 = 1
);

create or replace function doom_r2_portal_hits(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select hit.*
    from doom_r2_portal_hit_rows hit
    where hit.session_token = p_session
  ~';
end;
/

-- Each active crossing closes the current sector interval.  An unterminated
-- column receives one final interval ending at the configured far distance.
create or replace view doom_r2_sector_interval_rows as
with
active_hits as (
  select hit.*,
    row_number() over (
      partition by session_token, column_no
      order by hit_t, linedef_id, seg_id, facing_side
    ) - 1 as interval_ordinal,
    lag(hit_t, 1, 0) over (
      partition by session_token, column_no
      order by hit_t, linedef_id, seg_id, facing_side
    ) as t_start,
    lag(to_sector_id, 1, from_sector_id) over (
      partition by session_token, column_no
      order by hit_t, linedef_id, seg_id, facing_side
    ) as interval_sector_id
  from doom_r2_portal_hit_rows hit
  where is_active = 1
),
closed_intervals as (
  select
    session_token,
    column_no,
    interval_ordinal,
    t_start,
    hit_t as t_end,
    interval_sector_id as sector_id,
    linedef_id as terminating_linedef_id,
    0 as is_final
  from active_hits
),
last_active as (
  select active_hits.*,
    row_number() over (
      partition by session_token, column_no
      order by hit_t desc, linedef_id desc, seg_id desc, facing_side desc
    ) as reverse_ordinal
  from active_hits
),
final_intervals as (
  select
    last_active.session_token,
    last_active.column_no,
    last_active.interval_ordinal + 1 as interval_ordinal,
    last_active.hit_t as t_start,
    config.number_value as t_end,
    last_active.to_sector_id as sector_id,
    cast(null as number) as terminating_linedef_id,
    1 as is_final
  from last_active
  join doom_config config
    on config.config_key = 'FAR_DISTANCE'
  where last_active.reverse_ordinal = 1
    and last_active.is_termination = 0
)
select * from closed_intervals
union all
select * from final_intervals;

create or replace function doom_r2_sector_intervals(
  p_session varchar2
) return varchar2 sql_macro(table)
is
begin
  return q'~
    select interval_row.*
    from doom_r2_sector_interval_rows interval_row
    where interval_row.session_token = p_session
  ~';
end;
/

-- Dynamic-schema installation changes PLAYER metadata after R1 is created.
-- Revalidate the otherwise unchanged R1 pixel view at the final render stage.
alter view doom_r1_pixel_rows compile;

commit;
