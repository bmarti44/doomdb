whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 serveroutput on size unlimited

begin
  execute immediate 'drop function doom_mle_flag_repeated';
exception when others then if sqlcode<>-4043 then raise;end if;
end;
/
begin
  execute immediate 'drop function doom_mle_flag_hoisted';
exception when others then if sqlcode<>-4043 then raise;end if;
end;
/
create function doom_mle_flag_repeated(p_iterations number) return number
as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'longFlagRepeatedChecksum(number)';
/
create function doom_mle_flag_hoisted(p_iterations number) return number
as mle module doom_teavm_simulation env doom_teavm_sim_env
signature 'longFlagHoistedChecksum(number)';
/

declare
  c_batches constant pls_integer:=20;
  c_iterations constant pls_integer:=200000;
  type values_t is table of number index by pls_integer;
  l_repeated values_t;l_hoisted values_t;
  l_started timestamp with time zone;l_a number;l_b number;l_value number;l_j pls_integer;
  function elapsed_ms(p_value interval day to second)return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+
      extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
  end;
  procedure sort_values(p_values in out nocopy values_t) is
  begin
    for i in 2..c_batches loop
      l_value:=p_values(i);l_j:=i-1;
      while l_j>=1 and p_values(l_j)>l_value loop
        p_values(l_j+1):=p_values(l_j);l_j:=l_j-1;
      end loop;
      p_values(l_j+1):=l_value;
    end loop;
  end;
begin
  l_a:=doom_mle_flag_repeated(10000);
  l_b:=doom_mle_flag_hoisted(10000);
  if l_a<>l_b then raise_application_error(-20796,'flag cast warmup checksum');end if;
  for i in 1..c_batches loop
    if mod(i,2)=1 then
      l_started:=systimestamp;l_a:=doom_mle_flag_repeated(c_iterations);
      l_repeated(i):=elapsed_ms(systimestamp-l_started);
      l_started:=systimestamp;l_b:=doom_mle_flag_hoisted(c_iterations);
      l_hoisted(i):=elapsed_ms(systimestamp-l_started);
    else
      l_started:=systimestamp;l_b:=doom_mle_flag_hoisted(c_iterations);
      l_hoisted(i):=elapsed_ms(systimestamp-l_started);
      l_started:=systimestamp;l_a:=doom_mle_flag_repeated(c_iterations);
      l_repeated(i):=elapsed_ms(systimestamp-l_started);
    end if;
    if l_a<>l_b then raise_application_error(-20796,'flag cast checksum');end if;
  end loop;
  sort_values(l_repeated);sort_values(l_hoisted);
  dbms_output.put_line('PMLE_LONG_FLAG_CAST|PASS|batches='||c_batches||
    '|iterations='||c_iterations||
    '|repeated_p50_ms='||round(l_repeated(10),3)||
    '|repeated_p95_ms='||round(l_repeated(19),3)||
    '|hoisted_p50_ms='||round(l_hoisted(10),3)||
    '|hoisted_p95_ms='||round(l_hoisted(19),3)||
    '|p50_speedup='||round(l_repeated(10)/l_hoisted(10),4)||
    '|checksum='||l_a);
end;
/
