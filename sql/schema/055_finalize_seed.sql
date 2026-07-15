insert into doom_linedef (
  linedef_id, start_vertex_id, end_vertex_id, flags, special, tag,
  right_sidedef_id, left_sidedef_id)
select linedef_id, start_vertex_id, end_vertex_id, flags, special, tag,
       right_sidedef_id, left_sidedef_id
 from doom_map_linedef
 order by linedef_id;

-- Immutable per-asset metadata avoids scanning and ranking all texels during
-- every masked-frame render merely to retain one off-screen witness sample.
merge into doom_asset asset
using (
  select a asset_id,
    min(x) keep (dense_rank first order by y,x) first_opaque_x,
    min(y) keep (dense_rank first order by y,x) first_opaque_y
  from at
  where c>=0
  group by a
) opaque
on (opaque.asset_id=asset.asset_id)
when matched then update set
  asset.first_opaque_x=opaque.first_opaque_x,
  asset.first_opaque_y=opaque.first_opaque_y;

alter table at add constraint at_pk primary key (a, x, y);
alter table at add constraint at_asset_fk foreign key (a)
  references doom_asset (asset_id) enable validate;

commit;
