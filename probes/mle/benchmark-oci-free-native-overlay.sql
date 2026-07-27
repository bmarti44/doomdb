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
    if l_loaded<>l_offset then
      raise_application_error(-20796,'native overlay pack mismatch');
    end if;
  end loop;
  if doom_free_gen_finalize<>l_bytes then
    raise_application_error(-20796,'native overlay finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_NATIVE_OVERLAY_LOAD|PASS|pack_bytes='||l_bytes);
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
    raise_application_error(-20796,'native overlay texture hash mismatch');
  end if;
  l_loaded:=doom_free_gen_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'native overlay texture load mismatch');
    end if;
  end loop;
  if doom_free_gen_texture_finalize<>l_bytes then
    raise_application_error(-20796,'native overlay texture finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_NATIVE_OVERLAY_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  type poses_t is table of pls_integer;
  l_poses poses_t:=poses_t(0,500,999,2500,5249);
  l_reference0 raw(32000);l_reference1 raw(32000);
  l_native0 raw(32000);l_native1 raw(32000);
  l_value number;l_tape number;l_commands number;l_misses number;

  procedure render_native(
    p_pose pls_integer,
    p_frame0 out raw,
    p_frame1 out raw,
    p_tape_bytes out number,
    p_commands out number,
    p_misses out number) is
    l_offset pls_integer:=16;
    l_chunk_bytes pls_integer;
    l_chunk raw(32767);
  begin
    p_tape_bytes:=doom_free_gen_native_tape(p_pose);
    doom_free_native_overlay.begin_frame;
    while l_offset<p_tape_bytes loop
      l_chunk_bytes:=doom_free_gen_native_record_length(l_offset,32000);
      l_chunk:=doom_free_gen_native_chunk(l_offset,l_chunk_bytes);
      doom_free_native_overlay.consume_records(l_chunk);
      l_offset:=l_offset+l_chunk_bytes;
    end loop;
    if l_offset<>p_tape_bytes then
      raise_application_error(-20796,'native overlay tape boundary mismatch');
    end if;
    doom_free_native_overlay.finish_frame(
      p_frame0,p_frame1,p_commands,p_misses);
  end;
begin
  doom_free_native_overlay.reset_cache;
  for pose in 0..49 loop
    render_native(
      pose,l_native0,l_native1,l_tape,l_commands,l_misses);
  end loop;
  for index_ in 1..l_poses.count loop
    l_value:=doom_free_gen_frame(l_poses(index_));
    l_reference0:=doom_free_gen_frame_chunk(0,32000);
    l_reference1:=doom_free_gen_frame_chunk(32000,32000);
    render_native(
      l_poses(index_),l_native0,l_native1,l_tape,l_commands,l_misses);
    if l_reference0<>l_native0 or l_reference1<>l_native1 then
      raise_application_error(
        -20796,'native overlay frame mismatch at pose '||l_poses(index_));
    end if;
    if l_commands<>doom_free_gen_native_commands
        or l_misses<>doom_free_gen_native_misses then
      raise_application_error(
        -20796,'native overlay counter mismatch at pose '||l_poses(index_));
    end if;
    dbms_output.put_line(
      'PMLE_FREE_NATIVE_OVERLAY_EQUIVALENCE|PASS|pose='||l_poses(index_)||
      '|frame_bytes=64000|tape_bytes='||l_tape||
      '|commands='||l_commands||'|misses='||l_misses);
  end loop;
end;
/

declare
  c_passes constant pls_integer:=12;
  c_frames constant pls_integer:=500;
  c_start constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_values values_t;l_sorted values_t;
  l_started timestamp with time zone;l_pass_started timestamp with time zone;
  l_clock_started number;l_wall number;l_clock number;l_value number;
  l_checksum number:=0;l_j pls_integer;l_suspects number;
  l_frame0 raw(32000);l_frame1 raw(32000);
  l_tape number;l_commands number;l_misses number;

  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;

  procedure render_native(p_pose pls_integer) is
    l_offset pls_integer:=16;
    l_chunk_bytes pls_integer;
    l_chunk raw(32767);
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
      l_frame0,l_frame1,l_commands,l_misses);
  end;
begin
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame_ in 1..c_frames loop
      l_started:=systimestamp;
      render_native(c_start+frame_-1);
      l_values(frame_):=elapsed_ms(systimestamp-l_started);
      l_sorted(frame_):=l_values(frame_);
      l_checksum:=l_checksum+utl_raw.length(l_frame0)
        +utl_raw.length(l_frame1)+l_commands+l_misses;
    end loop;
    l_wall:=elapsed_ms(systimestamp-l_pass_started);
    l_clock:=(dbms_utility.get_time-l_clock_started)*10;
    l_suspects:=case when abs(l_wall-l_clock)>30 then 1 else 0 end;
    for i in 2..c_frames loop
      l_value:=l_sorted(i);l_j:=i-1;
      while l_j>=1 and l_sorted(l_j)>l_value loop
        l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
      end loop;
      l_sorted(l_j+1):=l_value;
    end loop;
    dbms_output.put_line(
      'PMLE_FREE_NATIVE_OVERLAY_PASS|PASS|pass='||pass||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(250),3)||
      '|p95_ms='||round(l_sorted(475),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|last_tape_bytes='||l_tape||
      '|last_commands='||l_commands||
      '|last_misses='||l_misses||
      '|checksum='||l_checksum);
  end loop;
end;
/
