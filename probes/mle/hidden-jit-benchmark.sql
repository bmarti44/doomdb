whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
set linesize 32767 trimspool on

declare
  c_iterations constant pls_integer := 1000000;
  c_samples constant pls_integer := 40;
  l_started timestamp with time zone;
  l_elapsed interval day to second;
  l_elapsed_ms number;
  l_checksum number;
  l_label varchar2(64);

  function elapsed_ms(p_elapsed interval day to second) return number is
  begin
    return extract(day from p_elapsed)*86400000+
      extract(hour from p_elapsed)*3600000+
      extract(minute from p_elapsed)*60000+
      extract(second from p_elapsed)*1000;
  end;
begin
  select action into l_label from v$session
    where sid=to_number(sys_context('USERENV','SID'));

  dbms_output.put_line('PMLE_HIDDEN_JIT|DIAGNOSTIC_NOT_GATE|cell='||l_label||
    '|iterations='||c_iterations||'|samples='||c_samples);

  for i in 1..c_samples loop
    l_started:=systimestamp;
    l_checksum:=doom.doom_mle_bench_arithmetic(c_iterations,17+i);
    l_elapsed:=systimestamp-l_started;
    l_elapsed_ms:=elapsed_ms(l_elapsed);
    dbms_output.put_line('PMLE_HIDDEN_JIT_SAMPLE|cell='||l_label||
      '|sample='||i||
      '|elapsed_ms='||
        to_char(l_elapsed_ms,'FM999999990D000','NLS_NUMERIC_CHARACTERS=''.,''')||
      '|ns_per_iteration='||
        to_char(l_elapsed_ms*1000000/c_iterations,
          'FM999999990D000','NLS_NUMERIC_CHARACTERS=''.,''')||
      '|checksum='||l_checksum);
  end loop;

  dbms_output.put_line('PMLE_HIDDEN_JIT|PASS|cell='||l_label||
    '|terminal_samples='||c_samples||'|classification=DIAGNOSTIC_NOT_GATE');
end;
/
