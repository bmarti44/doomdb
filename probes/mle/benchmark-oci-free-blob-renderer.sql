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
  l_loaded:=doom_free_blob_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_pack,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_blob_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if doom_free_blob_finalize<>l_bytes then
    raise_application_error(-20796,'Blob renderer pack mismatch');
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
    raise_application_error(-20796,'Blob renderer texture hash mismatch');
  end if;
  l_loaded:=doom_free_blob_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_blob_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
  end loop;
  if doom_free_blob_texture_finalize<>l_bytes then
    raise_application_error(-20796,'Blob renderer texture finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_BLOB_TEXTURE|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  type poses_t is table of pls_integer;
  l_poses poses_t:=poses_t(500,750,999);
  l_blob blob;l_reference raw(32000);l_actual raw(32000);l_dummy number;
begin
  if doom_free_blob_reset<>262144 then
    raise_application_error(-20796,'Blob renderer reset mismatch');
  end if;
  for item in 1..l_poses.count loop
    l_dummy:=doom_free_blob_ref_frame(l_poses(item));
    l_blob:=doom_free_blob_frame(l_poses(item));
    if dbms_lob.getlength(l_blob)<>64000 then
      raise_application_error(-20796,'Blob renderer frame length mismatch');
    end if;
    for half in 0..1 loop
      l_reference:=doom_free_blob_ref_chunk(half*32000,32000);
      l_actual:=dbms_lob.substr(l_blob,32000,half*32000+1);
      if utl_raw.compare(l_reference,l_actual)<>0 then
        raise_application_error(
          -20796,'Blob renderer frame mismatch at pose '||l_poses(item));
      end if;
    end loop;
    dbms_output.put_line(
      'PMLE_FREE_BLOB_EQUIVALENCE|PASS|pose='||l_poses(item)||
      '|frame_bytes=64000|stats='||doom_free_blob_stats);
    if dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob);end if;
  end loop;
end;
/

declare
  c_passes constant pls_integer:=6;
  c_frames constant pls_integer:=500;
  c_start constant pls_integer:=500;
  type values_t is table of number index by pls_integer;
  l_values values_t;l_sorted values_t;
  l_started timestamp with time zone;l_pass_started timestamp with time zone;
  l_clock_started number;l_wall number;l_clock number;l_value number;
  l_checksum number:=0;l_j pls_integer;l_suspects number;l_blob blob;
  function elapsed_ms(p interval day to second)return number is
  begin
    return extract(day from p)*86400000+extract(hour from p)*3600000+
      extract(minute from p)*60000+extract(second from p)*1000;
  end;
begin
  if doom_free_blob_reset<>262144 then
    raise_application_error(-20796,'Blob renderer timed reset mismatch');
  end if;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame_ in 1..c_frames loop
      l_started:=systimestamp;
      l_blob:=doom_free_blob_frame(c_start+frame_-1);
      if dbms_lob.getlength(l_blob)<>64000 then
        raise_application_error(-20796,'Blob renderer timed length mismatch');
      end if;
      l_values(frame_):=elapsed_ms(systimestamp-l_started);
      l_sorted(frame_):=l_values(frame_);
      l_checksum:=l_checksum+dbms_lob.getlength(l_blob);
      if dbms_lob.istemporary(l_blob)=1 then
        dbms_lob.freetemporary(l_blob);
      end if;
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
      'PMLE_FREE_BLOB_PASS|PASS|pass='||pass||
      '|cache='||case when pass=1 then 'COLD_ROUTE' else 'REPLAY_WARM' end||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(250),3)||
      '|p95_ms='||round(l_sorted(475),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|last_stats='||doom_free_blob_stats||
      '|checksum='||l_checksum);
  end loop;
end;
/
