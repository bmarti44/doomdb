import assert from 'node:assert/strict';
import fs from 'node:fs';

const sourcePath = new URL('./mle-rank-wrapper.mjs', import.meta.url);
const source = fs.readFileSync(sourcePath, 'utf8');
const importLine = "import * as engine from 'doom_wasm2js_engine';";
assert.equal(source.split(importLine).length - 1, 1);

const memory = {buffer: new ArrayBuffer(256)};
const arrays = new Map();
let nextReference = 1;
let nextOffset = 16;
let iwadReference = 0;
let tableReference = 0;
let commandReference = 0;
let canonicalReference = 0;
let tic = 0;

function allocate(length) {
  const reference = nextReference++;
  const offset = nextOffset;
  nextOffset += length + 8;
  if (nextOffset > memory.buffer.byteLength) {
    const grown = new ArrayBuffer(memory.buffer.byteLength * 2 + nextOffset);
    new Uint8Array(grown).set(new Uint8Array(memory.buffer));
    memory.buffer = grown;
  }
  arrays.set(reference, {length, offset});
  return reference;
}

const engine = {
  memory,
  teavm_arrayLength(reference) {
    return arrays.get(reference)?.length ?? -1;
  },
  teavm_byteArrayData(reference) {
    return arrays.get(reference)?.offset ?? -1;
  },
  doom_allocate_iwad(length) {
    iwadReference = allocate(length);
    return length;
  },
  doom_iwad_ref() {
    return iwadReference;
  },
  doom_allocate_tables(length) {
    tableReference = allocate(length);
    return length;
  },
  doom_tables_ref() {
    return tableReference;
  },
  doom_initialize() {
    commandReference = allocate(32);
    tic = 0;
    return tic;
  },
  doom_command_ref() {
    return commandReference;
  },
  doom_step_authority() {
    return ++tic;
  },
  doom_canonical_length() {
    const bytes = Uint8Array.of(tic, 2, 3, 4, 5);
    canonicalReference = allocate(bytes.length);
    const row = arrays.get(canonicalReference);
    new Uint8Array(memory.buffer, row.offset, row.length).set(bytes);
    return bytes.length;
  },
  doom_canonical_ref() {
    return canonicalReference;
  },
  doom_i64_constant_high: () => 15,
  doom_i64_field_high: () => 15,
  doom_i64_field_copy_high: () => 23,
  doom_i64_array_high: () => 7,
  doom_i64_call_high: () => 15,
  doom_i64_flag_or_high: () => 15,
  doom_release() {
    return 0;
  },
};
globalThis.__doomdbWasm2jsMock = engine;
const rewritten = source.replace(
  importLine,
  'const engine = globalThis.__doomdbWasm2jsMock;',
);
const wrapper = await import(
  `data:text/javascript;base64,${Buffer.from(rewritten).toString('base64')}`,
);

assert.equal(wrapper.allocateIwad(40), 40);
assert.equal(wrapper.loadIwadChunk(0, Uint8Array.of(1, 2, 3)), 3);
const originalBuffer = memory.buffer;
assert.equal(wrapper.allocateTablePack(300), 300);
assert.notEqual(memory.buffer, originalBuffer, 'mock did not grow linear memory');
assert.equal(wrapper.loadIwadChunk(3, Uint8Array.of(4, 5)), 5);
const iwad = arrays.get(iwadReference);
assert.deepEqual(
  [...new Uint8Array(memory.buffer, iwad.offset, 5)],
  [1, 2, 3, 4, 5],
  'IWAD view was not recreated after memory growth',
);
assert.equal(wrapper.loadTablePackChunk(0, Uint8Array.of(9, 8)), 2);
assert.equal(wrapper.initializeMultiplayerGame(2, 1, 3, 1, 1), 0);
const commands = Uint8Array.from({length: 32}, (_, index) => index);
assert.equal(wrapper.stepMultiplayerAuthoritative(2, 3, commands), 1);
const command = arrays.get(commandReference);
assert.deepEqual(
  [...new Uint8Array(memory.buffer, command.offset, 32)],
  [...commands],
);
assert.equal(wrapper.canonicalStateLength(), 5);
assert.deepEqual([...wrapper.canonicalStateChunk(1, 3)], [2, 3, 4]);
assert.equal(wrapper.loweringStatus(), 'i64=exact|values=15,15,23,7,15,15');
assert.match(wrapper.memoryStatus(), /^linear_memory_bytes=[1-9][0-9]*$/);
assert.throws(
  () => wrapper.loadIwadChunk(39, Uint8Array.of(1, 2)),
  /outside its allocated byte array/,
);
assert.throws(
  () => wrapper.stepMultiplayerAuthoritative(2, 3, new Uint8Array(31)),
  /command vector length mismatch/,
);
wrapper.release();
delete globalThis.__doomdbWasm2jsMock;

console.log('PASS PMLE-WASM2JS-MLE-WRAPPER-UNIT');
