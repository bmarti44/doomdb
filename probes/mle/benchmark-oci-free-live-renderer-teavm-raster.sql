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
      raise_application_error(-20796,'generated raster pack mismatch');
    end if;
  end loop;
  if doom_free_gen_finalize<>l_bytes then
    raise_application_error(-20796,'generated raster finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_TEAVM_RASTER_LOAD|PASS|pack_bytes='||l_bytes);
end;
/

declare
  l_blob blob;l_bytes number;l_expected_sha varchar2(64);
  l_actual_sha varchar2(64);l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select wall_blob,wall_bytes,wall_sha
    into l_blob,l_bytes,l_expected_sha
    from doom_free_generated_source;
  l_actual_sha:=lower(rawtohex(
    dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));
  if l_actual_sha<>l_expected_sha then
    raise_application_error(-20796,'generated raster texture hash mismatch');
  end if;
  l_loaded:=doom_free_gen_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'generated raster texture load mismatch');
    end if;
  end loop;
  if doom_free_gen_texture_finalize<>l_bytes then
    raise_application_error(-20796,'generated raster texture finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_TEAVM_RASTER_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  l_blob blob;l_bytes number;l_expected_sha varchar2(64);
  l_actual_sha varchar2(64);l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select flat_blob,flat_bytes,flat_sha
    into l_blob,l_bytes,l_expected_sha
    from doom_free_generated_source;
  l_actual_sha:=lower(rawtohex(
    dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));
  if l_actual_sha<>l_expected_sha then
    raise_application_error(-20796,'generated flat hash mismatch');
  end if;
  l_loaded:=doom_free_gen_flat_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_flat_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'generated flat load mismatch');
    end if;
  end loop;
  if doom_free_gen_flat_finalize<>l_bytes then
    raise_application_error(-20796,'generated flat finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_TEAVM_FLAT_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  l_blob blob;l_bytes number;l_expected_sha varchar2(64);
  l_actual_sha varchar2(64);l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select sprite_blob,sprite_bytes,sprite_sha
    into l_blob,l_bytes,l_expected_sha
    from doom_free_generated_source;
  l_actual_sha:=lower(rawtohex(
    dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));
  if l_actual_sha<>l_expected_sha then
    raise_application_error(-20796,'generated sprite hash mismatch');
  end if;
  l_loaded:=doom_free_gen_sprite_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_sprite_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'generated sprite load mismatch');
    end if;
  end loop;
  if doom_free_gen_sprite_finalize<>l_bytes then
    raise_application_error(-20796,'generated sprite finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_TEAVM_SPRITE_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  l_blob blob;l_bytes number;l_expected_sha varchar2(64);
  l_actual_sha varchar2(64);l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select ui_blob,ui_bytes,ui_sha
    into l_blob,l_bytes,l_expected_sha
    from doom_free_generated_source;
  l_actual_sha:=lower(rawtohex(
    dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));
  if l_actual_sha<>l_expected_sha then
    raise_application_error(-20796,'generated UI hash mismatch');
  end if;
  l_loaded:=doom_free_gen_ui_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_gen_ui_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'generated UI load mismatch');
    end if;
  end loop;
  if doom_free_gen_ui_finalize<>l_bytes then
    raise_application_error(-20796,'generated UI finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_TEAVM_UI_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  c_passes constant pls_integer:=4;
  c_frames constant pls_integer:=200;
  c_start constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_values values_t;l_sorted values_t;
  l_started timestamp with time zone;l_pass_started timestamp with time zone;
  l_wall number;l_value number;l_checksum number:=0;l_j pls_integer;
  l_stage varchar2(16);
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for stage in 1..2 loop
    l_stage:=case stage when 1 then 'PLANES_ONLY' else 'WALLS_ONLY' end;
    for pass in 1..c_passes loop
      l_pass_started:=systimestamp;
      for frame_index in 1..c_frames loop
        l_started:=systimestamp;
        if stage=1 then
          l_checksum:=l_checksum+
            doom_free_gen_planes_only(c_start+frame_index-1);
        else
          l_checksum:=l_checksum+
            doom_free_gen_walls_only(c_start+frame_index-1);
        end if;
        l_values(frame_index):=elapsed_ms(systimestamp-l_started);
        l_sorted(frame_index):=l_values(frame_index);
      end loop;
      l_wall:=elapsed_ms(systimestamp-l_pass_started);
      for i in 2..c_frames loop
        l_value:=l_sorted(i);l_j:=i-1;
        while l_j>=1 and l_sorted(l_j)>l_value loop
          l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
        end loop;
        l_sorted(l_j+1):=l_value;
      end loop;
      dbms_output.put_line(
        'PMLE_FREE_LIVE_TEAVM_STAGE_PASS|PASS|stage='||l_stage||
        '|pass='||pass||'|frames='||c_frames||
        '|p50_ms='||round(l_sorted(100),3)||
        '|p95_ms='||round(l_sorted(190),3)||
        '|throughput_fps='||round(c_frames*1000/l_wall,3)||
        '|pixel_writes='||doom_free_gen_raster_writes||
        '|checksum='||l_checksum);
    end loop;
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
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for pose in 0..49 loop
    l_checksum:=l_checksum+doom_free_gen_frame(pose);
  end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame in 1..c_frames loop
      l_started:=systimestamp;
      l_checksum:=l_checksum+doom_free_gen_frame(c_start+frame-1);
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
      'PMLE_FREE_LIVE_TEAVM_RASTER_PASS|PASS|pass='||pass||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(250),3)||
      '|p95_ms='||round(l_sorted(475),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|pixel_writes='||doom_free_gen_raster_writes||
      '|checksum='||l_checksum);
    if doom_free_gen_raster_writes<53760 then
      raise_application_error(-20796,'generated raster did not cover viewport');
    end if;
  end loop;
