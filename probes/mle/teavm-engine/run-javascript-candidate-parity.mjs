#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const here = new URL('./', import.meta.url);
const candidatePath = process.env.DOOMDB_MLE_CANDIDATE
  ?? 'target/javascript/doom-mle-simulation-engine-headless.js';
const oraclePath = process.env.DOOMDB_MLE_ORACLE
  ?? '../../../client/dist/play/doom-mle-authority-5ec18cbe4cff.js';
const iwadPath = process.env.DOOMDB_MLE_PARITY_IWAD
  ?? '../../../client/dist/play/freedoom1-7323bcc168c5.bin';
const tablePath = process.env.DOOMDB_MLE_PARITY_TABLES
  ?? '../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin';
const fixturePath = process.env.DOOMDB_MLE_PARITY_FIXTURE
  ?? '../../../tests/fixtures/mle-live-deathmatch-2026-07-23.json';
const resolve = value => new URL(value, here);

const [candidate, oracle] = await Promise.all([
  import(resolve(candidatePath)),
  import(resolve(oraclePath)),
]);
const iwad = fs.readFileSync(resolve(iwadPath));
const tables = fs.readFileSync(resolve(tablePath));
const fixtureBytes = fs.readFileSync(resolve(fixturePath));
const fixture = JSON.parse(fixtureBytes);

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function load(engine, bytes, allocate, write) {
  assert.equal(engine[allocate](bytes.length), bytes.length);
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset, Math.min(
      bytes.length, offset + 1024 * 1024));
    assert.equal(engine[write](offset, chunk), offset + chunk.length);
  }
}

function canonical(engine) {
  const length = engine.canonicalStateLength();
  assert.ok(length > 0, `invalid canonical length ${length}`);
  const bytes = new Uint8Array(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const chunk = engine.canonicalStateChunk(
      offset, Math.min(32767, length - offset));
    bytes.set(chunk, offset);
  }
  return bytes;
}

function compareCanonical(tic) {
  const actual = canonical(candidate);
  const expected = canonical(oracle);
  assert.equal(actual.length, expected.length,
    `tic ${tic} canonical length mismatch`);
  if (!actual.every((value, index) => value === expected[index])) {
    const first = actual.findIndex((value, index) => value !== expected[index]);
    throw new Error(`tic ${tic} canonical mismatch at byte ${first}: `
      + `candidate=${actual[first]} oracle=${expected[first]} `
      + `candidate_sha256=${sha256(actual)} oracle_sha256=${sha256(expected)}`);
  }
  return actual;
}

for (const engine of [candidate, oracle]) {
  load(engine, iwad, 'allocateIwad', 'loadIwadChunk');
  load(engine, tables, 'allocateTablePack', 'loadTablePackChunk');
  assert.match(engine.initializeMultiplayerGame(
    fixture.players, fixture.mode === 'DEATHMATCH' ? 1 : 0,
    fixture.skill, fixture.episode, fixture.map),
  /state=multiplayer-initialized\|gametic=0\|/);
}

compareCanonical(0);
let finalCanonical;
let stepped = 0;
for (const run of fixture.runs) {
  const commands = Uint8Array.from(Buffer.from(run.command, 'hex'));
  assert.equal(commands.length, 32);
  for (let repetition = 0; repetition < run.repeat; repetition++) {
    stepped++;
    assert.equal(candidate.stepMultiplayerAuthoritative(
      fixture.players, run.membership, commands), stepped);
    assert.equal(oracle.stepMultiplayerAuthoritative(
      fixture.players, run.membership, commands), stepped);
    finalCanonical = compareCanonical(stepped);
  }
}
assert.equal(stepped, fixture.tics);

const candidateBytes = fs.readFileSync(resolve(candidatePath));
const oracleBytes = fs.readFileSync(resolve(oraclePath));
process.stdout.write('PASS PMLE-JAVASCRIPT-CANDIDATE-PARITY'
  + ` tics=${stepped}`
  + ` checkpoints=${stepped + 1}`
  + ` canonical_bytes=${finalCanonical.length}`
  + ` canonical_sha256=${sha256(finalCanonical)}`
  + ` fixture_sha256=${sha256(fixtureBytes)}`
  + ` stream_sha256=${fixture.expandedSha256}`
  + ` candidate_sha256=${sha256(candidateBytes)}`
  + ` oracle_sha256=${sha256(oracleBytes)}\n`);

candidate.release();
oracle.release();
