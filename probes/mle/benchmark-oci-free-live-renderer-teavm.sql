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
      raise_application_error(-20796,'generated renderer load mismatch');
    end if;
  end loop;
  if doom_free_gen_finalize<>l_bytes then
    raise_application_error(-20796,'generated renderer finalize mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_FREE_LIVE_TEAVM_LOAD|PASS|bytes='||l_bytes);
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
    l_checksum:=l_checksum+doom_free_gen_render(pose);
  end loop;
  for pass in 1..c_passes loop
    l_pass_started:=systimestamp;l_clock_started:=dbms_utility.get_time;
    for frame in 1..c_frames loop
      l_started:=systimestamp;
      l_checksum:=l_checksum+doom_free_gen_render(c_start+frame-1);
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
      'PMLE_FREE_LIVE_TEAVM_PASS|PASS|pass='||pass||'|frames='||c_frames||
      '|p50_ms='||round(l_sorted(250),3)||
      '|p95_ms='||round(l_sorted(475),3)||
      '|wall_ms='||round(l_wall,3)||
      '|clock_ms='||round(l_clock,3)||
      '|throughput_fps='||round(c_frames*1000/l_wall,3)||
      '|clock_suspects='||l_suspects||'|checksum='||l_checksum);
  end loop;
end;
/
