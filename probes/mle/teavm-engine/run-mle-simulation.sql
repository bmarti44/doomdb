whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 serveroutput on size unlimited

declare
  c_warmups constant pls_integer := 30;
  c_samples constant pls_integer := 300;
  c_p95_limit_ms constant number := 15;
  type number_list is table of number index by binary_integer;
  l_samples number_list;
  l_iwad blob;
  l_table_pack blob;
  l_iwad_bytes pls_integer;
  l_offset pls_integer := 0;
  l_chunk raw(32767);
  l_loaded pls_integer;
  l_state varchar2(4000);
  l_tic number;
  l_initial varchar2(4000);
  l_memory varchar2(4000);
  l_started timestamp with time zone;
  l_delta interval day to second;
  l_value number;
  l_prior number;

  function interval_ms(p_delta interval day to second) return number is
  begin
    return extract(day from p_delta) * 86400000
      + extract(hour from p_delta) * 3600000
      + extract(minute from p_delta) * 60000
      + extract(second from p_delta) * 1000;
  end;
begin
  select payload_bytes into l_iwad
    from doom_engine_artifact
   where artifact_name = 'freedoom1.wad';
  l_iwad_bytes := dbms_lob.getlength(l_iwad);
  l_loaded := doom_teavm_sim_allocate(l_iwad_bytes);
  if l_loaded <> l_iwad_bytes then
    raise_application_error(-20790, 'MLE IWAD allocation mismatch');
  end if;

  while l_offset < l_iwad_bytes loop
    l_chunk := dbms_lob.substr(
      least(32767, l_iwad_bytes - l_offset), l_offset + 1, l_iwad);
    l_loaded := doom_teavm_sim_load(l_offset, l_chunk);
    l_offset := l_offset + utl_raw.length(l_chunk);
    if l_loaded <> l_offset then
      raise_application_error(-20790, 'MLE IWAD chunk mismatch at ' || l_offset);
    end if;
  end loop;

  select table_pack_blob into l_table_pack from doom_teavm_sim_source;
  l_iwad_bytes := dbms_lob.getlength(l_table_pack);
  l_offset := 0;
  l_loaded := doom_teavm_sim_table_allocate(l_iwad_bytes);
  while l_offset < l_iwad_bytes loop
    l_chunk := dbms_lob.substr(
      least(32767, l_iwad_bytes - l_offset), l_offset + 1, l_table_pack);
    l_loaded := doom_teavm_sim_table_load(l_offset, l_chunk);
    l_offset := l_offset + utl_raw.length(l_chunk);
    if l_loaded <> l_offset then
      raise_application_error(-20790,
        'MLE canonical-table chunk mismatch at ' || l_offset);
    end if;
  end loop;

  l_initial := doom_teavm_sim_initialize();
  dbms_output.put_line('PMLE_TEAVM_SIM_INITIAL|' || l_initial);

  for i in 1 .. c_warmups loop
    l_tic := doom_teavm_sim_step_bare(
      case when mod(i - 1, 7) = 0 then 25 else 0 end,
      case when mod(i - 1, 11) = 0 then -24 else 0 end,
      case when mod(i - 1, 5) = 0 then -640 else 0 end,
      0);
  end loop;

  for i in 1 .. c_samples loop
    l_started := systimestamp;
    l_tic := doom_teavm_sim_step_bare(
      case when mod(i - 1, 7) = 0 then 25 else 0 end,
      case when mod(i - 1, 11) = 0 then -24 else 0 end,
      case when mod(i - 1, 5) = 0 then -640 else 0 end,
      0);
    l_delta := systimestamp - l_started;
    l_samples(i) := interval_ms(l_delta);
    if l_tic <> c_warmups + i then
      raise_application_error(-20790, 'MLE tic mismatch at ' || i);
    end if;
  end loop;
  l_state := doom_teavm_sim_state();
  l_memory := doom_teavm_sim_memory();

  for i in 2 .. c_samples loop
    l_value := l_samples(i);
    l_prior := i - 1;
    while l_prior >= 1 and l_samples(l_prior) > l_value loop
      l_samples(l_prior + 1) := l_samples(l_prior);
      l_prior := l_prior - 1;
    end loop;
    l_samples(l_prior + 1) := l_value;
  end loop;

  dbms_output.put_line('PMLE_TEAVM_SIM_FINAL|' || l_state);
  dbms_output.put_line(
    'PMLE_TEAVM_SIM_TIMING|warmups=' || c_warmups || '|samples=' || c_samples
      || '|p50Ms=' || to_char(l_samples(ceil(c_samples * 0.50)), 'fm9999990d000')
      || '|p95Ms=' || to_char(l_samples(ceil(c_samples * 0.95)), 'fm9999990d000')
      || '|maxMs=' || to_char(l_samples(c_samples), 'fm9999990d000')
      || '|targetP95Ms=' || to_char(c_p95_limit_ms, 'fm9999990d000'));
  if l_samples(ceil(c_samples * 0.95)) > c_p95_limit_ms then
    raise_application_error(-20791, 'MLE authoritative ticker p95 gate failed');
  end if;
  dbms_output.put_line('PMLE_TEAVM_SIM_GATE|PASS|scope=authoritative_ticker');
  dbms_output.put_line('PMLE_TEAVM_SIM_MEMORY|' || l_memory);
  doom_teavm_sim_release;
exception
  when others then
    begin
      doom_teavm_sim_release;
    exception
      when others then null;
    end;
    raise;
end;
/
