whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  l_pack blob;l_bytes number;l_offset number:=0;l_chunk raw(16000);
  l_loaded number;
begin
  select pack_blob,pack_bytes into l_pack,l_bytes from doom_free_live_source;
  l_loaded:=doom_free_live_allocate(l_bytes);
  if l_loaded<>l_bytes then
    raise_application_error(-20796,'free live rank allocation mismatch');
  end if;
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_pack,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_live_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'free live rank load mismatch');
    end if;
  end loop;
  if doom_free_live_finalize<>l_bytes then
    raise_application_error(-20796,'free live rank finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_RANK_LOAD|PASS|bytes='||l_bytes||'|'||
    doom_free_live_stats);
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
    raise_application_error(-20796,'rank wall texture source hash mismatch');
  end if;
  l_loaded:=doom_free_live_texture_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_blob,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_live_texture_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'rank wall texture load mismatch');
    end if;
  end loop;
  if doom_free_live_texture_finalize<>l_bytes then
    raise_application_error(-20796,'rank wall texture finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_RANK_TEXTURE_LOAD|PASS|bytes='||l_bytes||
    '|sha256='||l_actual_sha);
end;
/

declare
  c_passes constant pls_integer:=6;
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
  for pose in 0..49 loop l_checksum:=l_checksum+doom_free_live_render(pose);end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame in 1..c_frames loop
      l_started:=systimestamp;
      l_checksum:=l_checksum+doom_free_live_render((pass-1)*c_frames+frame-1);
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
      'PMLE_FREE_LIVE_PASS|PASS|pass='||pass||'|frames='||c_frames||
      '|p50_ms='||round(l_sorted(250),3)||
      '|p95_ms='||round(l_sorted(475),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||'|checksum='||l_checksum);
  end loop;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_STATS|PASS|'||doom_free_live_stats||
    '|frame_bytes='||(
      utl_raw.length(doom_free_live_frame_chunk(0,32000))+
      utl_raw.length(doom_free_live_frame_chunk(32000,32000))));
  doom_free_live_release;
exception when others then
  begin doom_free_live_release;exception when others then null;end;
  raise;
end;
/
