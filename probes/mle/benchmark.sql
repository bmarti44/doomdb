whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
set linesize 32767 long 1000000 longchunksize 1000000 trimspool on

declare
  c_width                 constant pls_integer := 320;
  c_height                constant pls_integer := 200;
  c_frame_bytes           constant pls_integer := c_width * c_height;
  c_chunk_bytes           constant pls_integer := c_frame_bytes / 2;
  c_warmups               constant pls_integer := 30;
  c_fail_fast_samples     constant pls_integer := 30;
  c_full_samples          constant pls_integer := 300;
  c_renderer_p95_limit_ms constant number := 20;
  c_renderer_p99_limit_ms constant number := 33.3;
  c_fail_fast_median_ms   constant number := 100;
  c_timing_batch          constant pls_integer := 2;

  type number_list is table of number index by pls_integer;
  l_samples number_list;
  l_chunk0 raw(32767);
  l_chunk1 raw(32767);
  l_checksum number;
  l_counter1 number;
  l_counter2 number;
  l_started_cpu number;
  l_elapsed_ms number;
  l_p50 number;
  l_p95 number;
  l_p99 number;
  l_max number;
  l_sum number;
  l_run pls_integer;
  l_count pls_integer;
  l_arithmetic_result number;
  l_arithmetic_ns number;
  l_capability varchar2(32767);
  l_version varchar2(4000);
  l_gate_pass boolean := true;
  l_baseline_p50 number;
  l_column_p95 number;
  l_column_p99 number;

  procedure summarize(p_count pls_integer) is
    l_sorted number_list := l_samples;
    l_value number;
    l_j pls_integer;
  begin
    for i in 2..p_count loop
      l_value := l_sorted(i);
      l_j := i - 1;
      while l_j >= 1 and l_sorted(l_j) > l_value loop
        l_sorted(l_j + 1) := l_sorted(l_j);
        l_j := l_j - 1;
      end loop;
      l_sorted(l_j + 1) := l_value;
    end loop;
    l_sum := 0;
    for i in 1..p_count loop l_sum := l_sum + l_sorted(i); end loop;
    l_p50 := l_sorted(ceil(p_count * 0.50));
    l_p95 := l_sorted(ceil(p_count * 0.95));
    l_p99 := l_sorted(ceil(p_count * 0.99));
    l_max := l_sorted(p_count);
  end;

  procedure sample_frame(p_seed pls_integer, p_slot pls_integer) is
  begin
    l_started_cpu := dbms_utility.get_cpu_time;
    for repetition in 1..c_timing_batch loop
      doom_mle_bench_render(p_seed + repetition, l_chunk0, l_chunk1, l_checksum);
    end loop;
    l_samples(p_slot) := (dbms_utility.get_cpu_time - l_started_cpu) * 10 /
      c_timing_batch;
    if utl_raw.length(l_chunk0) <> c_chunk_bytes
       or utl_raw.length(l_chunk1) <> c_chunk_bytes then
      raise_application_error(-20870, 'MLE renderer returned wrong frame length');
    end if;
  end;

  procedure sample_columns(
    p_seed pls_integer,p_dynamic_columns pls_integer,p_slot pls_integer) is
  begin
    l_started_cpu := dbms_utility.get_cpu_time;
    for repetition in 1..c_timing_batch loop
      doom_mle_bench_columns(p_seed + repetition, p_dynamic_columns,
        l_chunk0, l_chunk1, l_checksum);
    end loop;
    l_samples(p_slot) := (dbms_utility.get_cpu_time - l_started_cpu) * 10 /
      c_timing_batch;
    if utl_raw.length(l_chunk0) <> c_chunk_bytes
       or utl_raw.length(l_chunk1) <> c_chunk_bytes then
      raise_application_error(-20873, 'MLE column renderer returned wrong frame length');
    end if;
  end;
