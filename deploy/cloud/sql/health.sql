whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
set echo off

alter session set nls_numeric_characters = '.,';
alter session set nls_territory = 'AMERICA';
alter session set nls_language = 'AMERICAN';
alter session set time_zone = 'UTC';

-- DoomDB's deterministic documents require SHA-256 through DBMS_CRYPTO. The
-- deployment user must already have direct EXECUTE capability on this package;
-- fail before publishing any ORDS object when the Autonomous schema lacks it.
declare
  digest raw(32);
begin
  digest := dbms_crypto.hash(
    utl_raw.cast_to_raw('doomdb-capability-check'),
    dbms_crypto.hash_sh256);
  if utl_raw.length(digest) != 32 then
    raise_application_error(-20071, 'DBMS_CRYPTO_SHA256_UNAVAILABLE');
  end if;
end;
/

create or replace view public_health as
select 1 as healthy, 'doomdb' as service from dual;

begin
  ords.enable_schema(
    p_enabled             => true,
    p_schema              => sys_context('USERENV', 'CURRENT_SCHEMA'),
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'doom',
    p_auto_rest_auth      => false);
  ords.enable_object(
    p_enabled        => true,
    p_schema         => sys_context('USERENV', 'CURRENT_SCHEMA'),
    p_object         => 'PUBLIC_HEALTH',
    p_object_type    => 'VIEW',
    p_object_alias   => 'public_health',
    p_auto_rest_auth => false);
  commit;
end;
/
