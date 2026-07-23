whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited
set linesize 32767 trimspool on

declare
  c_warmups constant pls_integer := 20;
  c_samples constant pls_integer := 100;
  c_batch constant pls_integer := 5;
  type number_list is table of number index by pls_integer;
  l_samples number_list;
  l_commands raw(32767);
  l_chunk0 raw(32767);
  l_chunk1 raw(32767);
  l_mle_checksum number;
  l_native_checksum pls_integer;
  l_started number;
  l_value number;
  l_j pls_integer;
begin
  for i in 1..c_warmups loop
    doom_mle_bench_commands(i, l_commands, l_mle_checksum);
    doom_mle_native_bench.render_command_stream(
      l_commands, l_chunk0, l_chunk1, l_native_checksum);
  end loop;
  if utl_raw.length(l_commands) <> 640 or utl_raw.length(l_chunk0) <> 32000
     or utl_raw.length(l_chunk1) <> 32000 or l_mle_checksum <> l_native_checksum then
    raise_application_error(-20883, 'command compositor contract failed');
  end if;
  for i in 1..c_samples loop
    l_started := dbms_utility.get_cpu_time;
    for repetition_ in 1..c_batch loop
      doom_mle_bench_commands(i + repetition_, l_commands, l_mle_checksum);
      doom_mle_native_bench.render_command_stream(
        l_commands, l_chunk0, l_chunk1, l_native_checksum);
    end loop;
    l_samples(i) := (dbms_utility.get_cpu_time - l_started) * 10 / c_batch;
  end loop;
  for i in 2..c_samples loop
    l_value := l_samples(i);
    l_j := i - 1;
    while l_j >= 1 and l_samples(l_j) > l_value loop
      l_samples(l_j + 1) := l_samples(l_j);
      l_j := l_j - 1;
    end loop;
    l_samples(l_j + 1) := l_value;
  end loop;
  dbms_output.put_line('PMLE_COMMAND|' ||
    'mle_commands_plus_native_compositor|samples=' || c_samples ||
    '|p50_ms=' || to_char(l_samples(ceil(c_samples * .50)), 'FM999999990D000') ||
    '|p95_ms=' || to_char(l_samples(ceil(c_samples * .95)), 'FM999999990D000') ||
    '|p99_ms=' || to_char(l_samples(ceil(c_samples * .99)), 'FM999999990D000') ||
    '|max_ms=' || to_char(l_samples(c_samples), 'FM999999990D000') ||
    '|checksum=' || l_native_checksum);
  if l_samples(ceil(c_samples * .95)) <= 20
     and l_samples(ceil(c_samples * .99)) <= 33.3 then
    dbms_output.put_line('PMLE_COMMAND_GATE|PASS|p95_limit_ms=20|p99_limit_ms=33.3');
  else
    dbms_output.put_line('PMLE_COMMAND_GATE|FAIL|p95_limit_ms=20|p99_limit_ms=33.3');
  end if;
end;
/
