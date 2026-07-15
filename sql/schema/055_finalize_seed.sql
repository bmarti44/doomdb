insert into doom_linedef (
  linedef_id, start_vertex_id, end_vertex_id, flags, special, tag,
  right_sidedef_id, left_sidedef_id)
select linedef_id, start_vertex_id, end_vertex_id, flags, special, tag,
       right_sidedef_id, left_sidedef_id
 from doom_map_linedef
 order by linedef_id;

alter table at add constraint at_pk primary key (a, x, y);
alter table at add constraint at_asset_fk foreign key (a)
  references doom_asset (asset_id) enable validate;

commit;
