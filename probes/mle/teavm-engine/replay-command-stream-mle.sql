whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
declare
  c_stream constant varchar2(64):='__STREAM_NAME__';
  c_deathmatch constant pls_integer:=__DEATHMATCH__;
  c_limit constant pls_integer:=__TIC_LIMIT__;
  type values_t is table of number index by pls_integer;
  type text_values_t is table of varchar2(4000) index by pls_integer;
  l_samples values_t;l_sorted values_t;l_windows values_t;
  l_window_memory text_values_t;
  l_wad blob;l_pack blob;l_origin blob;l_chunk raw(32767);l_length pls_integer;
  l_offset pls_integer;l_loaded number;l_state varchar2(32767);
  l_started timestamp with time zone;l_total_started timestamp with time zone;
  l_total_ms number;l_elapsed number;l_count pls_integer:=0;
  l_window_started timestamp with time zone;l_window_count pls_integer:=0;
  l_value number;l_j pls_integer;l_tic number;

  function elapsed_ms(p_value interval day to second)return number is
  begin
    return extract(day from p_value)*86400000+
      extract(hour from p_value)*3600000+
      extract(minute from p_value)*60000+
      extract(second from p_value)*1000;
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
      raise_application_error(-20796,'warm-prefix origin restore mismatch');
    end if;
  end;

begin
  if not regexp_like(c_stream,'^[a-z0-9][a-z0-9-]{0,63}$') then
    raise_application_error(-20796,'command replay stream name');
  end if;
  select count(*) into l_count from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and c_limit;
  if l_count<100 then
    raise_application_error(-20796,'command replay requires at least 100 tics');
  end if;

  doom_teavm_sim_release;
  select payload_bytes into l_wad from doom_engine_artifact
    where artifact_name='freedoom1.wad';
  l_length:=dbms_lob.getlength(l_wad);
  l_loaded:=doom_teavm_sim_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_wad,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  select table_pack_blob into l_pack from doom_teavm_sim_source;
  l_length:=dbms_lob.getlength(l_pack);
  l_loaded:=doom_teavm_sim_table_allocate(l_length);l_offset:=0;
  while l_offset<l_length loop
    l_chunk:=dbms_lob.substr(l_pack,least(32767,l_length-l_offset),l_offset+1);
    l_loaded:=doom_teavm_sim_table_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  l_started:=systimestamp;
  l_state:=doom_teavm_sim_multi_init_game(2,c_deathmatch,3,1,1);
  dbms_output.put_line('PMLE_LIVE_REPLAY_INIT|stream='||c_stream||
    '|wall_ms='||round(elapsed_ms(systimestamp-l_started),3));
  capture_origin;

  l_count:=0;l_total_started:=systimestamp;l_window_started:=l_total_started;
  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector
    from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and c_limit
    order by tic
  ) loop
    if command_.tic<>l_count+1 then
      raise_application_error(-20796,'command replay tic gap');
    end if;
    l_started:=systimestamp;
    l_tic:=doom_teavm_sim_authority_step(
      2,command_.membership,command_.command_vector);
    l_elapsed:=elapsed_ms(systimestamp-l_started);
    l_count:=l_count+1;l_samples(l_count):=l_elapsed;l_sorted(l_count):=l_elapsed;
    if l_tic<>command_.tic then
      raise_application_error(-20796,'command replay frontier mismatch');
    end if;
    if mod(l_count,100)=0 then
      l_window_count:=l_window_count+1;
      l_windows(l_window_count):=elapsed_ms(systimestamp-l_window_started);
      l_window_memory(l_window_count):=doom_teavm_sim_memory;
      l_window_started:=systimestamp;
    end if;
  end loop;
  if mod(l_count,100)<>0 then
    l_window_count:=l_window_count+1;
    l_windows(l_window_count):=elapsed_ms(systimestamp-l_window_started);
    l_window_memory(l_window_count):=doom_teavm_sim_memory;
  end if;
  l_total_ms:=elapsed_ms(systimestamp-l_total_started);
  -- Emit only after the measured loop so DBMS_OUTPUT formatting cannot alter
  -- the per-tic wall-clock samples being compared with the live worker.
  for i in 1..l_count loop
    dbms_output.put_line('PMLE_LIVE_REPLAY_TIC|tic='||i||
      '|mle_ms='||round(l_samples(i),3));
  end loop;

  for i in 2..l_count loop
    l_value:=l_sorted(i);l_j:=i-1;
    while l_j>=1 and l_sorted(l_j)>l_value loop
      l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
    end loop;
    l_sorted(l_j+1):=l_value;
  end loop;
  dbms_output.put_line('PMLE_LIVE_REPLAY_TICKER|stream='||c_stream||
    '|tics='||l_count||
    '|p50_ms='||round(l_sorted(ceil(l_count*.50)),3)||
    '|p95_ms='||round(l_sorted(ceil(l_count*.95)),3)||
    '|p99_ms='||round(l_sorted(ceil(l_count*.99)),3)||
    '|max_ms='||round(l_sorted(l_count),3)||
    '|throughput_tps='||round(l_count*1000/l_total_ms,3));
  for i in 1..l_window_count loop
    dbms_output.put_line('PMLE_LIVE_REPLAY_WINDOW|through_tic='||
      least(i*100,l_count)||'|tics='||
      case when i<l_window_count or mod(l_count,100)=0
        then 100 else mod(l_count,100) end||
      '|wall_ms='||round(l_windows(i),3)||
      '|memory='||l_window_memory(i));
  end loop;
  dbms_output.put_line('PMLE_LIVE_REPLAY_MEMORY|'||doom_teavm_sim_memory);
  restore_origin;
  l_count:=0;l_total_started:=systimestamp;
  for command_ in (
    select tic,to_number(rawtohex(membership_bitmap),'XX') membership,
      command_vector
    from doom_mle_perf_vector
    where stream_name=c_stream and tic between 1 and 500
    order by tic
  ) loop
    l_started:=systimestamp;
    l_tic:=doom_teavm_sim_authority_step(
      2,command_.membership,command_.command_vector);
    l_elapsed:=elapsed_ms(systimestamp-l_started);
    l_count:=l_count+1;l_sorted(l_count):=l_elapsed;
    if l_tic<>command_.tic then
      raise_application_error(-20796,'warm-prefix frontier mismatch');
    end if;
  end loop;
  l_total_ms:=elapsed_ms(systimestamp-l_total_started);
  for i in 2..l_count loop
    l_value:=l_sorted(i);l_j:=i-1;
    while l_j>=1 and l_sorted(l_j)>l_value loop
      l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
    end loop;
    l_sorted(l_j+1):=l_value;
  end loop;
  dbms_output.put_line('PMLE_LIVE_REPLAY_WARM_PREFIX|after_full_tics='||
    c_limit||'|tics='||l_count||
    '|p50_ms='||round(l_sorted(ceil(l_count*.50)),3)||
    '|p95_ms='||round(l_sorted(ceil(l_count*.95)),3)||
    '|p99_ms='||round(l_sorted(ceil(l_count*.99)),3)||
    '|max_ms='||round(l_sorted(l_count),3)||
    '|throughput_tps='||round(l_count*1000/l_total_ms,3));
  if dbms_lob.istemporary(l_origin)=1 then dbms_lob.freetemporary(l_origin);end if;
  doom_teavm_sim_release;
exception when others then
  if dbms_lob.istemporary(l_origin)=1 then dbms_lob.freetemporary(l_origin);end if;
  begin doom_teavm_sim_release;exception when others then null;end;
  raise;
end;
/
