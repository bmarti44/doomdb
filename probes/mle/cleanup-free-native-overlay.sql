whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
begin
  execute immediate 'drop package doom_free_native_overlay';
exception when others then
  if sqlcode<>-4043 then raise;end if;
end;
/
