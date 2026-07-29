whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
begin execute immediate 'drop mle module doom_plain_live_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_plain_renderer_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
commit;
