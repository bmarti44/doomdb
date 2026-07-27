whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
begin execute immediate 'drop function doom_free_blob_ref_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_ref_frame';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_stats';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_frame_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_frame';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_reset';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_texture_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_texture_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_texture_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_blob_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle env doom_free_blob_env';exception when others then if sqlcode not in(-4080,-4103,-4105) then raise;end if;end;
/
begin execute immediate 'drop mle module doom_free_blob_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_free_blob_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
commit;
