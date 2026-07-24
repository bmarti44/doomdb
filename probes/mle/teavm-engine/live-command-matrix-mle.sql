whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_stream constant varchar2(64):='__STREAM_NAME__';
  c_samples constant pls_integer:=500;
  c_warmup constant pls_integer:=500;
  type raw_table is table of raw(32767) index by pls_integer;
  l_cmd32 raw_table;
  l_cmd16 raw_table;
  l_wad blob;l_pack blob;l_origin blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;
  l_state varchar2(32767);l_started timestamp with time zone;

  function elapsed_ms(p_value interval day to second)return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+
      extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
  end;

  procedure load_assets is
  begin
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    l_length:=dbms_lob.getlength(l_wad);
    l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_wad,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    select table_pack_blob into l_pack from doom_teavm_sim_source;
    l_length:=dbms_lob.getlength(l_pack);
    l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_pack,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;

  procedure capture_origin is
  begin
    l_length:=doom_teavm_sim_checkpoint_length;l_offset:=0;
    dbms_lob.createtemporary(l_origin,true,dbms_lob.call);
    while l_offset<l_length loop
      l_chunk:=doom_teavm_sim_checkpoint_chunk(
        l_offset,least(32767,l_length-l_offset));
      dbms_lob.writeappend(l_origin,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
  end;

  procedure restore_origin is
  begin
    l_length:=dbms_lob.getlength(l_origin);
    l_loaded:=doom_teavm_sim_restore_allocate(l_length);l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_origin,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_teavm_sim_restore_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    l_state:=doom_teavm_sim_restore(0);
    if l_state not like 'state=restored|gametic=0|%' then
      raise_application_error(-20796,'matrix origin restore mismatch');
    end if;
  end;

  procedure measure(p_name varchar2,p_authoritative boolean) is
    type values_t is table of number index by pls_integer;
    l_values values_t;l_sorted values_t;
    l_tic number;l_elapsed number;l_total_started timestamp with time zone;
    l_total_ms number;l_value number;l_j pls_integer;
    l_cpu_started number;l_cpu_ms number;
  begin
    l_cpu_started:=dbms_utility.get_cpu_time;l_total_started:=systimestamp;
    for i in 1..c_samples loop
      l_started:=systimestamp;
      if p_authoritative then
        l_tic:=doom_teavm_sim_authority_step(2,3,l_cmd32(i));
      else
        l_tic:=doom_teavm_sim_multi_step(2,l_cmd16(i));
      end if;
      l_elapsed:=elapsed_ms(systimestamp-l_started);
      l_values(i):=l_elapsed;l_sorted(i):=l_elapsed;
      if l_tic<>i then
        raise_application_error(-20796,'matrix frontier mismatch');
      end if;
    end loop;
    l_total_ms:=elapsed_ms(systimestamp-l_total_started);
    l_cpu_ms:=(dbms_utility.get_cpu_time-l_cpu_started)*10;
    for i in 2..c_samples loop
      l_value:=l_sorted(i);l_j:=i-1;
      while l_j>=1 and l_sorted(l_j)>l_value loop
        l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
      end loop;
      l_sorted(l_j+1):=l_value;
    end loop;
    dbms_output.put_line('PMLE_LIVE_MATRIX|scenario='||p_name||
      '|tics='||c_samples||
      '|p50_ms='||round(l_sorted(ceil(c_samples*.50)),3)||
      '|p95_ms='||round(l_sorted(ceil(c_samples*.95)),3)||
      '|p99_ms='||round(l_sorted(ceil(c_samples*.99)),3)||
      '|max_ms='||round(l_sorted(c_samples),3)||
      '|throughput_tps='||round(c_samples*1000/l_total_ms,3)||
      '|session_cpu_ms='||round(l_cpu_ms,3)||
      '|session_cpu_ms_per_tic='||round(l_cpu_ms/c_samples,3));
  end;
begin
  if not regexp_like(c_stream,'^[a-z0-9][a-z0-9-]{0,63}$') then
    raise_application_error(-20796,'matrix stream name');
  end if;
  for command_ in (
    select tic,command_vector from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and c_samples order by tic
  ) loop
    if command_.tic<>l_cmd32.count+1 or
       utl_raw.length(command_.command_vector)<>32 then
      raise_application_error(-20796,'matrix command stream mismatch');
    end if;
    l_cmd32(command_.tic):=command_.command_vector;
    l_cmd16(command_.tic):=utl_raw.substr(command_.command_vector,1,16);
  end loop;
  if l_cmd32.count<>c_samples then
    raise_application_error(-20796,'matrix command stream too short');
  end if;

  doom_teavm_sim_release;
  load_assets;
  l_started:=systimestamp;
  l_state:=doom_teavm_sim_multi_init_game(2,1,3,1,1);
  dbms_output.put_line('PMLE_LIVE_MATRIX_INIT|mode=DEATHMATCH|players=2'||
    '|wall_ms='||round(elapsed_ms(systimestamp-l_started),3));
  capture_origin;
  l_started:=systimestamp;
  for i in 1..c_warmup loop
    l_loaded:=doom_teavm_sim_authority_step(2,3,l_cmd32(i));
  end loop;
  dbms_output.put_line('PMLE_LIVE_MATRIX_WARMUP|scenario=DM2_AUTHORITY_EXACT'||
    '|tics='||c_warmup||
    '|wall_ms='||round(elapsed_ms(systimestamp-l_started),3));
  restore_origin;
  measure('DM2_AUTHORITY_EXACT',true);
  restore_origin;
  measure('DM2_BARE_EXACT',false);
  dbms_output.put_line('PMLE_LIVE_MATRIX_MEMORY|'||doom_teavm_sim_memory);
  if dbms_lob.istemporary(l_origin)=1 then dbms_lob.freetemporary(l_origin);end if;
  doom_teavm_sim_release;
exception when others then
  if dbms_lob.istemporary(l_origin)=1 then dbms_lob.freetemporary(l_origin);end if;
  begin doom_teavm_sim_release;exception when others then null;end;
  raise;
end;
/
