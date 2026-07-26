#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const here = new URL('./', import.meta.url);
const artifactPath = process.env.DOOMDB_WASM2JS_PRESENTATION
  ?? 'target/wasm/doom-wasm2js-presentation.o0.bundle.mjs';
const oraclePath = process.env.DOOMDB_WASM2JS_PRESENTATION_ORACLE
  ?? '../../../../artifacts/performance/pmle-presentation-decps/'
    + 'presentation-candidate-118c37717b36.js';
const iwadPath = '../../../../client/dist/play/freedoom1-7323bcc168c5.bin';
const tablePath =
  '../../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin';
const fixturePath = '../../../../tests/fixtures/'
  + 'mle-live-deathmatch-2026-07-23.json';
const tics = Number(process.env.DOOMDB_WASM2JS_FRAME_TICS ?? 100);
const resolve = value => new URL(value, here);

const [engine, oracle] = await Promise.all([
  import(resolve(artifactPath)),
  import(resolve(oraclePath)),
]);
const iwad = fs.readFileSync(resolve(iwadPath));
const tables = fs.readFileSync(resolve(tablePath));
const fixture = JSON.parse(fs.readFileSync(resolve(fixturePath), 'utf8'));

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function wasmArray(reference, expectedLength) {
  assert.ok(reference > 0, `invalid TeaVM array reference ${reference}`);
  assert.equal(engine.teavm_arrayLength(reference), expectedLength);
  return new Uint8Array(
    engine.memory.buffer,
    engine.teavm_byteArrayData(reference),
    expectedLength,
  );
}

function oracleLoad(bytes, allocate, write) {
  assert.equal(allocate(bytes.length), bytes.length);
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(
      offset,
      Math.min(bytes.length, offset + 1024 * 1024),
    );
    assert.equal(write(offset, chunk), offset + chunk.length);
  }
}

function compareFrame(tic, chain, unique) {
  assert.equal(engine.doom_render_player(0), 320 * 200);
  const actual = Uint8Array.from(
    wasmArray(engine.doom_frame_ref(), 320 * 200),
  );
  const expected = oracle.renderPlayerFrame(0);
  assert.equal(expected.length, 320 * 200);
  const actualSha = sha256(actual);
  const expectedSha = sha256(expected);
  assert.equal(actualSha, expectedSha, `frame mismatch at tic ${tic}`);
  unique.add(actualSha);
  return crypto.createHash('sha256')
    .update(chain)
    .update(Buffer.from(actualSha, 'hex'))
    .digest();
}

assert.equal(engine.doom_allocate_iwad(iwad.length), iwad.length);
wasmArray(engine.doom_iwad_ref(), iwad.length).set(iwad);
assert.equal(engine.doom_allocate_tables(tables.length), tables.length);
wasmArray(engine.doom_tables_ref(), tables.length).set(tables);
const initializeExport = process.env.DOOMDB_WASM2JS_AUTHORITY_INIT === '1'
  ? engine.doom_initialize
  : engine.doom_initialize_presentation;
const initializeResult = initializeExport(
  fixture.players,
  fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill,
  fixture.episode,
  fixture.map,
);
if (initializeResult !== 0) {
  const failureLength = engine.doom_init_failure_length();
  const failure = failureLength > 0
    ? Buffer.from(wasmArray(engine.doom_init_failure_ref(), failureLength))
        .toString('latin1')
    : '';
  throw new Error(`presentation initialize failed: ${initializeResult}: ${failure}`);
}

oracleLoad(iwad, oracle.allocateIwad, oracle.loadIwadChunk);
oracleLoad(tables, oracle.allocateTablePack, oracle.loadTablePackChunk);
assert.match(oracle.initializeMultiplayerGame(
  fixture.players,
  fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill,
  fixture.episode,
  fixture.map,
), /state=multiplayer-initialized\|gametic=0\|/);

let chain = Buffer.alloc(32);
const unique = new Set();
let stepped = 0;
for (const run of fixture.runs) {
  const command = Uint8Array.from(Buffer.from(run.command, 'hex'));
  assert.equal(command.length, 32);
  for (let repetition = 0; repetition < run.repeat && stepped < tics;
      repetition++) {
    // Rendering and canonical material can grow TeaVM linear memory.
    wasmArray(engine.doom_command_ref(), 32).set(command);
    assert.equal(engine.doom_step_authority(
      fixture.players,
      run.membership,
    ), stepped + 1);
    assert.equal(oracle.stepMultiplayerAuthoritative(
      fixture.players,
      run.membership,
      command,
    ), stepped + 1);
    stepped++;
    chain = compareFrame(stepped, chain, unique);
  }
  if (stepped === tics) break;
}
assert.equal(stepped, tics);
process.stdout.write(
  `PASS PMLE-WASM2JS-NODE-FRAME-PARITY tics=${stepped}`
  + ` frames=${stepped} unique_frames=${unique.size}`
  + ` frame_chain_sha256=${chain.toString('hex')}`
  + ` bundle_sha256=${sha256(fs.readFileSync(resolve(artifactPath)))}`
  + ` oracle_sha256=${sha256(fs.readFileSync(resolve(oraclePath)))}\n`,
);
