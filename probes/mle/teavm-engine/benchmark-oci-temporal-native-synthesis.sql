whenever sqlerror exit failure rollback
set define off
set serveroutput on

declare
  c_payload_bytes constant pls_integer:=128000;
  c_chunk_bytes constant pls_integer:=32766;
  c_iterations constant pls_integer:=40;
  type raw_table is table of raw(32767) index by pls_integer;
  l_current_mask raw_table;
  l_previous_mask raw_table;
  l_previous blob;
  l_current blob;
  l_output blob;
  l_previous_raw raw(32767);
  l_current_raw raw(32767);
  l_output_raw raw(32767);
  l_fill raw(32767);
  l_amount pls_integer;
  l_offset pls_integer;
  l_pattern pls_integer;
  l_started timestamp with time zone;
  l_ended timestamp with time zone;
  l_elapsed_ms number;

  function elapsed_ms(
    p_started timestamp with time zone,p_ended timestamp with time zone)
    return number
  is
    l_interval interval day to second:=p_ended-p_started;
  begin
    return extract(day from l_interval)*86400000+
      extract(hour from l_interval)*3600000+
      extract(minute from l_interval)*60000+
      extract(second from l_interval)*1000;
  end;

  procedure fill_blob(p_blob in out nocopy blob,p_value raw) is
    l_remaining pls_integer:=c_payload_bytes;
    l_piece raw(32767):=utl_raw.copies(p_value,c_chunk_bytes);
  begin
    while l_remaining>0 loop
      l_amount:=least(l_remaining,c_chunk_bytes);
      dbms_lob.writeappend(p_blob,l_amount,utl_raw.substr(l_piece,1,l_amount));
      l_remaining:=l_remaining-l_amount;
    end loop;
  end;
begin
  -- Patterns are indexed by numerator*3 + byte-phase. They implement the
  -- exact repeating per-pixel mask used by the interval-three MLE synthesis.
  l_current_mask(3):=utl_raw.copies(hextoraw('FF0000'),10922);
  l_current_mask(4):=utl_raw.copies(hextoraw('0000FF'),10922);
  l_current_mask(5):=utl_raw.copies(hextoraw('00FF00'),10922);
  l_previous_mask(3):=utl_raw.copies(hextoraw('00FFFF'),10922);
  l_previous_mask(4):=utl_raw.copies(hextoraw('FFFF00'),10922);
  l_previous_mask(5):=utl_raw.copies(hextoraw('FF00FF'),10922);
  l_current_mask(6):=utl_raw.copies(hextoraw('FFFF00'),10922);
  l_current_mask(7):=utl_raw.copies(hextoraw('00FFFF'),10922);
  l_current_mask(8):=utl_raw.copies(hextoraw('FF00FF'),10922);
  l_previous_mask(6):=utl_raw.copies(hextoraw('0000FF'),10922);
  l_previous_mask(7):=utl_raw.copies(hextoraw('FF0000'),10922);
  l_previous_mask(8):=utl_raw.copies(hextoraw('00FF00'),10922);

  dbms_lob.createtemporary(l_previous,true,dbms_lob.call);
  dbms_lob.createtemporary(l_current,true,dbms_lob.call);
  dbms_lob.createtemporary(l_output,true,dbms_lob.call);
  fill_blob(l_previous,hextoraw('55'));
  fill_blob(l_current,hextoraw('AA'));

  -- One untimed first touch pays package and temporary-LOB initialization.
  l_output_raw:=utl_raw.bit_or(
    utl_raw.bit_and(dbms_lob.substr(l_previous,c_chunk_bytes,1),
      l_previous_mask(3)),
    utl_raw.bit_and(dbms_lob.substr(l_current,c_chunk_bytes,1),
      l_current_mask(3)));

  l_started:=systimestamp;
  for l_iteration in 1..c_iterations loop
    dbms_lob.trim(l_output,0);
    for l_numerator in 1..2 loop
      l_offset:=1;
      while l_offset<=c_payload_bytes loop
        l_amount:=least(c_chunk_bytes,c_payload_bytes-l_offset+1);
        -- 32766 is divisible by three, so every full chunk retains phase.
        l_pattern:=l_numerator*3+
          mod((l_offset-1)+l_iteration,3);
        l_previous_raw:=dbms_lob.substr(
          l_previous,l_amount,l_offset);
        l_current_raw:=dbms_lob.substr(l_current,l_amount,l_offset);
        l_output_raw:=utl_raw.bit_or(
          utl_raw.bit_and(l_previous_raw,
            utl_raw.substr(l_previous_mask(l_pattern),1,l_amount)),
          utl_raw.bit_and(l_current_raw,
            utl_raw.substr(l_current_mask(l_pattern),1,l_amount)));
        dbms_lob.writeappend(l_output,l_amount,l_output_raw);
        l_offset:=l_offset+l_amount;
      end loop;
    end loop;
  end loop;
  l_ended:=systimestamp;
  l_elapsed_ms:=elapsed_ms(l_started,l_ended);
  if dbms_lob.getlength(l_output)<>2*c_payload_bytes then
    raise_application_error(-20796,'native temporal synthesis length mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_NATIVE_TEMPORAL_SYNTHESIS|PASS'
      ||'|iterations='||c_iterations
      ||'|players=2|phases=2|bytes_per_phase='||c_payload_bytes
      ||'|total_ms='||to_char(l_elapsed_ms,'FM9999990D000')
      ||'|ms_per_temporal_bundle='||
        to_char(l_elapsed_ms/c_iterations,'FM9999990D000')
      ||'|ms_per_synthesized_frame='||
        to_char(l_elapsed_ms/(c_iterations*2),'FM9999990D000'));
  dbms_lob.freetemporary(l_previous);
  dbms_lob.freetemporary(l_current);
  dbms_lob.freetemporary(l_output);
end;
/
