whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited

begin
  execute immediate 'drop function doom_temporal_synth';
exception when others then
  if sqlcode<>-4043 then raise;end if;
end;
/
begin
  execute immediate 'drop mle module doom_temporal_synth_module';
exception when others then
  if sqlcode not in(-4080,-4103) then raise;end if;
end;
/

create mle module doom_temporal_synth_module language javascript as
const bytes = 64000;
const previous = new Uint8Array(bytes);
const current = new Uint8Array(bytes);
const output = new Uint8Array(bytes);
const previous32 = new Uint32Array(previous.buffer);
const current32 = new Uint32Array(current.buffer);
const output32 = new Uint32Array(output.buffer);
const blend = new Uint8Array(65536);
let phase = 0;

for (let i = 0; i < bytes; i++) {
  previous[i] = (i * 17 + (i >>> 8)) & 255;
  current[i] = (i * 29 + (i >>> 7) + 61) & 255;
}
for (let a = 0; a < 256; a++) {
  for (let b = 0; b < 256; b++) {
    // This is a deterministic indexed-color cost proxy. The production LUT
    // is built from PLAYPAL nearest colors, but has the same access shape.
    blend[(a << 8) | b] = (a + b) >>> 1;
  }
}

export function synthesize(mode) {
  phase ^= 1;
  if (mode === 1) {
    // Four-pixel blocks selected from adjacent exact keyframes.
    for (let i = 0; i < output32.length; i++) {
      output32[i] = ((i + phase) & 1) === 0
        ? previous32[i] : current32[i];
    }
  } else if (mode === 2) {
    // Pixel-granular checkerboard. Each 32-bit operation selects alternating
    // bytes from the two exact keyframes, with the pattern inverted by row.
    for (let row = 0; row < 200; row++) {
      const mask = ((row + phase) & 1) === 0 ? 0x00ff00ff : 0xff00ff00;
      const inverse = ~mask;
      const start = row * 80;
      const end = start + 80;
      for (let i = start; i < end; i++) {
        output32[i] =
          (previous32[i] & mask) | (current32[i] & inverse);
      }
    }
  } else if (mode === 3) {
    // Scanline selection tests native TypedArray bulk copies.
    for (let row = 0; row < 200; row++) {
      const start = row * 320;
      const source = ((row + phase) & 1) === 0 ? previous : current;
      output.set(source.subarray(start, start + 320), start);
    }
  } else if (mode === 4) {
    // Palette-indexed 50/50 blend through a precomputed 256x256 LUT.
    for (let i = 0; i < bytes; i++) {
      output[i] = blend[(previous[i] << 8) | current[i]];
    }
  } else if (mode === 5) {
    // Same pixel checkerboard as mode 2, with eight words per loop test.
    for (let row = 0; row < 200; row++) {
      const mask = ((row + phase) & 1) === 0 ? 0x00ff00ff : 0xff00ff00;
      const inverse = ~mask;
      const start = row * 80;
      const end = start + 80;
      for (let i = start; i < end; i += 8) {
        output32[i] = (previous32[i] & mask) | (current32[i] & inverse);
        output32[i + 1] =
          (previous32[i + 1] & mask) | (current32[i + 1] & inverse);
        output32[i + 2] =
          (previous32[i + 2] & mask) | (current32[i + 2] & inverse);
        output32[i + 3] =
          (previous32[i + 3] & mask) | (current32[i + 3] & inverse);
        output32[i + 4] =
          (previous32[i + 4] & mask) | (current32[i + 4] & inverse);
        output32[i + 5] =
          (previous32[i + 5] & mask) | (current32[i + 5] & inverse);
        output32[i + 6] =
          (previous32[i + 6] & mask) | (current32[i + 6] & inverse);
        output32[i + 7] =
          (previous32[i + 7] & mask) | (current32[i + 7] & inverse);
      }
    }
  } else {
    throw new Error(`unknown synthesis mode: ${mode}`);
  }
  // Keep the output observable and vary the next input without changing the
  // measured memory-access cardinality.
  const sample = output[(phase * 31991 + 17) % bytes];
  current[(phase * 7919 + sample) % bytes] ^= sample;
  return sample;
}
/

create function doom_temporal_synth(p_mode number) return number
as mle module doom_temporal_synth_module
signature 'synthesize(number)';
/

declare
  c_warm constant pls_integer:=60;
  c_scored constant pls_integer:=300;
  type values_t is table of number index by pls_integer;
  l_values values_t;l_sorted values_t;
  l_started timestamp with time zone;l_done timestamp with time zone;
  l_value number;l_sample number;l_k pls_integer;l_mean number;
  function elapsed_ms(p_delta interval day to second)return number is
  begin
    return extract(day from p_delta)*86400000
      +extract(hour from p_delta)*3600000
      +extract(minute from p_delta)*60000
      +extract(second from p_delta)*1000;
  end;
begin
  for mode_ in 1..5 loop
    l_mean:=0;
    for iteration_ in 1..c_warm+c_scored loop
      l_started:=systimestamp;
      l_sample:=doom_temporal_synth(mode_);
      l_done:=systimestamp;
      if iteration_>c_warm then
        l_value:=elapsed_ms(l_done-l_started);
        l_values(iteration_-c_warm):=l_value;
        l_mean:=l_mean+l_value;
      end if;
    end loop;
    l_sorted:=l_values;
    for i in 2..c_scored loop
      l_value:=l_sorted(i);l_k:=i-1;
      while l_k>=1 and l_sorted(l_k)>l_value loop
        l_sorted(l_k+1):=l_sorted(l_k);l_k:=l_k-1;
      end loop;
      l_sorted(l_k+1):=l_value;
    end loop;
    dbms_output.put_line(
      'PMLE_TEMPORAL_KERNEL|PASS|mode='||mode_
      ||'|frames='||c_scored
      ||'|p50_ms='||to_char(l_sorted(ceil(c_scored*.50)),'FM9999990.000')
      ||'|p95_ms='||to_char(l_sorted(ceil(c_scored*.95)),'FM9999990.000')
      ||'|mean_ms='||to_char(l_mean/c_scored,'FM9999990.000')
      ||'|sample='||l_sample
      ||'|plausible='||
        case when l_sorted(ceil(c_scored*.95))<=8 then 'YES' else 'NO' end);
  end loop;
end;
/

drop function doom_temporal_synth;
drop mle module doom_temporal_synth_module;
