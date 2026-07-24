#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const here = new URL('./', import.meta.url);
const artifactPath = process.env.DOOMDB_WASM2JS_ARTIFACT
  ?? 'target/wasm/doom-wasm2js-authority.bundle.mjs';
const iwadPath = process.env.DOOMDB_WASM2JS_IWAD
  ?? '../../../../client/dist/play/freedoom1-7323bcc168c5.bin';
const tablePath = process.env.DOOMDB_WASM2JS_TABLES
  ?? '../../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin';
const fixturePath = process.env.DOOMDB_WASM2JS_FIXTURE
  ?? '../../../../tests/fixtures/mle-live-deathmatch-2026-07-23.json';
const tics = Number(process.env.DOOMDB_WASM2JS_TICS ?? 100);

const resolve = value => new URL(value, here);
const engine = await import(resolve(artifactPath));
const iwad = fs.readFileSync(resolve(iwadPath));
const tables = fs.readFileSync(resolve(tablePath));
const fixture = JSON.parse(fs.readFileSync(resolve(fixturePath), 'utf8'));

function byteArrayView(reference, expectedLength) {
  assert.ok(reference > 0, `invalid TeaVM array reference ${reference}`);
  assert.equal(engine.teavm_arrayLength(reference), expectedLength);
  const offset = engine.teavm_byteArrayData(reference);
  return new Uint8Array(engine.memory.buffer, offset, expectedLength);
}

assert.equal(engine.doom_allocate_iwad(iwad.length), iwad.length);
byteArrayView(engine.doom_iwad_ref(), iwad.length).set(iwad);
assert.equal(engine.doom_allocate_tables(tables.length), tables.length);
byteArrayView(engine.doom_tables_ref(), tables.length).set(tables);

const initStarted = performance.now();
assert.equal(engine.doom_initialize(
  fixture.players, fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill, fixture.episode, fixture.map), 0);
const initMs = performance.now() - initStarted;

const commandRef = engine.doom_command_ref();
const commandView = byteArrayView(commandRef, 32);
const samples = [];
let stepped = 0;
for (const run of fixture.runs) {
  const command = Uint8Array.from(Buffer.from(run.command, 'hex'));
  assert.equal(command.length, 32);
  for (let repetition = 0; repetition < run.repeat && stepped < tics;
      repetition++) {
    commandView.set(command);
    const started = performance.now();
    assert.equal(engine.doom_step_authority(
      fixture.players, run.membership), stepped + 1);
    samples.push(performance.now() - started);
    stepped++;
  }
  if (stepped === tics) break;
}
assert.equal(stepped, tics);

const canonicalLength = engine.doom_canonical_length();
assert.ok(canonicalLength > 0, `invalid canonical length ${canonicalLength}`);
const canonical = Buffer.from(byteArrayView(
  engine.doom_canonical_ref(), canonicalLength));
const canonicalSha = crypto.createHash('sha256').update(canonical).digest('hex');
const sorted = samples.toSorted((left, right) => left - right);
const percentile = fraction =>
  sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];

process.stdout.write('PASS PMLE-WASM2JS-NODE-SMOKE'
  + ` tics=${tics}`
  + ` init_ms=${initMs.toFixed(3)}`
  + ` p50_ms=${percentile(.5).toFixed(3)}`
  + ` p95_ms=${percentile(.95).toFixed(3)}`
  + ` max_ms=${Math.max(...samples).toFixed(3)}`
  + ` canonical_bytes=${canonicalLength}`
  + ` canonical_sha256=${canonicalSha}\n`);
assert.equal(engine.doom_release(), 0);
