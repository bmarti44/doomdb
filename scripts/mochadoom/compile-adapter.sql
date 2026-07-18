whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off heading off

declare
  l_compiled number;
  l_missing number;
begin
  l_compiled:=dbms_java.compile_class('doomdb/mocha/DoomDbMochaAdapter');
  select count(*) into l_missing from user_java_methods
    where name='doomdb/mocha/DoomDbMochaAdapter'
      and method_name<>'<clinit>' and is_abstract='NO' and is_compiled<>'YES';
  if l_missing<>0 then
    raise_application_error(-20000,l_missing||' adapter methods are not native');
  end if;
  dbms_output.put_line('PASS MOCHADOOM-NATIVE-ADAPTER newly_compiled='||l_compiled);
end;
/
