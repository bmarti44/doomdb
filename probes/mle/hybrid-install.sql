whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off

begin execute immediate 'drop procedure doom_mle_hybrid_render';
exception when others then if sqlcode <> -4043 then raise; end if; end;
/
begin execute immediate 'drop procedure doom_mle_hybrid_draw_calls';
exception when others then if sqlcode <> -4043 then raise; end if; end;
/
begin execute immediate 'drop procedure doom_mle_hybrid_draw_batches';
exception when others then if sqlcode <> -4043 then raise; end if; end;
/
begin execute immediate 'drop mle module doom_mle_hybrid_bench';
exception when others then if sqlcode not in (-4080, -4103) then raise; end if; end;
/
begin execute immediate 'drop mle env doom_mle_hybrid_env';
exception when others then if sqlcode not in (-4080, -4103, -4104, -4105) then raise; end if; end;
/

create mle env doom_mle_hybrid_env;

create mle module doom_mle_hybrid_bench
language javascript as

import * as plsffi from 'mle-js-plsql-ffi';

const renderer = plsffi.resolvePackage('doom_mle_native_bench');
const drawTape = new Uint8Array((1416 + 667) * 16);
const drawWords = new Uint32Array(drawTape.buffer);

function byteSwap32(value) {
  return ((value & 255) << 24) | ((value & 65280) << 8) |
    ((value >>> 8) & 65280) | (value >>> 24);
}

export function render(seed, chunk0, chunk1, checksumOut) {
  const nativeChunk0 = plsffi.arg({type: oracledb.DB_TYPE_RAW, maxSize: 32767});
  const nativeChunk1 = plsffi.arg({type: oracledb.DB_TYPE_RAW, maxSize: 32767});
  const nativeChecksum = plsffi.arg();
  renderer.render_translated_columns(
    seed, nativeChunk0, nativeChunk1, nativeChecksum);
  chunk0.value = nativeChunk0.val;
  chunk1.value = nativeChunk1.val;
  checksumOut.value = nativeChecksum.val;
}

export function drawCalls(seed, checksumOut) {
  renderer.reset_draw_calls();
  for (let command = 0; command < 1416; command++) {
    renderer.consume_draw_call(1, (command + seed) % 320,
      (command * 17 + seed) % 120, 8 + (command % 73), command & 63,
      (command >>> 3) & 31, command + seed, (command & 7) + 1);
  }
  for (let command = 0; command < 667; command++) {
    renderer.consume_draw_call(2, (command + seed) % 200,
      (command * 13) % 240, 8 + (command % 73), command & 63,
      (command >>> 3) & 31, command + seed, (command & 15) + 1);
  }
  const nativeChecksum = plsffi.arg();
  renderer.read_draw_checksum(nativeChecksum);
  checksumOut.value = nativeChecksum.val;
}

export function drawBatches(seed, checksumOut) {
  let word = 0;
  for (let command = 0; command < 2083; command++) {
    const kind = command < 1416 ? 1 : 2;
    const local = kind === 1 ? command : command - 1416;
    const coordinate = (local + seed) & 65535;
    const ordinate = (local * 17 + seed) & 255;
    const count = 8 + (local % 29);
    const frac = Math.imul(local + seed, 1103515245) | 0;
    const step = ((local & 7) + 1) << 10;
    drawWords[word] = byteSwap32(kind | (coordinate << 8) | (ordinate << 24));
    drawWords[word + 1] = byteSwap32(count | ((local & 63) << 8) |
      (((local >>> 3) & 31) << 16) | (((local + seed) & 63) << 24));
    drawWords[word + 2] = byteSwap32(frac);
    drawWords[word + 3] = byteSwap32(step);
    word += 4;
  }
  renderer.reset_draw_calls();
  renderer.consume_draw_blob(plsffi.argOf(drawTape, {
    type: oracledb.DB_TYPE_BLOB, maxSize: drawTape.length
  }));
  checksumOut.value = drawTape.length;
}
/

create procedure doom_mle_hybrid_render(
  p_seed in number,
  p_chunk0 out raw,
  p_chunk1 out raw,
  p_checksum out number
)
as mle module doom_mle_hybrid_bench
env doom_mle_hybrid_env
signature 'render(number, Out<Uint8Array>, Out<Uint8Array>, Out<number>)';
/

create procedure doom_mle_hybrid_draw_calls(
  p_seed in number,
  p_checksum out number
)
as mle module doom_mle_hybrid_bench
env doom_mle_hybrid_env
signature 'drawCalls(number, Out<number>)';
/

create procedure doom_mle_hybrid_draw_batches(
  p_seed in number,
  p_checksum out number
)
as mle module doom_mle_hybrid_bench
env doom_mle_hybrid_env
signature 'drawBatches(number, Out<number>)';
/
