whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

declare
  l_pack blob;l_bytes number;l_offset number:=0;l_chunk raw(16000);
  l_loaded number;l_frames number;
begin
  select pack_blob,pack_bytes into l_pack,l_bytes from doom_free_full_pack;
  l_loaded:=doom_free_full_allocate(l_bytes);
  while l_offset<l_bytes loop
    l_chunk:=dbms_lob.substr(
      l_pack,least(16000,l_bytes-l_offset),l_offset+1);
    l_loaded:=doom_free_full_load(l_offset,l_chunk);
    l_offset:=l_offset+utl_raw.length(l_chunk);
    if l_loaded<>l_offset then
      raise_application_error(-20796,'full-command load mismatch');
    end if;
  end loop;
  l_frames:=doom_free_full_finalize;
  if l_frames<>192 or doom_free_full_count<>192 then
    raise_application_error(-20796,'full-command frame count mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FULL_COMMAND_LOAD|PASS|pack_bytes='||l_bytes||
    '|frames='||l_frames);
end;
/

declare
  l_frame blob;l_chunk raw(32767);l_offset number;l_size number;
  l_actual varchar2(64);l_expected varchar2(64);l_value number;
begin
  for sample_ in (
    select 0 frame_index from dual union all
    select 95 from dual union all
    select 191 from dual
  ) loop
    l_value:=doom_free_full_render(sample_.frame_index);
    if doom_free_full_frame_prepare<>64000 then
      raise_application_error(-20796,'full-command frame size mismatch');
    end if;
    dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
    l_offset:=0;
    while l_offset<64000 loop
      l_size:=least(32767,64000-l_offset);
      l_chunk:=doom_free_full_frame_chunk(l_offset,l_size);
      if utl_raw.length(l_chunk)<>l_size then
        raise_application_error(-20796,'full-command frame short read');
      end if;
      dbms_lob.writeappend(l_frame,l_size,l_chunk);
      l_offset:=l_offset+l_size;
    end loop;
    l_actual:=lower(rawtohex(
      dbms_crypto.hash(l_frame,dbms_crypto.hash_sh256)));
    l_expected:=lower(rawtohex(
      doom_free_full_frame_digest(sample_.frame_index)));
    dbms_lob.freetemporary(l_frame);
    if l_actual<>l_expected then
      raise_application_error(-20796,'full-command frame digest mismatch');
    end if;
    dbms_output.put_line(
      'PMLE_FULL_COMMAND_EQUIVALENCE|PASS|frame='||
      sample_.frame_index||'|sha256='||l_actual||'|checksum='||l_value);
  end loop;
end;
/

declare
  c_passes constant pls_integer:=12;
  c_frames constant pls_integer:=192;
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
  for warmup in 1..5 loop
    l_checksum:=l_checksum+doom_free_full_batch(0,c_frames);
  end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame in 1..c_frames loop
      l_started:=systimestamp;
      l_checksum:=l_checksum+doom_free_full_render(frame-1);
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
      'PMLE_FULL_COMMAND_PASS|PASS|pass='||pass||
      '|frames='||c_frames||
      '|p50_ms='||round(l_sorted(96),3)||
      '|p95_ms='||round(l_sorted(183),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|checksum='||l_checksum);
  end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    l_checksum:=l_checksum+doom_free_full_batch(0,c_frames);
    l_wall:=elapsed_ms(systimestamp-l_pass_started);
    l_clock:=(dbms_utility.get_time-l_clock_started)*10;
    l_suspects:=case when abs(l_wall-l_clock)>30 then 1 else 0 end;
    dbms_output.put_line(
      'PMLE_FULL_COMMAND_BATCH|PASS|pass='||pass||
      '|frames='||c_frames||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|wall_ms_per_frame='||round(l_wall/c_frames,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||
      '|checksum='||l_checksum);
  end loop;
end;
/
