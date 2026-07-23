whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_warmups constant pls_integer:=20;
  c_samples constant pls_integer:=30;
  c_batch constant pls_integer:=20;
  type number_list is table of number index by pls_integer;
  l_samples number_list;l_started timestamp with time zone;l_value number;
  l_rows number;l_length number;l_j pls_integer;l_interval interval day to second;
begin
  for i in 1..c_warmups loop l_rows:=doom_mle_bind_frame(i);end loop;
  for i in 1..c_samples loop
    l_started:=systimestamp;
    for repetition_ in 1..c_batch loop
      l_rows:=doom_mle_bind_frame(i+repetition_);
    end loop;
    l_interval:=systimestamp-l_started;
    l_samples(i):=(extract(day from l_interval)*86400+
      extract(hour from l_interval)*3600+extract(minute from l_interval)*60+
      extract(second from l_interval))*1000/c_batch;
  end loop;
  for i in 2..c_samples loop l_value:=l_samples(i);l_j:=i-1;
    while l_j>=1 and l_samples(l_j)>l_value loop
      l_samples(l_j+1):=l_samples(l_j);l_j:=l_j-1;
    end loop;l_samples(l_j+1):=l_value;end loop;
  select dbms_lob.getlength(payload) into l_length from doom_mle_bind_sink where id=1;
  if l_rows<>1 or l_length<>64000 then
    raise_application_error(-20889,'session bind did not persist 64000 bytes');
  end if;
  dbms_output.put_line('PMLE_BIND|non_pure_session_execute_blob|bytes=64000' ||
    '|batch='||c_batch||'|samples='||c_samples||
    '|p50_ms='||round(l_samples(15),3)||'|p95_ms='||round(l_samples(29),3)||
    '|p99_ms='||round(l_samples(30),3)||'|max_ms='||round(l_samples(30),3));
end;
/
rollback;
