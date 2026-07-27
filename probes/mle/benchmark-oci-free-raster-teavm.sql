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
      raise_application_error(-20796,'small raster geometry pack mismatch');
    end if;
  end loop;
  if doom_free_gen_finalize<>l_bytes then
    raise_application_error(-20796,'small raster geometry finalize mismatch');
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
    raise_application_error(-20796,'small raster texture hash mismatch');
  end if;
  l_loaded:=doom_free_gen_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if doom_free_gen_texture_finalize<>l_bytes then
    raise_application_error(-20796,'small raster texture finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_RASTER_TEXTURE|PASS|encoded_bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  c_frames constant pls_integer:=500;
  c_start constant pls_integer:=500;
  l_pack blob;l_raw raw(32767);l_count number;l_length number;
  l_offset number;l_loaded number;l_atlas_length number;
begin
  l_atlas_length:=doom_free_gen_lit_length;
  l_loaded:=doom_free_raster_atlas_allocate(l_atlas_length);
  l_offset:=0;
  while l_offset<l_atlas_length loop
    l_raw:=doom_free_gen_lit_chunk(
      l_offset,least(16000,l_atlas_length-l_offset));
    l_loaded:=doom_free_raster_atlas_load(l_offset,l_raw);
    l_offset:=l_offset+utl_raw.length(l_raw);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'small raster atlas load mismatch');
    end if;
  end loop;

  dbms_lob.createtemporary(l_pack,true,dbms_lob.call);
  l_raw:=hextoraw('5243503101000000F401000014000000');
  dbms_lob.writeappend(l_pack,utl_raw.length(l_raw),l_raw);
  for frame in 0..c_frames-1 loop
    l_count:=doom_free_gen_resolved(c_start+frame);
    l_raw:=utl_raw.cast_from_binary_integer(l_count,utl_raw.little_endian);
    dbms_lob.writeappend(l_pack,utl_raw.length(l_raw),l_raw);
    l_length:=l_count*20;
    l_offset:=0;
    while l_offset<l_length loop
      l_raw:=doom_free_gen_resolved_chunk(
        l_offset,least(16000,l_length-l_offset));
      dbms_lob.writeappend(l_pack,utl_raw.length(l_raw),l_raw);
      l_offset:=l_offset+utl_raw.length(l_raw);
    end loop;
  end loop;

  l_length:=dbms_lob.getlength(l_pack);
  l_loaded:=doom_free_raster_command_allocate(l_length);
  l_offset:=0;
  while l_offset<l_length loop
    l_raw:=dbms_lob.substr(l_pack,least(16000,l_length-l_offset),l_offset+1);
    l_loaded:=doom_free_raster_command_load(l_offset,l_raw);
    l_offset:=l_offset+utl_raw.length(l_raw);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'small raster command load mismatch');
    end if;
  end loop;
  if doom_free_raster_finalize<>c_frames then
    raise_application_error(-20796,'small raster command finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_RASTER_COMMANDS|PASS|frames='||c_frames||
    '|bytes='||l_length||
    '|atlas_bytes='||l_atlas_length||
    '|first_commands='||doom_free_raster_command_count(0)||
    '|last_commands='||doom_free_raster_command_count(c_frames-1));
  dbms_lob.freetemporary(l_pack);
end;
/

declare
  type indices_t is table of pls_integer;
  l_indices indices_t:=indices_t(0,250,499);
  l_reference raw(32000);l_candidate raw(32000);
begin
  for item in 1..l_indices.count loop
    declare l_index pls_integer:=l_indices(item);l_dummy number;begin
      l_dummy:=doom_free_gen_frame(500+l_index);
      l_dummy:=doom_free_raster_render(l_index);
      for half in 0..1 loop
        l_reference:=doom_free_gen_frame_chunk(half*32000,32000);
        l_candidate:=doom_free_raster_frame_chunk(half*32000,32000);
        if utl_raw.compare(l_reference,l_candidate)<>0 then
          raise_application_error(
            -20796,'small raster frame mismatch at index '||l_index);
        end if;
      end loop;
      dbms_output.put_line(
        'PMLE_FREE_RASTER_EQUIVALENCE|PASS|pose='||(500+l_index)||
        '|commands='||doom_free_raster_command_count(l_index)||
        '|frame_bytes=64000');
    end;
  end loop;
end;
/

declare
  c_passes constant pls_integer:=12;
  c_frames constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_values values_t;l_sorted values_t;
  l_started timestamp with time zone;l_pass_started timestamp with time zone;
  l_clock_started number;l_wall number;l_clock number;l_value number;
  l_checksum number:=0;l_j pls_integer;l_suspects number;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for frame in 0..49 loop
    l_checksum:=l_checksum+doom_free_raster_render(frame);
  end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame in 1..c_frames loop
      l_started:=systimestamp;
      l_checksum:=l_checksum+doom_free_raster_render(frame-1);
      l_values(frame):=elapsed_ms(systimestamp-l_started);
      l_sorted(frame):=l_values(frame);
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
      'PMLE_FREE_RASTER_PASS|PASS|pass='||pass||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(250),3)||
      '|p95_ms='||round(l_sorted(475),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|checksum='||l_checksum);
  end loop;
end;
/

declare
  c_passes constant pls_integer:=12;
  c_frames constant pls_integer:=500;
  l_started timestamp with time zone;l_clock_started number;
  l_wall number;l_clock number;l_checksum number:=0;l_expected number:=0;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for frame in 0..c_frames-1 loop
    l_expected:=l_expected+doom_free_raster_render(frame);
  end loop;
  for pass in 1..c_passes loop
    l_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    l_checksum:=doom_free_raster_batch(0,c_frames);
    l_wall:=elapsed_ms(systimestamp-l_started);
    l_clock:=(dbms_utility.get_time-l_clock_started)*10;
    if l_checksum<>l_expected then
      raise_application_error(-20796,'small raster batch checksum mismatch');
    end if;
    dbms_output.put_line(
      'PMLE_FREE_RASTER_BATCH|PASS|pass='||pass||
      '|frames='||c_frames||
      '|wall_ms_per_frame='||round(l_wall/c_frames,3)||
      '|clock_ms_per_frame='||round(l_clock/c_frames,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||
        case when abs(l_wall-l_clock)>30 then 1 else 0 end||
      '|checksum='||l_checksum);
  end loop;
end;
/
