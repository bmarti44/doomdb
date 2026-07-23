whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off
begin execute immediate 'drop function doom_mle_adb_arithmetic';
exception when others then if sqlcode<>-4043 then raise;end if;end;
/
begin execute immediate 'drop mle module doom_mle_adb_probe';
exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop mle env doom_mle_adb_env';
exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;
/
