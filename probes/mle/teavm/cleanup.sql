whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin
  execute immediate 'drop function doom_teavm_checksum';
exception when others then if sqlcode <> -4043 then raise; end if;
end;
/
begin
  execute immediate 'drop mle module doom_teavm_probe';
exception when others then if sqlcode not in (-4080, -4103) then raise; end if;
end;
/
begin
  execute immediate 'drop table doom_teavm_source purge';
exception when others then if sqlcode <> -942 then raise; end if;
end;
/
