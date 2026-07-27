whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off
begin execute immediate 'drop procedure doom_free_live_release';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_stats';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_frame_chunk';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_render_batch';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_render';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_finalize';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_load';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_free_live_allocate';exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_free_live_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_free_live_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
