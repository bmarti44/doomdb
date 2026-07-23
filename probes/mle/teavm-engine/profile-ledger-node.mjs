#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import inspector from 'node:inspector';
import v8 from 'node:v8';
const modulePath = process.env.DOOMDB_MLE_PROFILE_MODULE
  ?? './target/javascript/doom-mle-simulation-engine-headless.js';
const {
  allocateIwad, allocateTablePack, initialize, loadIwadChunk,
  loadTablePackChunk, release, stepCommandBare,
} = await import(modulePath);

const project = new URL('./', import.meta.url);
const routePath = new URL('../../../artifacts/t8.1-live/mocha-e1m1-skill3-route.json', project);
const iwadPath = new URL('target/iwad-smoke/freedoom1.wad', project);
const tablePath = new URL('target/canonical-runtime-v2.bin', project);
const profilePath = process.argv[2] ?? '/tmp/doom-mle-ledger.cpuprofile';
const route = JSON.parse(fs.readFileSync(routePath));
const iwad = fs.readFileSync(iwadPath), tables = fs.readFileSync(tablePath);
assert.equal(route.commandCount, 13272);

function load(allocate, append, bytes) {
  allocate(bytes.length);
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 1024 * 1024));
    assert.equal(append(offset, chunk), offset + chunk.length);
  }
}

let turnHeld = 0;
function vector(command) {
  const forward = Math.abs(command.forward) > 1 ? command.forward
    : command.forward * (command.run ? 50 : 25);
  const side = Math.abs(command.strafe) > 1 ? command.strafe
    : command.strafe * (command.run ? 40 : 24);
  const mouse = Math.abs(command.turn) > 1;
  if (command.turn === 0 || mouse) turnHeld = 0; else turnHeld += 1;
  const magnitude = mouse ? Math.abs(command.turn) * 256
    : turnHeld < 6 ? 320 : command.run ? 1280 : 640;
  const turn = command.turn === 0 ? 0 : -Math.sign(command.turn) * magnitude;
  let buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0)
    | (command.weapon > 0 ? 4 | ((command.weapon - 1) << 3) : 0);
  if (command.pause) buttons = 129;
  const consistency = (command.automap ? 2 : 0)
    | (command.menu !== 'NONE' ? 4 : 0) | (command.cheat ? 8 : 0);
  return [forward, side, turn, consistency, buttons];
}

const vectors = route.runs.flatMap(run => Array.from(
  {length: run.repeat}, () => vector(run.command)));
load(allocateIwad, loadIwadChunk, iwad);
load(allocateTablePack, loadTablePackChunk, tables);
initialize();

const session = new inspector.Session();session.connect();
const post = (method, params = {}) => new Promise((resolve, reject) =>
  session.post(method, params, (error, result) => error ? reject(error) : resolve(result)));
await post('Profiler.enable');await post('Profiler.start');
const heapBefore = v8.getHeapStatistics();const started = performance.now();
for (let index = 0; index < vectors.length; index += 1) {
  const command = vectors[index];
  assert.equal(stepCommandBare(...command), index + 1);
}
const elapsedMs = performance.now() - started;
const heapAfter = v8.getHeapStatistics();
const {profile} = await post('Profiler.stop');session.disconnect();
fs.writeFileSync(profilePath, JSON.stringify(profile));release();
process.stdout.write(`PMLE_NODE_LEDGER_PROFILE|PASS|tics=${vectors.length}`
  + `|elapsed_ms=${elapsedMs.toFixed(3)}|tps=${(vectors.length * 1000 / elapsedMs).toFixed(3)}`
  + `|used_heap_before=${heapBefore.used_heap_size}|used_heap_after=${heapAfter.used_heap_size}`
  + `|profile=${profilePath}\n`);
