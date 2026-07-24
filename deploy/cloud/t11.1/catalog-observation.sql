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
  l_java_objects  number;
  l_java_specs    number;
  l_java_deps     number;
  l_legacy        number;
  l_legacy_api    number;
  l_mle_modules   number;
  l_mle_envs      number;
  l_mle_specs     number;
  l_source_bytes  number;
  l_source_sha    varchar2(64);
  l_table_bytes   number;
  l_table_sha     varchar2(64);
  l_iwad_sha      varchar2(64);
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
  select count(*) into l_java_objects from user_objects
    where object_type like 'JAVA%';
  select count(*) into l_java_specs
  from user_objects object_
  where object_type in('FUNCTION','PROCEDURE')
    and exists (
      select 1 from user_source source_
      where source_.name=object_.object_name
        and source_.type=object_.object_type
        and regexp_like(source_.text,'LANGUAGE[[:space:]]+JAVA','i'));
  select count(*) into l_java_deps from user_dependencies
    where referenced_type like 'JAVA%';
  select count(*) into l_legacy from user_objects
    where object_name in('DOOM_WORKER_API','DOOM_UNIFIED_WORKER',
      'DOOM_RENDER_WORKER','DOOM_MOCHA_BRIDGE');
  select count(*) into l_legacy_api from user_procedures
    where object_name='DOOM_API' and procedure_name in(
      'POLL_MATCH_FRAME','NEW_GAME','STEP','SUBMIT_STEP','POLL_FRAME',
      'SAVE_GAME','LOAD_GAME','START_REPLAY','STEP_REPLAY');
  select count(*) into l_mle_modules from user_objects
    where object_name='DOOM_TEAVM_SIMULATION' and object_type='MLE MODULE'
      and status='VALID';
  select count(*) into l_mle_envs from user_objects
    where object_name='DOOM_TEAVM_SIM_ENV' and object_type='MLE ENVIRONMENT'
      and status='VALID';
  select count(*) into l_mle_specs from user_procedures
    where object_name like 'DOOM_TEAVM_SIM_%';
  select dbms_lob.getlength(source_blob),
    lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256))),
    dbms_lob.getlength(table_pack_blob),
    lower(rawtohex(dbms_crypto.hash(table_pack_blob,dbms_crypto.hash_sh256)))
    into l_source_bytes,l_source_sha,l_table_bytes,l_table_sha
    from doom_teavm_sim_source;
  select payload_sha256 into l_iwad_sha from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  if l_java_objects<>0 or l_java_specs<>0 or l_java_deps<>0 or
     l_legacy<>0 or l_legacy_api<>0 then
    raise_application_error(-20803,'Java/OJVM production fence failed');
  end if;
  if l_mle_modules<>1 or l_mle_envs<>1 or l_mle_specs<>24 or
     l_source_bytes<>1170639 or
     l_source_sha<>'103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e' or
     l_table_bytes<>180272 or
     l_table_sha<>'058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44' or
     l_iwad_sha<>'7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d' then
    raise_application_error(-20804,'pinned MLE production artifact fence failed');
  end if;
  dbms_output.put_line('T111_TARGET|'||nvl(l_cloud_service,'NULL')||'|'||l_service||'|'||l_version);
  dbms_output.put_line('T111_RESOURCES|'||l_cpu||'|'||l_storage_gb);
  dbms_output.put_line('T111_CATALOG|'||l_invalid||'|'||l_errors||'|'||l_bad_cons||'|'||l_probe);
  dbms_output.put_line('T111_GRANTS|'||l_public||'|'||l_sys||'|'||l_unexpected);
  dbms_output.put_line('T111_MLE|'||l_mle_modules||'|'||l_mle_envs||'|'||
    l_mle_specs||'|'||l_source_bytes||'|'||l_source_sha||'|'||
    l_table_bytes||'|'||l_table_sha||'|'||l_iwad_sha);
  dbms_output.put_line('T111_JAVA_REMOVAL|'||l_java_objects||'|'||
    l_java_specs||'|'||l_java_deps||'|'||l_legacy||'|'||l_legacy_api);
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
