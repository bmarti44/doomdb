whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off lines 32767 trimspool on serveroutput on size unlimited
declare
  c_iterations constant pls_integer:=1000000;
  c_samples constant pls_integer:=20;
  type values_t is table of number index by pls_integer;
  l_state values_t;l_table values_t;l_started timestamp with time zone;
  l_state_sum number:=0;l_table_sum number:=0;l_a number;l_b number;
  function elapsed_ms(p_started timestamp with time zone)return number is
    l_elapsed interval day to second:=systimestamp-p_started;
  begin return extract(day from l_elapsed)*86400000+
    extract(hour from l_elapsed)*3600000+extract(minute from l_elapsed)*60000+
    extract(second from l_elapsed)*1000;end;
  function percentile(p_values values_t,p_count number,p_fraction number)return number is
    l_sorted values_t;l_value number;l_at pls_integer;
  begin
    for i in 1..p_count loop
      l_value:=p_values(i);l_at:=i-1;
      while l_at>=1 and l_sorted(l_at)>l_value loop
        l_sorted(l_at+1):=l_sorted(l_at);l_at:=l_at-1;
      end loop;
      l_sorted(l_at+1):=l_value;
    end loop;
    return l_sorted(ceil(p_count*p_fraction));
  end;
begin
  l_a:=doom_mle_dispatch_state(10000);l_b:=doom_mle_dispatch_table(10000);
  if l_a<>l_b then raise_application_error(-20793,'dispatch checksum warmup');end if;
  for sample in 1..c_samples loop
    l_started:=systimestamp;l_a:=doom_mle_dispatch_state(c_iterations);
    l_state(sample):=elapsed_ms(l_started);l_state_sum:=l_state_sum+l_a;
    l_started:=systimestamp;l_b:=doom_mle_dispatch_table(c_iterations);
    l_table(sample):=elapsed_ms(l_started);l_table_sum:=l_table_sum+l_b;
    if l_a<>l_b then raise_application_error(-20793,'dispatch checksum');end if;
  end loop;
  dbms_output.put_line('PMLE_ACTIVE_STATE_DISPATCH|iterations='||c_iterations||
    '|samples='||c_samples||'|state_p50_ms='||round(percentile(l_state,c_samples,.5),3)||
    '|state_p95_ms='||round(percentile(l_state,c_samples,.95),3)||
    '|table_p50_ms='||round(percentile(l_table,c_samples,.5),3)||
    '|table_p95_ms='||round(percentile(l_table,c_samples,.95),3)||
    '|checksum='||l_a);
end;
/
