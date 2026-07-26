whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off
set echo off
set verify off
set feedback off
set heading off
set pagesize 0
set linesize 32767
set trimout on
set trimspool on
set tab off
set serveroutput on size unlimited

declare
  l_java_objects number;
  l_java_specs number;
  l_java_deps number;
  l_legacy_objects number;
  l_legacy_api number;
  l_mle_modules number;
  l_mle_envs number;
  l_mle_specs number;
  l_source_bytes number;
  l_source_sha varchar2(64);
  l_table_bytes number;
  l_table_sha varchar2(64);
  l_diagnostic_objects number;
  l_invalid number;
  l_errors number;
  l_rest_objects number;
  l_unexpected_rest number;
  l_hosted_modules number;
  l_hosted_templates number;
  l_hosted_handlers number;
begin
  if sys_context('USERENV','CLOUD_SERVICE') not in ('OLTP','APEX','AJD') then
    raise_application_error(-20801,'release audit requires Autonomous Database');
  end if;
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
  select count(*) into l_legacy_objects from user_objects
    where object_name in(
      'DOOM_WORKER_API','DOOM_UNIFIED_WORKER','DOOM_RENDER_WORKER',
      'DOOM_MOCHA_BRIDGE');
  select count(*) into l_legacy_api from user_procedures
    where object_name='DOOM_API' and procedure_name in(
      'POLL_MATCH_FRAME','NEW_GAME','STEP','SUBMIT_STEP','POLL_FRAME',
      'SAVE_GAME','LOAD_GAME','START_REPLAY','STEP_REPLAY');
  select count(*) into l_mle_modules from user_objects
    where object_name='DOOM_TEAVM_SIMULATION'
      and object_type='MLE MODULE' and status='VALID';
  select count(*) into l_mle_envs from user_objects
    where object_name='DOOM_TEAVM_SIM_ENV'
      and object_type='MLE ENVIRONMENT' and status='VALID';
  select count(*) into l_mle_specs from user_procedures
    where object_name like 'DOOM_TEAVM_SIM_%';
  select dbms_lob.getlength(source_blob),
    lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256))),
    dbms_lob.getlength(table_pack_blob),
    lower(rawtohex(dbms_crypto.hash(table_pack_blob,dbms_crypto.hash_sh256)))
    into l_source_bytes,l_source_sha,l_table_bytes,l_table_sha
    from doom_teavm_sim_source;
  select count(*) into l_diagnostic_objects from user_objects
    where object_name like 'DOOM_TEAVM_BIND%'
       or object_name like 'DOOM_TEAVM_FRAME%'
       or object_name like 'DOOM_MLE_PERF%';
  select count(*) into l_invalid from user_objects where status<>'VALID';
  select count(*) into l_errors from user_errors;
  select count(*) into l_rest_objects from user_ords_enabled_objects
    where parsing_object in('DOOM_API','PUBLIC_HEALTH');
  select count(*) into l_unexpected_rest from user_ords_enabled_objects
    where parsing_object not in('DOOM_API','PUBLIC_HEALTH');
  select count(*) into l_hosted_modules from user_ords_modules
    where name='doom.hosted.app';
  select count(*) into l_hosted_templates
  from user_ords_templates template_
  join user_ords_modules module_ on module_.id=template_.module_id
  where module_.name='doom.hosted.app';
  select count(*) into l_hosted_handlers
  from user_ords_handlers handler_
  join user_ords_templates template_ on template_.id=handler_.template_id
  join user_ords_modules module_ on module_.id=template_.module_id
  where module_.name='doom.hosted.app';

  if l_java_objects<>0 or l_java_specs<>0 or l_java_deps<>0 or
      l_legacy_objects<>0 or l_legacy_api<>0 then
    raise_application_error(-20803,'production Java-removal fence failed');
  end if;
  if l_mle_modules<>1 or l_mle_envs<>1 or l_mle_specs<>25 or
      l_source_bytes<>1081335 or
      l_source_sha<>
        '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3' or
      l_table_bytes<>180272 or
      l_table_sha<>
        '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44'
  then
    raise_application_error(-20804,'production MLE artifact fence failed');
  end if;
  if l_diagnostic_objects<>0 or l_invalid<>0 or l_errors<>0 then
    raise_application_error(-20805,'release catalog hygiene fence failed');
  end if;
  if l_rest_objects<>2 or l_unexpected_rest<>0 or
      l_hosted_modules<>1 or l_hosted_templates<>2 or l_hosted_handlers<>2
  then
    raise_application_error(-20806,'release ORDS surface fence failed');
  end if;

  dbms_output.put_line(
    'PMLE_OCI_JAVA_REMOVAL|PASS'||
    '|java_objects='||l_java_objects||
    '|java_specs='||l_java_specs||
    '|java_dependencies='||l_java_deps||
    '|legacy_objects='||l_legacy_objects||
    '|legacy_api='||l_legacy_api||
    '|mle_modules='||l_mle_modules||
    '|mle_environments='||l_mle_envs||
    '|mle_call_specs='||l_mle_specs||
    '|source_bytes='||l_source_bytes||
    '|source_sha256='||l_source_sha||
    '|table_bytes='||l_table_bytes||
    '|table_sha256='||l_table_sha||
    '|diagnostic_objects='||l_diagnostic_objects||
    '|invalid_objects='||l_invalid||
    '|source_errors='||l_errors||
    '|rest_objects='||l_rest_objects||
    '|unexpected_rest='||l_unexpected_rest||
    '|hosted_modules='||l_hosted_modules||
    '|hosted_templates='||l_hosted_templates||
    '|hosted_handlers='||l_hosted_handlers);
end;
/