begin
  select banner_full into l_version
    from v$version where banner_full like 'Oracle%Database%26ai%' and rownum = 1;
  dbms_output.put_line('PMLE_VERSION|' || replace(l_version, chr(10), ' '));

  l_capability := doom_mle_bench_capability;
  dbms_output.put_line('PMLE_CAPABILITY|' || l_capability);
  if not regexp_like(l_capability, '"navigator":"object"')
     or not regexp_like(l_capability, '"webAssembly":"undefined"') then
    raise_application_error(-20871, 'unexpected MLE runtime capability set');
  end if;

  l_counter1 := doom_mle_bench_counter;
  l_counter2 := doom_mle_bench_counter;
  if l_counter1 <> 1 or l_counter2 <> 2 then
    raise_application_error(-20872, 'stored MLE module state did not persist');
  end if;
  dbms_output.put_line('PMLE_STATE|counter=' || l_counter1 || ',' || l_counter2);

  l_started_cpu := dbms_utility.get_cpu_time;
  l_arithmetic_result := doom_mle_bench_arithmetic(1000000, 17);
  l_arithmetic_ns := (dbms_utility.get_cpu_time - l_started_cpu) * 10000000 /
    1000000;
  dbms_output.put_line('PMLE_ARITHMETIC|iterations=1000000|ns_per_iteration=' ||
    to_char(l_arithmetic_ns, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
    '|checksum=' || l_arithmetic_result);

  for i in 1..c_warmups loop
    doom_mle_bench_render(-i, l_chunk0, l_chunk1, l_checksum);
  end loop;

  l_count := c_fail_fast_samples;
  for i in 1..l_count loop sample_frame(i, i); end loop;
  summarize(l_count);
  dbms_output.put_line('PMLE_RENDER_PREFLIGHT|samples=' || l_count ||
    '|p50_ms=' || to_char(l_p50, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
    '|p95_ms=' || to_char(l_p95, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
    '|p99_ms=' || to_char(l_p99, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
    '|max_ms=' || to_char(l_max, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
    '|checksum=' || l_checksum);
  l_baseline_p50 := l_p50;

  for miss_index in 1..6 loop
    declare
      l_misses pls_integer := case miss_index
        when 1 then 0 when 2 then 8 when 3 then 32
        when 4 then 80 when 5 then 160 else 320 end;
    begin
      l_samples.delete;
      for i in 1..c_fail_fast_samples loop
        sample_columns(miss_index * 10000 + i, l_misses, i);
      end loop;
      summarize(c_fail_fast_samples);
      dbms_output.put_line('PMLE_COLUMN_MATRIX|dynamic_columns=' || l_misses ||
        '|samples=' || c_fail_fast_samples ||
        '|p50_ms=' || to_char(l_p50, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
        '|p95_ms=' || to_char(l_p95, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
        '|p99_ms=' || to_char(l_p99, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
        '|max_ms=' || to_char(l_max, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,'''));
      if l_misses = c_width then
        l_column_p95 := l_p95;
        l_column_p99 := l_p99;
      end if;
    end;
  end loop;

  if l_column_p95 > c_renderer_p95_limit_ms
     or l_column_p99 > c_renderer_p99_limit_ms then
    dbms_output.put_line('PMLE_GATE|FAIL_FAST|reason=optimized_dynamic_columns_over_budget' ||
      '|baseline_p50_ms=' || to_char(l_baseline_p50, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      '|column_p95_ms=' || to_char(l_column_p95, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      '|column_p99_ms=' || to_char(l_column_p99, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    return;
  end if;

  for run_number in 1..2 loop
    l_run := run_number;
    l_samples.delete;
    for i in 1..c_full_samples loop
      sample_columns(l_run * 100000 + i, c_width, i);
    end loop;
    summarize(c_full_samples);
    dbms_output.put_line('PMLE_RENDER_RUN|run=' || l_run || '|samples=' || c_full_samples ||
      '|mean_ms=' || to_char(l_sum / c_full_samples, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      '|p50_ms=' || to_char(l_p50, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      '|p95_ms=' || to_char(l_p95, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      '|p99_ms=' || to_char(l_p99, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,''') ||
      '|max_ms=' || to_char(l_max, 'FM999999990D000', 'NLS_NUMERIC_CHARACTERS=''.,'''));
    if l_p95 > c_renderer_p95_limit_ms or l_p99 > c_renderer_p99_limit_ms then
      l_gate_pass := false;
    end if;
  end loop;

  if l_gate_pass then
    dbms_output.put_line('PMLE_GATE|PASS|p95_limit_ms=20|p99_limit_ms=33.3');
  else
    dbms_output.put_line('PMLE_GATE|FAIL|reason=renderer_budget_exceeded' ||
      '|p95_limit_ms=20|p99_limit_ms=33.3');
  end if;
end;
/
