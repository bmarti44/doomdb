whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

-- Managed ORDS calls only the two reviewed public objects. Static engine tables,
-- dynamic state, helpers, and probe objects receive no PUBLIC privilege.
begin
  execute immediate 'revoke select on doom_config from public';
exception when others then
  if sqlcode != -1927 then raise; end if;
end;
/
grant execute on doom_api to public;
grant select on public_health to public;
commit;
