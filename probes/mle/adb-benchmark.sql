whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_iterations constant pls_integer:=1000000;
  c_batch constant pls_integer:=20;
  l_started timestamp with time zone;l_interval interval day to second;
  l_seconds number;l_value number;l_ns number;
begin
  for i in 1..5 loop l_value:=doom_mle_adb_arithmetic(c_iterations,i);end loop;
  l_started:=systimestamp;
  for i in 1..c_batch loop
    l_value:=doom_mle_adb_arithmetic(c_iterations,i);
  end loop;
  l_interval:=systimestamp-l_started;
  l_seconds:=extract(day from l_interval)*86400+
    extract(hour from l_interval)*3600+extract(minute from l_interval)*60+
    extract(second from l_interval);
  l_ns:=l_seconds*1000000000/(c_iterations*c_batch);
  dbms_output.put_line('PMLE_ADB_VERSION|version='||dbms_db_version.version_full||
    '|db='||sys_context('USERENV','DB_NAME')||
    '|service='||sys_context('USERENV','SERVICE_NAME'));
  dbms_output.put_line('PMLE_ADB_ARITH|iterations='||c_iterations||
    '|batch='||c_batch||'|wall_ns_per_iteration='||
    round(l_ns,3)||
    '|checksum='||l_value);
  if l_ns<=15 then
    dbms_output.put_line('PMLE_ADB_DECISION|REOPEN_EXACT_RENDERER|threshold_ns=15');
  elsif l_ns>=100 then
    dbms_output.put_line('PMLE_ADB_DECISION|CLOSE_EXACT_RENDERER|threshold_ns=100');
  else
    dbms_output.put_line('PMLE_ADB_DECISION|INCONCLUSIVE_PRODUCTION_PROBE_REQUIRED|range_ns=15..100');
  end if;
end;
/
