whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  l_pack blob;l_bytes number;l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select pack_blob,pack_bytes into l_pack,l_bytes
    from doom_free_generated_source;
  l_loaded:=doom_free_gen_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_pack,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if doom_free_gen_finalize<>l_bytes then
    raise_application_error(-20796,'pixel tape geometry finalize mismatch');
  end if;
end;
/

declare
  l_blob blob;l_bytes number;l_expected_sha varchar2(64);
  l_actual_sha varchar2(64);l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select encoded_bytes,dbms_lob.getlength(encoded_bytes),payload_sha256
    into l_blob,l_bytes,l_expected_sha
    from doom_renderer_asset_pack where asset_kind='wall_texture';
  l_actual_sha:=lower(rawtohex(
    dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));
  if l_actual_sha<>l_expected_sha then
    raise_application_error(-20796,'pixel tape texture hash mismatch');
  end if;
  l_loaded:=doom_free_gen_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if doom_free_gen_texture_finalize<>l_bytes then
    raise_application_error(-20796,'pixel tape texture finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_PIXEL_TAPE_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  type poses_t is table of pls_integer;
  l_poses poses_t:=poses_t(500,750,999);
  l_reference0 raw(32000);l_reference1 raw(32000);
  l_decoded0 raw(32000);l_decoded1 raw(32000);
  l_value number;l_tape number;l_commands number;l_misses number;
  procedure decode_frame(p_pose pls_integer) is
    l_offset pls_integer:=16;l_chunk_bytes pls_integer;l_chunk raw(32767);
  begin
    l_tape:=doom_free_gen_native_tape(p_pose);
    doom_free_native_overlay.begin_frame;
    while l_offset<l_tape loop
      l_chunk_bytes:=doom_free_gen_native_record_length(l_offset,32000);
      l_chunk:=doom_free_gen_native_chunk(l_offset,l_chunk_bytes);
      doom_free_native_overlay.consume_records(l_chunk);
      l_offset:=l_offset+l_chunk_bytes;
    end loop;
    doom_free_native_overlay.finish_frame(
      l_decoded0,l_decoded1,l_commands,l_misses);
  end;
begin
  if doom_free_gen_native_reset<>262144 then
    raise_application_error(-20796,'pixel tape generated reset mismatch');
  end if;
  doom_free_native_overlay.reset_cache;
  for item in 1..l_poses.count loop
    l_value:=doom_free_gen_frame(l_poses(item));
    l_reference0:=doom_free_gen_frame_chunk(0,32000);
    l_reference1:=doom_free_gen_frame_chunk(32000,32000);
    decode_frame(l_poses(item));
    if l_reference0<>l_decoded0 or l_reference1<>l_decoded1 then
      raise_application_error(
        -20796,'pixel tape frame mismatch at pose '||l_poses(item));
    end if;
    dbms_output.put_line(
      'PMLE_FREE_PIXEL_TAPE_EQUIVALENCE|PASS|pose='||l_poses(item)||
      '|frame_bytes=64000|tape_bytes='||l_tape||
      '|commands='||l_commands||'|misses='||l_misses);
  end loop;
end;
/

declare
  c_passes constant pls_integer:=6;
  c_frames constant pls_integer:=500;
  c_start constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_time values_t;l_sorted_time values_t;
  l_bytes values_t;l_sorted_bytes values_t;
  l_misses values_t;l_sorted_misses values_t;
  l_started timestamp with time zone;l_pass_started timestamp with time zone;
  l_clock_started number;l_wall number;l_clock number;l_value number;
  l_checksum number:=0;l_j pls_integer;l_suspects number;
  l_tape number;l_commands number;l_miss number;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
  procedure sort_values(p_values in out nocopy values_t) is
    l_sort number;l_at pls_integer;
  begin
    for index_ in 2..c_frames loop
      l_sort:=p_values(index_);l_at:=index_-1;
      while l_at>=1 and p_values(l_at)>l_sort loop
        p_values(l_at+1):=p_values(l_at);l_at:=l_at-1;
      end loop;
      p_values(l_at+1):=l_sort;
    end loop;
  end;
begin
  if doom_free_gen_native_reset<>262144 then
    raise_application_error(-20796,'pixel tape timed reset mismatch');
  end if;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame_ in 1..c_frames loop
      l_started:=systimestamp;
      l_tape:=doom_free_gen_native_tape(c_start+frame_-1);
      declare
        l_offset pls_integer:=0;l_length pls_integer;l_chunk raw(16000);
        l_consumed pls_integer:=0;
      begin
        while l_offset<l_tape loop
          l_length:=least(16000,l_tape-l_offset);
          l_chunk:=doom_free_gen_native_chunk(l_offset,l_length);
          l_consumed:=l_consumed+utl_raw.length(l_chunk);
          l_offset:=l_offset+l_length;
        end loop;
        if l_consumed<>l_tape then
          raise_application_error(-20796,'pixel tape egress mismatch');
        end if;
      end;
      l_commands:=doom_free_gen_native_commands;
      l_miss:=doom_free_gen_native_misses;
      l_time(frame_):=elapsed_ms(systimestamp-l_started);
      l_bytes(frame_):=l_tape;
      l_misses(frame_):=l_miss;
      l_sorted_time(frame_):=l_time(frame_);
      l_sorted_bytes(frame_):=l_bytes(frame_);
      l_sorted_misses(frame_):=l_misses(frame_);
      l_checksum:=l_checksum+l_tape+l_commands+l_miss;
    end loop;
    l_wall:=elapsed_ms(systimestamp-l_pass_started);
    l_clock:=(dbms_utility.get_time-l_clock_started)*10;
    l_suspects:=case when abs(l_wall-l_clock)>30 then 1 else 0 end;
    sort_values(l_sorted_time);
    sort_values(l_sorted_bytes);
    sort_values(l_sorted_misses);
    dbms_output.put_line(
      'PMLE_FREE_PIXEL_TAPE_PASS|PASS|pass='||pass||
      '|cache='||case when pass=1 then 'COLD_ROUTE' else 'REPLAY_WARM' end||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted_time(250),3)||
      '|p95_ms='||round(l_sorted_time(475),3)||
      '|tape_p50_bytes='||l_sorted_bytes(250)||
      '|tape_p95_bytes='||l_sorted_bytes(475)||
      '|miss_p50='||l_sorted_misses(250)||
      '|miss_p95='||l_sorted_misses(475)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|checksum='||l_checksum);
  end loop;
end;
/
