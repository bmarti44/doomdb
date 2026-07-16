whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off timing off

declare
  c_samples constant pls_integer := 1500;
  type numbers is table of number index by binary_integer;
  total numbers;
  render numbers;
  bsp numbers;
  solid numbers;
  portal numbers;
  plane numbers;
  sprite numbers;
  present numbers;
  codec numbers;
  blob_write numbers;
  payload blob;
  started number;
  elapsed_ms number;

  procedure quicksort(
    values_io in out nocopy numbers,
    low_index in binary_integer,
    high_index in binary_integer
  ) is
    left_index binary_integer := low_index;
    right_index binary_integer := high_index;
    pivot number := values_io(trunc((low_index + high_index) / 2));
    swap_value number;
  begin
    while left_index <= right_index loop
      while values_io(left_index) < pivot loop
        left_index := left_index + 1;
      end loop;
      while values_io(right_index) > pivot loop
        right_index := right_index - 1;
      end loop;
      if left_index <= right_index then
        swap_value := values_io(left_index);
        values_io(left_index) := values_io(right_index);
        values_io(right_index) := swap_value;
        left_index := left_index + 1;
        right_index := right_index - 1;
      end if;
    end loop;
    if low_index < right_index then
      quicksort(values_io, low_index, right_index);
    end if;
    if left_index < high_index then
      quicksort(values_io, left_index, high_index);
    end if;
  end quicksort;

  procedure emit_percentiles(
    label in varchar2,
    values_io in out nocopy numbers
  ) is
  begin
    quicksort(values_io, 1, c_samples);
    dbms_output.put_line(
      rpad(label, 8) ||
      ' p50_ms=' || to_char(values_io(750) / 1e6, 'FM9990.000') ||
      ' p95_ms=' || to_char(values_io(1425) / 1e6, 'FM9990.000') ||
      ' p99_ms=' || to_char(values_io(1485) / 1e6, 'FM9990.000')
    );
  end emit_percentiles;
begin
  dbms_lob.createtemporary(payload, true);
  started := dbms_utility.get_time;
  for sample_index in 1 .. c_samples loop
    doom_bsp_kernel_fill(payload);
    render(sample_index) := doom_bsp_last_render_ns();
    bsp(sample_index) := doom_bsp_last_bsp_ns();
    solid(sample_index) := doom_bsp_last_solid_ns();
    portal(sample_index) := doom_bsp_last_portal_ns();
    plane(sample_index) := doom_bsp_last_plane_ns();
    sprite(sample_index) := doom_bsp_last_sprite_ns();
    present(sample_index) := doom_bsp_last_presentation_ns();
    codec(sample_index) := doom_bsp_last_codec_ns();
    blob_write(sample_index) := doom_bsp_last_blob_ns();
    total(sample_index) := render(sample_index) + codec(sample_index) +
      blob_write(sample_index);
  end loop;
  elapsed_ms := (dbms_utility.get_time - started) * 10;
  dbms_output.put_line(
    'OJVM frames=' || c_samples ||
    ' elapsed_ms=' || to_char(elapsed_ms, 'FM9999990.000') ||
    ' mean_call_ms=' || to_char(elapsed_ms / c_samples, 'FM9990.000') ||
    ' payload_bytes=' || dbms_lob.getlength(payload)
  );
  emit_percentiles('TOTAL', total);
  emit_percentiles('RENDER', render);
  emit_percentiles('BSP', bsp);
  emit_percentiles('SOLID', solid);
  emit_percentiles('PORTAL', portal);
  emit_percentiles('PLANE', plane);
  emit_percentiles('SPRITE', sprite);
  emit_percentiles('PRESENT', present);
  emit_percentiles('CODEC', codec);
  emit_percentiles('BLOB', blob_write);
  dbms_lob.freetemporary(payload);
end;
/

exit
