whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  session_ constant varchar2(32):='0123456789abcdef0123456789abcdef';
  result_ varchar2(4000);
begin
  result_:=doom_resident_sim_load_player(session_,0,0,0d,0d,0d,0d);
  if result_<>'OK' then raise_application_error(-20000,result_);end if;
  -- Warm allocation/JIT-visible paths before retaining the reported sample.
  result_:=doom_resident_sim_benchmark_turn(session_,100000);
  result_:=doom_resident_sim_benchmark_turn(session_,10000000);
  if substr(result_,1,3)<>'OK|' then raise_application_error(-20000,result_);end if;
  dbms_output.put_line('resident_sim_turn_benchmark='||result_);
end;
/
