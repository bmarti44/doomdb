import * as engine from 'doom_wasm2js_engine';

const FRAME_COMMAND_BYTES = 32;
let iwadLength = 0;
let tableLength = 0;
let canonicalLength = 0;

function byteArray(reference, expectedLength, label) {
  if (!Number.isInteger(reference) || reference <= 0) {
    throw new Error(`${label} has invalid TeaVM reference ${reference}`);
  }
  const actualLength = engine.teavm_arrayLength(reference);
  if (actualLength !== expectedLength) {
    throw new Error(
      `${label} length mismatch: actual=${actualLength} expected=${expectedLength}`,
    );
  }
  const offset = engine.teavm_byteArrayData(reference);
  if (!Number.isInteger(offset) || offset < 0) {
    throw new Error(`${label} has invalid linear-memory offset ${offset}`);
  }
  return new Uint8Array(engine.memory.buffer, offset, expectedLength);
}

function copyChunk(reference, totalLength, offset, chunk, label) {
  if (!(chunk instanceof Uint8Array)
      || !Number.isInteger(offset)
      || offset < 0
      || offset + chunk.byteLength > totalLength) {
    throw new Error(`${label} chunk is outside its allocated byte array`);
  }
  // Recreate the view for every chunk. A later TeaVM allocation can grow
  // linear memory and detach an earlier ArrayBuffer-backed view.
  byteArray(reference, totalLength, label).set(chunk, offset);
  return offset + chunk.byteLength;
}

export function allocateIwad(length) {
  const allocated = engine.doom_allocate_iwad(length);
  if (allocated !== length) {
    throw new Error(`IWAD allocation failed: ${allocated}/${length}`);
  }
  iwadLength = length;
  return allocated;
}

export function loadIwadChunk(offset, chunk) {
  return copyChunk(
    engine.doom_iwad_ref(),
    iwadLength,
    offset,
    chunk,
    'IWAD',
  );
}

export function allocateTablePack(length) {
  const allocated = engine.doom_allocate_tables(length);
  if (allocated !== length) {
    throw new Error(`table-pack allocation failed: ${allocated}/${length}`);
  }
  tableLength = length;
  return allocated;
}

export function loadTablePackChunk(offset, chunk) {
  return copyChunk(
    engine.doom_tables_ref(),
    tableLength,
    offset,
    chunk,
    'table pack',
  );
}

export function initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map) {
  const tic = engine.doom_initialize(
    activePlayers,
    deathmatch,
    skill,
    episode,
    map,
  );
  if (tic !== 0) {
    throw new Error(`wasm2js initialization returned tic ${tic}`);
  }
  canonicalLength = 0;
  return tic;
}

export function stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands) {
  if (!(commands instanceof Uint8Array)
      || commands.byteLength !== FRAME_COMMAND_BYTES) {
    throw new Error(`command vector length mismatch: ${commands?.byteLength}`);
  }
  byteArray(
    engine.doom_command_ref(),
    FRAME_COMMAND_BYTES,
    'command vector',
  ).set(commands);
  const tic = engine.doom_step_authority(activePlayers, membershipMask);
  if (tic < 1) {
    throw new Error(`wasm2js authority step failed: ${tic}`);
  }
  canonicalLength = 0;
  return tic;
}

export function canonicalStateLength() {
  const length = engine.doom_canonical_length();
  if (!Number.isInteger(length) || length <= 0) {
    throw new Error(`canonical state length is invalid: ${length}`);
  }
  canonicalLength = length;
  return length;
}

export function canonicalStateChunk(offset, length) {
  const total = canonicalLength > 0
    ? canonicalLength
    : canonicalStateLength();
  if (!Number.isInteger(offset)
      || !Number.isInteger(length)
      || offset < 0
      || length < 1
      || offset + length > total
      || length > 32767) {
    throw new Error(`canonical chunk outside state: ${offset}/${length}/${total}`);
  }
  return Uint8Array.from(
    byteArray(engine.doom_canonical_ref(), total, 'canonical state')
      .subarray(offset, offset + length),
  );
}

export function loweringStatus() {
  const values = [
    engine.doom_i64_constant_high(),
    engine.doom_i64_field_high(),
    engine.doom_i64_field_copy_high(),
    engine.doom_i64_array_high(),
    engine.doom_i64_call_high(),
    engine.doom_i64_flag_or_high(),
  ];
  const expected = [15, 15, 23, 7, 15, 15];
  if (values.some((value, index) => value !== expected[index])) {
    throw new Error(`wasm2js i64 lowering mismatch: ${values.join(',')}`);
  }
  return `i64=exact|values=${values.join(',')}`;
}

export function memoryStatus() {
  return `linear_memory_bytes=${engine.memory.buffer.byteLength}`;
}

export function release() {
  const result = engine.doom_release();
  iwadLength = 0;
  tableLength = 0;
  canonicalLength = 0;
  if (result !== 0) {
    throw new Error(`wasm2js release failed: ${result}`);
  }
}
