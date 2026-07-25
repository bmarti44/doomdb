whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off linesize 32767 trimspool on serveroutput on size unlimited

declare
  c_stream constant varchar2(64):='live-dm-2026-07-23';
  c_parity_tics constant pls_integer:=100;
  c_rank_tics constant pls_integer:=5250;
  type values_t is table of number index by pls_integer;
  type text_values_t is table of varchar2(4000) index by pls_integer;
  l_samples values_t;l_sorted values_t;l_windows values_t;
  l_window_memory text_values_t;
  l_wad blob;l_pack blob;l_canonical blob;l_chunk raw(32767);
  l_length pls_integer;l_offset pls_integer;l_loaded number;
  l_started timestamp with time zone;l_total_started timestamp with time zone;
  l_window_started timestamp with time zone;
  l_elapsed number;l_total_ms number;l_value number;
  l_count pls_integer:=0;l_window_count pls_integer:=0;l_j pls_integer;
  l_tic number;l_canonical_sha varchar2(64);

  function elapsed_ms(p_value interval day to second)return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+
      extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
  end;

  procedure load_game is
  begin
    doom_wasm2js_rank_release;
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    l_length:=dbms_lob.getlength(l_wad);
    l_loaded:=doom_wasm2js_rank_iwad_allocate(l_length);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_wad,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_wasm2js_rank_iwad_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    if l_loaded<>l_length then
      raise_application_error(-20796,'wasm2js IWAD load incomplete');
    end if;
    select table_pack_blob into l_pack from doom_teavm_sim_source;
    l_length:=dbms_lob.getlength(l_pack);
    l_loaded:=doom_wasm2js_rank_table_allocate(l_length);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        l_pack,least(32767,l_length-l_offset),l_offset+1);
      l_loaded:=doom_wasm2js_rank_table_load(l_offset,l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    if l_loaded<>l_length then
      raise_application_error(-20796,'wasm2js table-pack load incomplete');
    end if;
    if doom_wasm2js_rank_init(2,1,3,1,1)<>0 then
      raise_application_error(-20796,'wasm2js initialization frontier');
    end if;
    l_wad:=null;l_pack:=null;l_chunk:=null;
  end;

  procedure parity_100 is
  begin
    load_game;
    l_count:=0;
    for command_ in (
      select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
        command_vector
      from doom_mle_perf_vector
      where stream_name=c_stream and tic between 1 and c_parity_tics
      order by tic
    ) loop
      l_count:=l_count+1;
      l_tic:=doom_wasm2js_rank_step(
        2,command_.membership,command_.command_vector);
      if command_.tic<>l_count or l_tic<>l_count then
        raise_application_error(-20796,'wasm2js parity frontier mismatch');
      end if;
    end loop;
    if l_count<>c_parity_tics then
      raise_application_error(-20796,'wasm2js parity corpus incomplete');
    end if;
    l_length:=doom_wasm2js_rank_canonical_length;
    dbms_lob.createtemporary(l_canonical,true,dbms_lob.call);
    l_offset:=0;
    while l_offset<l_length loop
      l_chunk:=doom_wasm2js_rank_canonical_chunk(
        l_offset,least(32767,l_length-l_offset));
      if utl_raw.length(l_chunk)<>least(32767,l_length-l_offset) then
        raise_application_error(
          -20796,'wasm2js canonical chunk short at '||l_offset);
      end if;
      dbms_lob.writeappend(
        l_canonical,utl_raw.length(l_chunk),l_chunk);
      l_offset:=l_offset+utl_raw.length(l_chunk);
    end loop;
    if l_offset<>l_length then
      raise_application_error(-20796,'wasm2js canonical load incomplete');
    end if;
    l_canonical_sha:=lower(rawtohex(
      dbms_crypto.hash(l_canonical,dbms_crypto.hash_sh256)));
    dbms_output.put_line(
      'PMLE_WASM2JS_MLE_PARITY|PASS|tics='||c_parity_tics||
      '|canonical_bytes='||l_length||
      '|canonical_sha256='||l_canonical_sha);
    dbms_lob.freetemporary(l_canonical);
    l_canonical:=null;l_chunk:=null;
  end;
begin
  select count(*) into l_count from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and c_rank_tics;
  if l_count<>c_rank_tics then
    raise_application_error(-20796,'wasm2js exact rank corpus incomplete');
  end if;
  if doom_wasm2js_rank_lowering<>
      'i64=exact|values=15,15,23,7,15,15' then
    raise_application_error(-20796,'wasm2js lowering changed before rank');
  end if;

  parity_100;
  load_game;
  l_count:=0;l_window_count:=0;
  l_total_started:=systimestamp;l_window_started:=l_total_started;
  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector
    from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and c_rank_tics
    order by tic
  ) loop
    l_started:=systimestamp;
    l_tic:=doom_wasm2js_rank_step(
      2,command_.membership,command_.command_vector);
    l_elapsed:=elapsed_ms(systimestamp-l_started);
    l_count:=l_count+1;
    l_samples(l_count):=l_elapsed;l_sorted(l_count):=l_elapsed;
    if command_.tic<>l_count or l_tic<>l_count then
      raise_application_error(-20796,'wasm2js rank frontier mismatch');
    end if;
    if mod(l_count,100)=0 then
      l_window_count:=l_window_count+1;
      l_windows(l_window_count):=elapsed_ms(systimestamp-l_window_started);
      l_window_memory(l_window_count):=doom_wasm2js_rank_memory;
      l_window_started:=systimestamp;
    end if;
  end loop;
  if mod(l_count,100)<>0 then
    l_window_count:=l_window_count+1;
    l_windows(l_window_count):=elapsed_ms(systimestamp-l_window_started);
    l_window_memory(l_window_count):=doom_wasm2js_rank_memory;
  end if;
  l_total_ms:=elapsed_ms(systimestamp-l_total_started);

  for i in 1..l_count loop
    dbms_output.put_line('PMLE_WASM2JS_MLE_TIC|tic='||i||
      '|mle_ms='||round(l_samples(i),3));
  end loop;
  for i in 2..l_count loop
    l_value:=l_sorted(i);l_j:=i-1;
    while l_j>=1 and l_sorted(l_j)>l_value loop
      l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
    end loop;
    l_sorted(l_j+1):=l_value;
  end loop;
  dbms_output.put_line(
    'PMLE_WASM2JS_MLE_RANK|PASS|stream='||c_stream||
    '|tics='||l_count||
    '|p50_ms='||round(l_sorted(ceil(l_count*.50)),3)||
    '|p95_ms='||round(l_sorted(ceil(l_count*.95)),3)||
    '|p99_ms='||round(l_sorted(ceil(l_count*.99)),3)||
    '|max_ms='||round(l_sorted(l_count),3)||
    '|throughput_tps='||round(l_count*1000/l_total_ms,3));
  for i in 1..l_window_count loop
    dbms_output.put_line(
      'PMLE_WASM2JS_MLE_WINDOW|through_tic='||
      least(i*100,l_count)||'|tics='||
      case when i<l_window_count or mod(l_count,100)=0
        then 100 else mod(l_count,100) end||
      '|wall_ms='||round(l_windows(i),3)||
      '|memory='||l_window_memory(i));
  end loop;
  doom_wasm2js_rank_release;
exception when others then
  if dbms_lob.istemporary(l_canonical)=1 then
    dbms_lob.freetemporary(l_canonical);
  end if;
  begin doom_wasm2js_rank_release;exception when others then null;end;
  raise;
end;
/
