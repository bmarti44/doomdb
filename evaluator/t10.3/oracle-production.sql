set serveroutput on size unlimited heading off feedback off pages 0 lines 32767 trimspool on
declare
  l_invalid number; l_constraints number; l_forbidden number; l_rest varchar2(4000); l_obj_hash varchar2(64); l_con_hash varchar2(64);
  procedure require(p boolean,m varchar2) is begin if not p then raise_application_error(-20991,m); end if; end;
begin
  select count(*) into l_invalid from user_objects where status <> 'VALID';
  select count(*) into l_constraints from user_constraints where status <> 'ENABLED' or validated <> 'VALIDATED';
  select count(*) into l_forbidden from user_objects where regexp_like(object_name,'(^|_)(EVAL|FIXTURE|GOLDEN|TEST|MOCK|REFERENCE)($|_)');
  select standard_hash(coalesce(listagg(object_type||':'||object_name||':'||status,'|') within group(order by object_type,object_name),'EMPTY'),'SHA256') into l_obj_hash from user_objects;
  select standard_hash(coalesce(listagg(table_name||':'||constraint_name||':'||constraint_type||':'||status||':'||validated,'|') within group(order by table_name,constraint_name),'EMPTY'),'SHA256') into l_con_hash from user_constraints;
  select coalesce(json_arrayagg(object_name order by object_name returning varchar2),'[]') into l_rest from user_ords_enabled_objects;
  require(l_invalid=0,'invalid production objects'); require(l_constraints=0,'disabled or unvalidated constraints'); require(l_forbidden=0,'evaluator-shaped schema object'); require(l_rest='["DOOM_API","PUBLIC_HEALTH"]','AutoREST exposure differs');
  dbms_output.put_line('T103_SCHEMA_LEDGER '||json_object('invalidObjects' value l_invalid,'disabledOrUnvalidatedConstraints' value l_constraints,'enabledRestObjects' value l_rest format json,'forbiddenObjects' value json_array() format json,'objectFingerprintSha256' value lower(l_obj_hash),'constraintFingerprintSha256' value lower(l_con_hash) returning varchar2));
  dbms_output.put_line('T103_CORRECTNESS schema '||lower(l_obj_hash));
  dbms_output.put_line('PASS T10.3-SCHEMA-AUDIT (6/6 live catalog assertions)');
end;
/
