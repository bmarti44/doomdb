whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off echo off feedback off heading off pagesize 0 serveroutput on

declare
  l_version varchar2(128);
begin
  select dbms_java.get_jdk_version into l_version from dual;
  if not (l_version like '1.8.%' or l_version like '11.%') then
    raise_application_error(-20820,'Autonomous OJVM must accept Java 8 bytecode');
  end if;
  dbms_output.put_line('T111_OJVM|VALID|'||l_version);
end;
/
exit success commit
