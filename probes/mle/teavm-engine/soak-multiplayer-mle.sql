whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_players constant pls_integer:=4;
  c_warmup_seconds constant number:=300;
  c_duration_seconds constant number:=1800;
  c_slot_ms constant number:=1000/35;
  c_slow_call_ms constant number:=100;
  c_tail_window_seconds constant number:=300;
  type histogram_t is table of pls_integer index by pls_integer;
  type slow_number_t is table of number index by pls_integer;
  type slow_time_t is table of timestamp with time zone index by pls_integer;
  l_early_hist histogram_t;l_late_hist histogram_t;
  l_slow_tic slow_number_t;l_slow_ms slow_number_t;
  l_slow_started slow_time_t;l_slow_ended slow_time_t;
  l_wad blob;l_pack blob;l_chunk raw(32767);l_commands raw(32);
  l_length pls_integer;l_iwad_length pls_integer;l_offset pls_integer;l_next number;
  l_hex varchar2(64);l_state varchar2(32767);l_tic pls_integer:=0;
  l_engine_tic pls_integer:=0;l_warmup_tics pls_integer:=0;
  l_started timestamp with time zone;l_step_started timestamp with time zone;
  l_step_ended timestamp with time zone;l_elapsed_ms number;l_step_ms number;
  l_max_step_ms number:=0;l_over_slot pls_integer:=0;l_backlog number:=0;
  l_max_backlog number:=0;
  l_early_count pls_integer:=0;l_late_count pls_integer:=0;
  l_slow_count pls_integer:=0;
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
  procedure observe(p_hist in out nocopy histogram_t,p_count in out pls_integer,
      p_value number) is l_bucket pls_integer;
  begin
    l_bucket:=least(10000,greatest(0,floor(p_value*10)));
    p_hist(l_bucket):=case when p_hist.exists(l_bucket) then p_hist(l_bucket)+1 else 1 end;
    p_count:=p_count+1;
  end;
  function percentile99(p_hist histogram_t,p_count pls_integer)return number is
    l_target pls_integer:=ceil(p_count*.99);l_seen pls_integer:=0;l_bucket pls_integer;
  begin
    if p_count=0 then return null;end if;l_bucket:=p_hist.first;
    while l_bucket is not null loop
      l_seen:=l_seen+p_hist(l_bucket);
      if l_seen>=l_target then return l_bucket/10;end if;
      l_bucket:=p_hist.next(l_bucket);
    end loop;
    return 1000;
  end;
begin
  dbms_application_info.set_module('DOOM_MLE_SOAK','INITIALIZE');
  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);l_iwad_length:=l_length;
  l_next:=doom_teavm_sim_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_next:=doom_teavm_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_pack);
  l_next:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
    l_next:=doom_teavm_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_state:=doom_teavm_sim_multi_init(c_players);
  if c_warmup_seconds>0 then
    dbms_application_info.set_action('WARMUP');l_started:=systimestamp;
    loop
      l_engine_tic:=l_engine_tic+1;l_commands:=commands(l_engine_tic);
      l_next:=doom_teavm_sim_multi_step(c_players,l_commands);
      if l_next<>l_engine_tic then raise_application_error(-20794,
        'warmup tic mismatch expected='||l_engine_tic||' actual='||l_next);end if;
      l_warmup_tics:=l_warmup_tics+1;
      exit when elapsed_ms(systimestamp-l_started)>=c_warmup_seconds*1000;
    end loop;
  end if;
  dbms_application_info.set_action('TICKER');l_started:=systimestamp;
  loop
    l_tic:=l_tic+1;l_engine_tic:=l_engine_tic+1;
    l_commands:=commands(l_engine_tic);l_step_started:=systimestamp;
    l_next:=doom_teavm_sim_multi_step(c_players,l_commands);
    if l_next<>l_engine_tic then raise_application_error(-20794,
      'soak tic mismatch expected='||l_engine_tic||' actual='||l_next);end if;
    l_step_ended:=systimestamp;l_step_ms:=elapsed_ms(l_step_ended-l_step_started);
    l_elapsed_ms:=elapsed_ms(l_step_ended-l_started);
    if l_step_ms>c_slow_call_ms then
      l_slow_count:=l_slow_count+1;l_slow_tic(l_slow_count):=l_tic;
      l_slow_ms(l_slow_count):=l_step_ms;
      l_slow_started(l_slow_count):=l_step_started;
      l_slow_ended(l_slow_count):=l_step_ended;
    end if;
    if l_elapsed_ms<=least(c_tail_window_seconds,c_duration_seconds)*1000 then
      observe(l_early_hist,l_early_count,l_step_ms);end if;
    if l_elapsed_ms>=greatest(0,c_duration_seconds-c_tail_window_seconds)*1000 then
      observe(l_late_hist,l_late_count,l_step_ms);end if;
    l_max_step_ms:=greatest(l_max_step_ms,l_step_ms);
    if l_step_ms>c_slot_ms then l_over_slot:=l_over_slot+1;end if;
    l_backlog:=greatest(0,l_backlog+l_step_ms-c_slot_ms);
    l_max_backlog:=greatest(l_max_backlog,l_backlog);
    exit when l_elapsed_ms>=c_duration_seconds*1000;
  end loop;
  dbms_output.put_line('PMLE_TEAVM_MULTI_SOAK|PASS|players='||c_players||
    '|warmup_s='||c_warmup_seconds||'|warmup_tics='||l_warmup_tics||
    '|duration_s='||round(l_elapsed_ms/1000,3)||'|tics='||l_tic||
    '|throughput_tps='||round(l_tic*1000/l_elapsed_ms,3)||
    '|early_samples='||l_early_count||'|early_p99_ms='||percentile99(l_early_hist,l_early_count)||
    '|late_samples='||l_late_count||'|late_p99_ms='||percentile99(l_late_hist,l_late_count)||
    '|over_slot='||l_over_slot||'|max_step_ms='||round(l_max_step_ms,3)||
    '|backlog_max_ms='||round(l_max_backlog,3)||
    '|backlog_end_ms='||round(l_backlog,3));
  if l_slow_count>0 then
    for i in 1..l_slow_count loop
      dbms_output.put_line('PMLE_TEAVM_MULTI_SOAK_SLOW|tic='||l_slow_tic(i)||
        '|started_utc='||to_char(sys_extract_utc(l_slow_started(i)),
          'YYYY-MM-DD"T"HH24:MI:SS.FF6')||'Z'||
        '|ended_utc='||to_char(sys_extract_utc(l_slow_ended(i)),
          'YYYY-MM-DD"T"HH24:MI:SS.FF6')||'Z'||
        '|elapsed_ms='||round(l_slow_ms(i),3));
    end loop;
  end if;
  dbms_output.put_line('PMLE_TEAVM_MULTI_SOAK_MEMORY|'||doom_teavm_sim_memory);
  doom_teavm_sim_release;dbms_application_info.set_module(null,null);
exception when others then
  dbms_application_info.set_action('FAILED');
  begin doom_teavm_sim_release;exception when others then null;end;raise;
end;
/
