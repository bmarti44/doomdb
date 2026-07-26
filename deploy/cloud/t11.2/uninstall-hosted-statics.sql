whenever sqlerror exit failure rollback
set define off

begin
  ords.delete_module(p_module_name=>'doom.hosted.app');
  commit;
end;
/

declare
  l_exists number;
begin
  select count(*) into l_exists from user_tables
    where table_name='DOOM_HOSTED_ASSET';
  if l_exists=1 then
    execute immediate
      'drop table doom_hosted_asset cascade constraints purge';
  end if;
end;
/

select 'T112_HOSTED_STATIC_UNINSTALL|PASS' as result from dual;
