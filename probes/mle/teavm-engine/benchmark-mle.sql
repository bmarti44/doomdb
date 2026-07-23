whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_chunk_bytes constant pls_integer:=32767;
  c_warmup constant pls_integer:=30;
  c_samples constant pls_integer:=3000;
  c_slot_ms constant number:=1000/35;
  type samples_t is table of number index by pls_integer;
  l_samples samples_t;
  l_backlogs samples_t;
  l_wad blob;l_table_pack blob;l_chunk raw(32767);l_length pls_integer;
  l_iwad_length pls_integer;l_offset pls_integer:=0;
  l_next number;l_state varchar2(32767);l_started timestamp with time zone;
  l_ms number;l_value number;l_j pls_integer;l_run_started timestamp with time zone;
  l_total_ms number;l_backlog number:=0;l_max_backlog number:=0;
  l_over_slot pls_integer:=0;
  function elapsed_ms(p_value interval day to second)return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
  end;
begin
  select payload_bytes into l_wad from doom_engine_artifact
   where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);
  l_iwad_length:=l_length;
  l_next:=doom_teavm_sim_allocate(l_length);
  if l_next<>l_length then raise_application_error(-20000,'IWAD allocation mismatch');end if;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(c_chunk_bytes,l_length-l_offset),l_offset+1);
    l_next:=doom_teavm_sim_load(l_offset,l_chunk);
    if l_next<>l_offset+utl_raw.length(l_chunk) then
      raise_application_error(-20001,'IWAD load offset mismatch');
    end if;
    l_offset:=l_next;
  end loop;
  select table_pack_blob into l_table_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_table_pack);l_offset:=0;
  l_next:=doom_teavm_sim_table_allocate(l_length);
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_table_pack,
      least(c_chunk_bytes,l_length-l_offset),l_offset+1);
    l_next:=doom_teavm_sim_table_load(l_offset,l_chunk);
    if l_next<>l_offset+utl_raw.length(l_chunk) then
      raise_application_error(-20002,'table pack load offset mismatch');
    end if;
    l_offset:=l_next;
  end loop;
  l_started:=systimestamp;l_state:=doom_teavm_sim_initialize;
  l_ms:=elapsed_ms(systimestamp-l_started);
  dbms_output.put_line('PMLE_TEAVM_TICKER_INIT|iwad_bytes='||l_iwad_length||
    '|wall_ms='||round(l_ms,3)||'|'||l_state);
  for i in 1..c_warmup loop
    l_next:=doom_teavm_sim_step_bare(
      case when mod(i,20)<14 then 25 else 0 end,
      case when mod(i,31)<3 then 8 else 0 end,
      case when mod(i,17)<5 then 320 else 0 end,
      case when mod(i,23)=0 then 1 else 0 end);
  end loop;
  l_run_started:=systimestamp;
  for i in 1..c_samples loop
    l_started:=systimestamp;
    l_next:=doom_teavm_sim_step_bare(
      case when mod(i,20)<14 then 25 else 0 end,
      case when mod(i,31)<3 then 8 else 0 end,
      case when mod(i,17)<5 then 320 else 0 end,
      case when mod(i,23)=0 then 1 else 0 end);
    l_samples(i):=elapsed_ms(systimestamp-l_started);
    if l_samples(i)>c_slot_ms then l_over_slot:=l_over_slot+1;end if;
    l_backlog:=greatest(0,l_backlog+l_samples(i)-c_slot_ms);
    l_backlogs(i):=l_backlog;
    l_max_backlog:=greatest(l_max_backlog,l_backlog);
  end loop;
  l_total_ms:=elapsed_ms(systimestamp-l_run_started);
  l_state:=doom_teavm_sim_state;
  for i in 2..c_samples loop
    l_value:=l_samples(i);l_j:=i-1;
    while l_j>=1 and l_samples(l_j)>l_value loop
      l_samples(l_j+1):=l_samples(l_j);l_j:=l_j-1;
    end loop;
    l_samples(l_j+1):=l_value;
  end loop;
  for i in 2..c_samples loop
    l_value:=l_backlogs(i);l_j:=i-1;
    while l_j>=1 and l_backlogs(l_j)>l_value loop
      l_backlogs(l_j+1):=l_backlogs(l_j);l_j:=l_j-1;
    end loop;
    l_backlogs(l_j+1):=l_value;
  end loop;
  dbms_output.put_line('PMLE_TEAVM_TICKER_BARE|warmup='||c_warmup||
    '|samples='||c_samples||'|p50_ms='||round(l_samples(1500),3)||
    '|p95_ms='||round(l_samples(2850),3)||
    '|p99_ms='||round(l_samples(2970),3)||
    '|max_ms='||round(l_samples(3000),3)||
    '|throughput_tps='||round(c_samples*1000/l_total_ms,3)||
    '|over_slot='||l_over_slot||
    '|backlog_p99_ms='||round(l_backlogs(2970),3)||
    '|backlog_max_ms='||round(l_max_backlog,3)||
    '|backlog_end_ms='||round(l_backlog,3)||'|'||l_state);
  dbms_output.put_line('PMLE_TEAVM_MEMORY|'||doom_teavm_sim_memory);
end;
/
