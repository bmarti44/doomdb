whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  l_pack blob;l_bytes number;l_offset number:=0;l_chunk raw(16000);
  l_loaded number;l_generated number;
begin
  select pack_blob,pack_bytes into l_pack,l_bytes from doom_free_hybrid_source;
  l_loaded:=doom_free_hybrid_allocate(l_bytes);
  l_generated:=doom_free_gen_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_pack,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_hybrid_load(l_offset,l_chunk);
    l_generated:=doom_free_gen_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset or l_generated<>l_offset then
      raise_application_error(-20796,'hybrid pack load mismatch');
    end if;
  end loop;
  if doom_free_hybrid_finalize<>l_bytes
      or doom_free_gen_finalize<>l_bytes then
    raise_application_error(-20796,'hybrid pack finalize mismatch');
  end if;
end;
/

declare
  l_blob blob;l_bytes number;l_expected_sha varchar2(64);
  l_actual_sha varchar2(64);l_offset number:=0;l_chunk raw(16000);
  l_hybrid number;l_generated number;
begin
  select encoded_bytes,dbms_lob.getlength(encoded_bytes),payload_sha256
    into l_blob,l_bytes,l_expected_sha
    from doom_renderer_asset_pack where asset_kind='wall_texture';
  l_actual_sha:=lower(rawtohex(
    dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256)));
  if l_actual_sha<>l_expected_sha then
    raise_application_error(-20796,'hybrid texture hash mismatch');
  end if;
  l_hybrid:=doom_free_hybrid_texture_allocate(l_bytes);
  l_generated:=doom_free_gen_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_hybrid:=doom_free_hybrid_texture_load(l_offset,l_chunk);
    l_generated:=doom_free_gen_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_hybrid<>l_offset or l_generated<>l_offset then
      raise_application_error(-20796,'hybrid texture load mismatch');
    end if;
  end loop;
  if doom_free_hybrid_texture_finalize<>l_bytes
      or doom_free_gen_texture_finalize<>l_bytes then
    raise_application_error(-20796,'hybrid texture finalize mismatch');
  end if;
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
  l_wall number;
  l_value number;
  l_checksum number:=0;
  l_j pls_integer;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for variant in 1..2 loop
    for pose in 0..99 loop
      if variant=1 then
        l_checksum:=l_checksum+doom_free_hybrid_frame(pose);
      else
        l_checksum:=l_checksum+doom_free_hybrid_frame_half(pose);
      end if;
    end loop;
    for pass in 1..c_passes loop
      l_pass_started:=systimestamp;
      for frame_ in 1..c_frames loop
        l_started:=systimestamp;
        if variant=1 then
          l_checksum:=l_checksum+
            doom_free_hybrid_frame(c_start+frame_-1);
        else
          l_checksum:=l_checksum+
            doom_free_hybrid_frame_half(c_start+frame_-1);
        end if;
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
        'PMLE_FREE_LIVE_HYBRID_INTEGRATED|PASS|variant='||
        case variant when 1 then 'FULL_WIDTH' else 'HALF_WIDTH' end||
        '|pass='||pass||
        '|frames='||c_frames||
        '|p50_ms='||round(l_sorted(150),3)||
        '|p95_ms='||round(l_sorted(285),3)||
        '|wall_ms='||round(l_wall,3)||
        '|throughput_fps='||round(c_frames*1000/l_wall,3)||
        '|stats='||doom_free_hybrid_stats||
        '|checksum='||l_checksum);
    end loop;
  end loop;
end;
/

declare
  c_frames constant pls_integer:=300;
  c_start constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_values values_t;
  l_sorted values_t;
  l_started timestamp with time zone;
  l_pass_started timestamp with time zone;
  l_wall number;
  l_value number;
  l_checksum number:=0;
  l_j pls_integer;
  l_raw_a raw(32000);
  l_raw_b raw(32000);
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  for pose in 0..49 loop
    l_checksum:=l_checksum+doom_free_hybrid_frame(pose);
  end loop;
  for stage in 1..6 loop
    l_pass_started:=systimestamp;
    for frame_ in 1..c_frames loop
      if stage=3 then
        l_checksum:=l_checksum+
          doom_free_hybrid_commands(c_start+frame_-1);
      elsif stage=5 then
        l_checksum:=l_checksum+
          doom_free_hybrid_commands_half(c_start+frame_-1);
      elsif stage=6 then
        l_checksum:=l_checksum+
          doom_free_hybrid_frame(c_start+frame_-1);
      end if;
      l_started:=systimestamp;
      case stage
        when 1 then
          l_checksum:=l_checksum+doom_free_hybrid_clear;
        when 2 then
          l_checksum:=l_checksum+
            doom_free_hybrid_commands(c_start+frame_-1);
        when 3 then
          l_checksum:=l_checksum+doom_free_hybrid_raster;
        when 4 then
          l_checksum:=l_checksum+
            doom_free_hybrid_commands_half(c_start+frame_-1);
        when 5 then
          l_checksum:=l_checksum+doom_free_hybrid_raster;
        when 6 then
          l_raw_a:=doom_free_hybrid_frame_chunk(0,32000);
          l_raw_b:=doom_free_hybrid_frame_chunk(32000,32000);
          l_checksum:=l_checksum+utl_raw.length(l_raw_a)+utl_raw.length(l_raw_b);
      end case;
      l_values(frame_):=elapsed_ms(systimestamp-l_started);
      l_sorted(frame_):=l_values(frame_);
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
      'PMLE_FREE_LIVE_HYBRID_STAGE|PASS|stage='||
      case stage when 1 then 'CLEAR' when 2 then 'COMMAND'
        when 3 then 'RASTER' when 4 then 'COMMAND_HALF'
        when 5 then 'RASTER_HALF' else 'RAW_EGRESS' end||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(150),3)||
      '|p95_ms='||round(l_sorted(285),3)||
      '|wall_ms='||round(l_wall,3)||
      '|checksum='||l_checksum);
  end loop;
end;
/
