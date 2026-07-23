whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_players constant pls_integer:=4;c_warmup constant pls_integer:=30;
  c_samples constant pls_integer:=3000;c_slot_ms constant number:=1000/35;
  type values_t is table of number index by pls_integer;
  l_samples values_t;l_backlogs values_t;l_wad blob;l_pack blob;l_chunk raw(32767);
  l_length pls_integer;l_iwad_length pls_integer;l_offset pls_integer;l_next number;
  l_hex varchar2(64);l_commands raw(32);l_state varchar2(32767);
  l_started timestamp;l_run_started timestamp;l_total_ms number;
  l_backlog number:=0;l_max_backlog number:=0;l_over_slot pls_integer:=0;
  l_value number;l_j pls_integer;
  function elapsed_ms(p_value interval day to second)return number is
  begin return extract(day from p_value)*86400000+
    extract(hour from p_value)*3600000+extract(minute from p_value)*60000+
    extract(second from p_value)*1000;end;
  function commands(p_tic number)return raw is
  begin
    l_hex:=
      (case when mod(p_tic,5)=0 then '19' else '00' end)||'000000000000'||
        (case when mod(p_tic,23)=0 then '01' else '00' end)||
      '00'||(case when mod(p_tic,7)=0 then 'E8' else '00' end)||'000000000000'||
      '0000'||(case when mod(p_tic,11)=0 then 'FD80' else '0000' end)||'00000000'||
      (case when mod(p_tic,13)=0 then 'F0' else '00' end)||'00000000000000';
    return hextoraw(l_hex);
  end;
begin
  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);l_iwad_length:=l_length;
  l_next:=doom_teavm_sim_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_next:=doom_teavm_sim_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_pack);l_next:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
    l_next:=doom_teavm_sim_table_load(l_offset,l_chunk);l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_started:=systimestamp;l_state:=doom_teavm_sim_multi_init(c_players);
  dbms_output.put_line('PMLE_TEAVM_MULTI_INIT|players='||c_players||
    '|iwad_bytes='||l_iwad_length||'|wall_ms='||round(elapsed_ms(systimestamp-l_started),3));
  for i in 1..c_warmup loop
    l_commands:=commands(i);l_next:=doom_teavm_sim_multi_step(c_players,l_commands);
  end loop;
  l_run_started:=systimestamp;
  for i in 1..c_samples loop
    l_commands:=commands(i);l_started:=systimestamp;
    l_next:=doom_teavm_sim_multi_step(c_players,l_commands);
    l_samples(i):=elapsed_ms(systimestamp-l_started);
    if l_samples(i)>c_slot_ms then l_over_slot:=l_over_slot+1;end if;
    l_backlog:=greatest(0,l_backlog+l_samples(i)-c_slot_ms);
    l_backlogs(i):=l_backlog;l_max_backlog:=greatest(l_max_backlog,l_backlog);
  end loop;
  l_total_ms:=elapsed_ms(systimestamp-l_run_started);
  for i in 2..c_samples loop
    l_value:=l_samples(i);l_j:=i-1;
    while l_j>=1 and l_samples(l_j)>l_value loop
      l_samples(l_j+1):=l_samples(l_j);l_j:=l_j-1;end loop;
    l_samples(l_j+1):=l_value;
  end loop;
  for i in 2..c_samples loop
    l_value:=l_backlogs(i);l_j:=i-1;
    while l_j>=1 and l_backlogs(l_j)>l_value loop
      l_backlogs(l_j+1):=l_backlogs(l_j);l_j:=l_j-1;end loop;
    l_backlogs(l_j+1):=l_value;
  end loop;
  dbms_output.put_line('PMLE_TEAVM_MULTI_TICKER|players='||c_players||
    '|warmup='||c_warmup||'|samples='||c_samples||
    '|p50_ms='||round(l_samples(1500),3)||'|p95_ms='||round(l_samples(2850),3)||
    '|p99_ms='||round(l_samples(2970),3)||'|max_ms='||round(l_samples(3000),3)||
    '|throughput_tps='||round(c_samples*1000/l_total_ms,3)||
    '|over_slot='||l_over_slot||'|backlog_p99_ms='||round(l_backlogs(2970),3)||
    '|backlog_max_ms='||round(l_max_backlog,3)||'|backlog_end_ms='||round(l_backlog,3));
  dbms_output.put_line('PMLE_TEAVM_MULTI_MEMORY|'||doom_teavm_sim_memory);
  doom_teavm_sim_release;
exception when others then begin doom_teavm_sim_release;exception when others then null;end;raise;
end;
/
