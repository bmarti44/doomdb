whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off timing off

declare
  c_samples constant pls_integer := 1500;
  type numbers is table of number index by binary_integer;
  totals numbers;
  blob_writes numbers;
  l_session varchar2(32);
  new_game_payload blob;
  step_payload blob;
  state_payload blob;
  ignored_sha varchar2(64);
  started number;
  elapsed_ms number;

  procedure quicksort(values_io in out nocopy numbers, low_index binary_integer,
      high_index binary_integer) is
    left_index binary_integer := low_index;
    right_index binary_integer := high_index;
    pivot number := values_io(trunc((low_index + high_index) / 2));
    swap_value number;
  begin
    while left_index <= right_index loop
      while values_io(left_index) < pivot loop left_index := left_index + 1; end loop;
      while values_io(right_index) > pivot loop right_index := right_index - 1; end loop;
      if left_index <= right_index then
        swap_value := values_io(left_index);
        values_io(left_index) := values_io(right_index);
        values_io(right_index) := swap_value;
        left_index := left_index + 1;
        right_index := right_index - 1;
      end if;
    end loop;
    if low_index < right_index then quicksort(values_io, low_index, right_index); end if;
    if left_index < high_index then quicksort(values_io, left_index, high_index); end if;
  end;

  procedure emit(label varchar2, values_io in out nocopy numbers) is
  begin
    quicksort(values_io, 1, c_samples);
    dbms_output.put_line(label ||
      ' p50_ms=' || to_char(values_io(750) / 1e6, 'FM9990.000') ||
      ' p95_ms=' || to_char(values_io(1425) / 1e6, 'FM9990.000') ||
      ' p99_ms=' || to_char(values_io(1485) / 1e6, 'FM9990.000'));
  end;
begin
  doom_api.new_game(3, l_session, new_game_payload);
  doom_tic_tx.apply_batch(l_session, to_clob(
    '{"v":1,"commands":[{"turn":1,"forward":0,"strafe":0,"run":0,' ||
    '"fire":0,"use":0,"weapon":0,"pause":0,"automap":0,"menu":"NONE",' ||
    '"cheat":"","seq":1}]}'), step_payload);
  dbms_lob.createtemporary(state_payload, true);
  for batch_index in 1 .. 10 loop
    started := dbms_utility.get_time;
    for frame_index in 1 .. 50 loop
      ignored_sha := doom_state_codec_fill(l_session, 0, state_payload);
    end loop;
    dbms_output.put_line('WARM frames=' || batch_index * 50 || ' batch_ms=' ||
      to_char((dbms_utility.get_time - started) * 10, 'FM9999990.000'));
  end loop;
  started := dbms_utility.get_time;
  for sample_index in 1 .. c_samples loop
    ignored_sha := doom_state_codec_fill(l_session, 0, state_payload);
    totals(sample_index) := doom_state_codec_total_ns();
    blob_writes(sample_index) := doom_state_codec_blob_ns();
  end loop;
  elapsed_ms := (dbms_utility.get_time - started) * 10;
  dbms_output.put_line('STATE_CODEC frames=' || c_samples ||
    ' elapsed_ms=' || to_char(elapsed_ms, 'FM9999990.000') ||
    ' mean_call_ms=' || to_char(elapsed_ms / c_samples, 'FM9990.000') ||
    ' bytes=' || dbms_lob.getlength(state_payload));
  emit('TOTAL', totals);
  emit('BLOB', blob_writes);
  rollback;
end;
/

exit
