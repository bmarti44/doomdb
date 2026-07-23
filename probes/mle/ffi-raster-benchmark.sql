whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_warmups constant pls_integer := 10;
  c_samples constant pls_integer := 50;
  type number_list is table of number index by pls_integer;
  l_samples number_list;
  l_chunk0 raw(32767);l_chunk1 raw(32767);
  l_mle_checksum number;l_frame_checksum pls_integer;
  l_started number;l_value number;l_j pls_integer;
begin
  for i in 1..c_warmups loop
    doom_mle_hybrid_draw_batches(i,l_mle_checksum);
    doom_mle_native_bench.finish_draw_frame(l_chunk0,l_chunk1,l_frame_checksum);
  end loop;
  if utl_raw.length(l_chunk0)<>32000 or utl_raw.length(l_chunk1)<>32000
     or l_mle_checksum<>(1416+667)*16 then
    raise_application_error(-20887,'hybrid raster contract failed');
  end if;
  for i in 1..c_samples loop
    l_started:=dbms_utility.get_cpu_time;
    doom_mle_hybrid_draw_batches(i,l_mle_checksum);
    doom_mle_native_bench.finish_draw_frame(l_chunk0,l_chunk1,l_frame_checksum);
    l_samples(i):=(dbms_utility.get_cpu_time-l_started)*10;
  end loop;
  for i in 2..c_samples loop
    l_value:=l_samples(i);l_j:=i-1;
    while l_j>=1 and l_samples(l_j)>l_value loop
      l_samples(l_j+1):=l_samples(l_j);l_j:=l_j-1;
    end loop;l_samples(l_j+1):=l_value;
  end loop;
  dbms_output.put_line('PMLE_FFI_RASTER|draw_commands=2083|target_pixels=45363' ||
    '|frame_bytes=64000|p50_ms='||l_samples(25)||'|p95_ms='||l_samples(48)||
    '|p99_ms='||l_samples(50)||'|max_ms='||l_samples(50)||
    '|frame_checksum='||l_frame_checksum);
end;
/
