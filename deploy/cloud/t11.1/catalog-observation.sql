whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off echo off feedback off heading off pagesize 0 linesize 32767 trimspool on serveroutput on size unlimited

declare
  l_cloud_service varchar2(128) := sys_context('USERENV','CLOUD_SERVICE');
  l_service       varchar2(128) := sys_context('USERENV','SERVICE_NAME');
  l_version       varchar2(128);
  l_cpu           number;
  l_storage_gb    number;
  l_invalid       number;
  l_errors        number;
  l_bad_cons      number;
  l_probe         number;
  l_sys           number;
  l_public        number;
  l_unexpected    number;
begin
  if l_cloud_service is null or l_cloud_service not in ('OLTP','APEX','AJD') then
    raise_application_error(-20801,'target is not an approved Autonomous workload');
  end if;
  select count(*) into l_probe from all_objects where owner='SYS' and object_name='DBMS_CLOUD' and object_type='PACKAGE';
  if l_probe != 1 then raise_application_error(-20802,'DBMS_CLOUD provenance is absent'); end if;
  select version into l_version from product_component_version
   where product like 'Oracle Database%' fetch first 1 row only;
  select to_number(value) into l_cpu from v$parameter where name='cpu_count';
  select greatest(1,ceil(sum(bytes)/power(1024,3))) into l_storage_gb from user_segments;
  select count(*) into l_invalid from user_objects where status <> 'VALID';
  select count(*) into l_errors from user_errors;
  select count(*) into l_bad_cons from user_constraints
   where status <> 'ENABLED' or validated <> 'VALIDATED';
  select count(*) into l_probe from user_objects where object_name like 'PROBE\_%' escape '\';
  select count(*) into l_sys from user_sys_privs where privilege in
    ('DBA','SYSDBA','SYSOPER','CREATE ANY PROCEDURE','ALTER ANY PROCEDURE','DROP ANY TABLE','UNLIMITED TABLESPACE');
  select count(*) into l_public from user_tab_privs
   where grantee='PUBLIC' and ((table_name='DOOM_API' and privilege='EXECUTE') or (table_name='PUBLIC_HEALTH' and privilege='SELECT'));
  select count(*) into l_unexpected from user_tab_privs
   where grantee='PUBLIC' and not ((table_name='DOOM_API' and privilege='EXECUTE') or (table_name='PUBLIC_HEALTH' and privilege='SELECT'));
  dbms_output.put_line('T111_TARGET|'||nvl(l_cloud_service,'NULL')||'|'||l_service||'|'||l_version);
  dbms_output.put_line('T111_RESOURCES|'||l_cpu||'|'||l_storage_gb);
  dbms_output.put_line('T111_CATALOG|'||l_invalid||'|'||l_errors||'|'||l_bad_cons||'|'||l_probe);
  dbms_output.put_line('T111_GRANTS|'||l_public||'|'||l_sys||'|'||l_unexpected);
end;
/

select 'T111_OBJECT|'||object_type||'|'||object_name||'|'||status
from user_objects order by object_type,object_name;
select 'T111_CONSTRAINT|'||table_name||'|'||constraint_name||'|'||constraint_type||'|'||status||'|'||validated
from user_constraints order by table_name,constraint_name;
select 'T111_PUBLIC_EXECUTE|'||table_name
from user_tab_privs where grantee='PUBLIC'
 and ((table_name='DOOM_API' and privilege='EXECUTE') or (table_name='PUBLIC_HEALTH' and privilege='SELECT')) order by table_name;
select 'T111_REST|'||object_name||'|'||object_type||'|'||status
from user_ords_enabled_objects order by object_name;
exit success commit
