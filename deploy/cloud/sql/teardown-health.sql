whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
set echo off

alter session set nls_numeric_characters = '.,';
alter session set nls_territory = 'AMERICA';
alter session set nls_language = 'AMERICAN';
alter session set time_zone = 'UTC';

begin
  ords.enable_object(
    p_enabled        => false,
    p_schema         => sys_context('USERENV', 'CURRENT_SCHEMA'),
    p_object         => 'PUBLIC_HEALTH',
    p_object_type    => 'VIEW',
    p_object_alias   => 'public_health',
    p_auto_rest_auth => false);
  commit;
end;
/

drop view public_health;