end;
/

declare
  c_chunk constant pls_integer:=8000;
  l_raw raw(8000);
  l_checksum number;
begin
  l_checksum:=doom_free_gen_frame(750);
  for part in 0..7 loop
    l_raw:=doom_free_gen_frame_chunk(part*c_chunk,c_chunk);
    dbms_output.put_line(
      'PMLE_FREE_LIVE_FRAME_CHUNK|PASS|pose=750|part='||part||
      '|bytes='||utl_raw.length(l_raw)||'|hex='||rawtohex(l_raw));
  end loop;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_FRAME_CAPTURE|PASS|pose=750|bytes=64000'||
    '|layout=COLUMN_MAJOR|checksum='||l_checksum);
end;
/

declare
  c_passes constant pls_integer:=6;
  c_frames constant pls_integer:=300;
  c_start constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_sorted values_t;
  l_started timestamp with time zone;
  l_pass_started timestamp with time zone;
  l_wall number;l_value number;l_checksum number:=0;l_j pls_integer;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for pose in 0..99 loop
    l_checksum:=l_checksum+doom_free_gen_frame_coarse(pose);
  end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;
    for frame_ in 1..c_frames loop
      l_started:=systimestamp;
      l_checksum:=l_checksum+
        doom_free_gen_frame_coarse(c_start+frame_-1);
      l_sorted(frame_):=elapsed_ms(systimestamp-l_started);
    end loop;
    l_wall:=elapsed_ms(systimestamp-l_pass_started);
    for i in 2..c_frames loop
      l_value:=l_sorted(i);l_j:=i-1;
      while l_j>=1 and l_sorted(l_j)>l_value loop
        l_sorted(l_j+1):=l_sorted(l_j);l_j:=l_j-1;
      end loop;
      l_sorted(l_j+1):=l_value;
    end loop;
    dbms_output.put_line(
      'PMLE_FREE_LIVE_TEAVM_COARSE|PASS|pass='||pass||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(150),3)||
      '|p95_ms='||round(l_sorted(285),3)||
      '|wall_ms='||round(l_wall,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|pixel_writes='||doom_free_gen_raster_writes||
      '|checksum='||l_checksum);
  end loop;
end;
/

declare
  c_chunk constant pls_integer:=8000;
  l_raw raw(8000);
  l_checksum number;
begin
  l_checksum:=doom_free_gen_frame_coarse(751);
  for part in 0..7 loop
    l_raw:=doom_free_gen_frame_chunk(part*c_chunk,c_chunk);
    dbms_output.put_line(
      'PMLE_FREE_LIVE_COARSE_FRAME_CHUNK|PASS|pose=751|part='||part||
      '|bytes='||utl_raw.length(l_raw)||'|hex='||rawtohex(l_raw));
  end loop;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_COARSE_FRAME_CAPTURE|PASS|pose=751|bytes=64000'||
    '|layout=COLUMN_MAJOR|checksum='||l_checksum);
end;
/
