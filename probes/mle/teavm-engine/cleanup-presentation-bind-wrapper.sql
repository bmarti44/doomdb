whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off
begin execute immediate 'drop procedure doom_teavm_bind_release';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_probe_direct';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_direct_mode';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_persist_locator';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_persist_direct';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_persist';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_frame_chunk';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_frame_length';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_authority_step';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_multi_init_game';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_table_load';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_table_allocate';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_load';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop function doom_teavm_bind_allocate';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_teavm_presentation_bind';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop mle env doom_teavm_presentation_bind_env';
exception when others then
  if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;
end;
/
begin execute immediate 'drop table doom_teavm_frame_sink purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
begin execute immediate 'drop table doom_teavm_bind_source purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
