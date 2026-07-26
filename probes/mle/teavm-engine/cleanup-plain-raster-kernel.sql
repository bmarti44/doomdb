whenever sqlerror continue
begin execute immediate 'drop procedure doom_plain_raster_release';exception when others then null;end;
/
begin execute immediate 'drop function doom_plain_raster_footprint';exception when others then null;end;
/
begin execute immediate 'drop function doom_plain_raster_frame';exception when others then null;end;
/
begin execute immediate 'drop mle module doom_plain_raster_kernel';exception when others then null;end;
/
begin execute immediate 'drop table doom_plain_raster_source purge';exception when others then null;end;
/
commit;
