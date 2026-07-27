whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
begin execute immediate 'drop function doom_free_raster_frame_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_command_count';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_batch';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_render';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_command_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_command_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_atlas_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_raster_atlas_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_free_raster_kernel';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_free_raster_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
commit;
