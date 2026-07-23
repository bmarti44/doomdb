whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_warmups constant pls_integer := 20;
  c_samples constant pls_integer := 100;
  c_expected_bytes constant pls_integer := (1416 + 667) * 16;
  type number_list is table of number index by pls_integer;
  l_samples number_list;
  l_tape blob;
  l_checksum number;
  l_started number;
  l_value number;
  l_j pls_integer;

  procedure report(p_name varchar2) is
  begin
    dbms_output.put_line('PMLE_TAPE|' || p_name ||
      '|bytes=' || c_expected_bytes || '|columns=1416|spans=667' ||
      '|p50_ms=' || l_samples(50) || '|p95_ms=' || l_samples(95) ||
      '|p99_ms=' || l_samples(99) || '|max_ms=' || l_samples(100) ||
      '|checksum=' || l_checksum);
  end;

  procedure sort_samples is
  begin
    for i in 2..c_samples loop
      l_value := l_samples(i); l_j := i - 1;
      while l_j >= 1 and l_samples(l_j) > l_value loop
        l_samples(l_j + 1) := l_samples(l_j); l_j := l_j - 1;
      end loop;
      l_samples(l_j + 1) := l_value;
    end loop;
  end;
begin
  for i in 1..c_warmups loop
    doom_mle_bench_tape(i, l_tape, l_checksum);
  end loop;
  if dbms_lob.getlength(l_tape) <> c_expected_bytes then
    raise_application_error(-20884, 'production tape BLOB has wrong length');
  end if;
  for i in 1..c_samples loop
    l_started := dbms_utility.get_cpu_time;
    doom_mle_bench_tape(i, l_tape, l_checksum);
    l_samples(i) := (dbms_utility.get_cpu_time - l_started) * 10;
  end loop;
  sort_samples;
  report('mle_production_cardinality_blob');

  for i in 1..c_warmups loop doom_mle_bench_cached_tape(l_tape); end loop;
  for i in 1..c_samples loop
    l_started := dbms_utility.get_cpu_time;
    doom_mle_bench_cached_tape(l_tape);
    l_samples(i) := (dbms_utility.get_cpu_time - l_started) * 10;
  end loop;
  sort_samples;
  report('mle_cached_blob_egress');
end;
/
