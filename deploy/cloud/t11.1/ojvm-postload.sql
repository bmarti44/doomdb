whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off echo off feedback off heading off pagesize 0 serveroutput on

declare
  l_classes number;
  l_invalid number;
begin
  select count(*) into l_classes from user_java_classes;
  select count(*) into l_invalid from user_objects
    where object_type='JAVA CLASS' and status<>'VALID';
  if l_classes<>830 or l_invalid<>0 then
    raise_application_error(-20821,'OJVM post-load mismatch classes='||
      l_classes||' invalid='||l_invalid);
  end if;
  dbms_output.put_line('T111_OJVM_POSTLOAD|830|0');
end;
/
exit success commit
