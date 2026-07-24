#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const here = new URL('./', import.meta.url);
const artifactPath = process.env.DOOMDB_WASM2JS_ARTIFACT
  ?? 'target/wasm/doom-wasm2js-authority.bundle.mjs';
const oraclePath = process.env.DOOMDB_WASM2JS_ORACLE
  ?? '../../../../client/dist/play/doom-mle-authority-e485b9418e58.js';
const iwadPath = process.env.DOOMDB_WASM2JS_IWAD
  ?? '../../../../client/dist/play/freedoom1-7323bcc168c5.bin';
const tablePath = process.env.DOOMDB_WASM2JS_TABLES
  ?? '../../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin';
const fixturePath = process.env.DOOMDB_WASM2JS_FIXTURE
  ?? '../../../../tests/fixtures/mle-live-deathmatch-2026-07-23.json';
const tics = Number(process.env.DOOMDB_WASM2JS_TICS ?? 100);
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
  return new Uint8Array(engine.memory.buffer,
    engine.teavm_byteArrayData(reference), expectedLength);
}

function wasmCanonical() {
  const length = engine.doom_canonical_length();
  assert.ok(length > 0, `invalid wasm2js canonical length ${length}`);
  return Uint8Array.from(wasmArray(engine.doom_canonical_ref(), length));
}

function oracleLoad(bytes, allocate, write) {
  assert.equal(allocate(bytes.length), bytes.length);
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset, Math.min(
      bytes.length, offset + 1024 * 1024));
    assert.equal(write(offset, chunk), offset + chunk.length);
  }
}

function oracleCanonical() {
  const length = oracle.canonicalStateLength();
  assert.ok(length > 0, `invalid oracle canonical length ${length}`);
  const bytes = new Uint8Array(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const chunk = oracle.canonicalStateChunk(
      offset, Math.min(32767, length - offset));
    bytes.set(chunk, offset);
  }
  return bytes;
}

function compareCanonical(tic) {
  const actual = wasmCanonical();
  const expected = oracleCanonical();
  if (actual.length !== expected.length) {
    throw new Error(`tic ${tic} canonical length mismatch: `
      + `wasm2js=${actual.length} oracle=${expected.length}`);
  }
  const differences = [];
  const lastDifferences = [];
  let differenceCount = 0;
  for (let index = 0; index < actual.length; index++) {
    if (actual[index] !== expected[index]) {
      differenceCount++;
      if (differences.length < 16) {
        differences.push(`${index}:${actual[index]}!=${expected[index]}`);
      }
      lastDifferences.push(`${index}:${actual[index]}!=${expected[index]}`);
      if (lastDifferences.length > 16) lastDifferences.shift();
    }
  }
  if (differenceCount !== 0) {
    throw new Error(`tic ${tic} canonical mismatch: differences=`
      + `${differenceCount} first=${differences.join(',')}`
      + ` last=${lastDifferences.join(',')}`
      + ` wasm2js_sha256=${sha256(actual)} oracle_sha256=${sha256(expected)}`);
  }
  return actual;
}

assert.equal(engine.doom_allocate_iwad(iwad.length), iwad.length);
wasmArray(engine.doom_iwad_ref(), iwad.length).set(iwad);
assert.equal(engine.doom_allocate_tables(tables.length), tables.length);
wasmArray(engine.doom_tables_ref(), tables.length).set(tables);
assert.equal(engine.doom_initialize(
  fixture.players, fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill, fixture.episode, fixture.map), 0);

oracleLoad(iwad, oracle.allocateIwad, oracle.loadIwadChunk);
oracleLoad(tables, oracle.allocateTablePack, oracle.loadTablePackChunk);
assert.match(oracle.initializeMultiplayerGame(
  fixture.players, fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill, fixture.episode, fixture.map),
/state=multiplayer-initialized\|gametic=0\|/);

compareCanonical(0);
const commandView = wasmArray(engine.doom_command_ref(), 32);
let canonical;
let stepped = 0;
for (const run of fixture.runs) {
  const command = Uint8Array.from(Buffer.from(run.command, 'hex'));
  assert.equal(command.length, 32);
  for (let repetition = 0; repetition < run.repeat && stepped < tics;
      repetition++) {
    commandView.set(command);
    assert.equal(engine.doom_step_authority(
      fixture.players, run.membership), stepped + 1);
    assert.equal(oracle.stepMultiplayerAuthoritative(
      fixture.players, run.membership, command), stepped + 1);
    stepped++;
    canonical = compareCanonical(stepped);
  }
  if (stepped === tics) break;
}
assert.equal(stepped, tics);

const fixtureBytes = fs.readFileSync(resolve(fixturePath));
const oracleBytes = fs.readFileSync(resolve(oraclePath));
process.stdout.write('PASS PMLE-WASM2JS-NODE-PARITY'
  + ` tics=${tics}`
  + ` checkpoints=${tics + 1}`
  + ` canonical_bytes=${canonical.length}`
  + ` canonical_sha256=${sha256(canonical)}`
  + ` fixture_sha256=${sha256(fixtureBytes)}`
  + ` stream_sha256=${fixture.expandedSha256}`
  + ` oracle_sha256=${sha256(oracleBytes)}\n`);

assert.equal(engine.doom_release(), 0);
oracle.release();
