whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off timing on

declare
  compiled_main number;
  compiled_json number;
  compiled_kernel number;
  missing_methods number;
begin
  -- OJVM's asynchronous JIT otherwise spends roughly a minute compiling in
  -- every newly claimed game-worker session.  Compile synchronously at deploy
  -- time so stored native code is shared by all later sessions.
  compiled_main := dbms_java.compile_class('DoomBspKernelBench');
  compiled_json := dbms_java.compile_class('DoomBspKernelBench$JsonInput');
  compiled_kernel := dbms_java.compile_class('DoomBspKernelBench$KernelInput');

  select count(*)
    into missing_methods
    from user_java_methods
   where name in (
       'DoomBspKernelBench',
       'DoomBspKernelBench$JsonInput',
       'DoomBspKernelBench$KernelInput')
     and is_compiled <> 'YES'
     and method_name <> '<clinit>';
  if missing_methods <> 0 then
    raise_application_error(-20000,
      missing_methods || ' OJVM renderer methods are not compiled');
  end if;

  dbms_output.put_line('OJVM_RENDERER_COMPILED main=' || compiled_main ||
    ' json=' || compiled_json || ' kernel=' || compiled_kernel);
end;
/

select name || ' methods=' || count(*) ||
  ' compiled=' || sum(case when is_compiled = 'YES' then 1 else 0 end)
from user_java_methods
where name in (
  'DoomBspKernelBench',
  'DoomBspKernelBench$JsonInput',
  'DoomBspKernelBench$KernelInput')
group by name
order by name;

exit
