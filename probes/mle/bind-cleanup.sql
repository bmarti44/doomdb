whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off
begin execute immediate 'drop function doom_mle_bind_frame';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_mle_bind_bench';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_mle_bind_sink purge';
exception when others then if sqlcode<>-942 then raise;end if;end;
/
