whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off
begin
  execute immediate 'drop package doom_mle_native_bench';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
