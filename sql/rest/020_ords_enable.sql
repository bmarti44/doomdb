whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off

alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

-- UNION ALL makes this minimal readiness projection intrinsically read-only.
-- It intentionally exposes neither session counts nor deployment details.
create or replace view public_health as
select 1 healthy,'doomdb' service from dual
union all
select 1,'doomdb' from dual where 1=0;

begin
  ords.enable_schema(
    p_enabled=>true,
    p_schema=>sys_context('USERENV','CURRENT_SCHEMA'),
    p_url_mapping_type=>'BASE_PATH',
    p_url_mapping_pattern=>lower(sys_context('USERENV','CURRENT_SCHEMA')),
    p_auto_rest_auth=>false);

  ords.enable_object(
    p_enabled=>true,
    p_schema=>sys_context('USERENV','CURRENT_SCHEMA'),
    p_object=>'DOOM_API',
    p_object_type=>'PACKAGE',
    p_object_alias=>'doom_api',
    p_auto_rest_auth=>false);

  ords.enable_object(
    p_enabled=>true,
    p_schema=>sys_context('USERENV','CURRENT_SCHEMA'),
    p_object=>'DOOM_WORKER_API',
    p_object_type=>'PACKAGE',
    p_object_alias=>'doom_worker_api',
    p_auto_rest_auth=>false);

  ords.enable_object(
    p_enabled=>true,
    p_schema=>sys_context('USERENV','CURRENT_SCHEMA'),
    p_object=>'PUBLIC_HEALTH',
    p_object_type=>'VIEW',
    p_object_alias=>'public_health',
    p_auto_rest_auth=>false);
  commit;
exception when others then
  rollback;
  raise_application_error(-20710,'ORDS object publication failed');
end;
/
