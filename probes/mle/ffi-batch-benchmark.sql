whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off serveroutput on size unlimited

declare
  c_warmups constant pls_integer := 20;
  c_samples constant pls_integer := 100;
  type number_list is table of number index by pls_integer;
  l_samples number_list;
  l_checksum number;
  l_started number;
  l_value number;
  l_j pls_integer;
begin
  for i in 1..c_warmups loop doom_mle_hybrid_draw_batches(i, l_checksum); end loop;
  if l_checksum <> (1416 + 667) * 16 then
    raise_application_error(-20885, 'batched FFI byte count mismatch');
  end if;
  for i in 1..c_samples loop
    l_started := dbms_utility.get_cpu_time;
    doom_mle_hybrid_draw_batches(i, l_checksum);
    l_samples(i) := (dbms_utility.get_cpu_time - l_started) * 10;
  end loop;
  for i in 2..c_samples loop
    l_value := l_samples(i); l_j := i - 1;
    while l_j >= 1 and l_samples(l_j) > l_value loop
      l_samples(l_j + 1) := l_samples(l_j); l_j := l_j - 1;
    end loop;
    l_samples(l_j + 1) := l_value;
  end loop;
  dbms_output.put_line('PMLE_FFI_BATCH|draw_commands=2083|bytes=33328|ffi_calls=4' ||
    '|p50_ms=' || l_samples(50) || '|p95_ms=' || l_samples(95) ||
    '|p99_ms=' || l_samples(99) || '|max_ms=' || l_samples(100) ||
    '|checksum=' || l_checksum);
end;
/
