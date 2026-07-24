#!/usr/bin/env node
import fs from 'node:fs';
import inspector from 'node:inspector';
import {createHash} from 'node:crypto';

const here = new URL('./', import.meta.url);
const modulePath = process.env.DOOMDB_MLE_CHECKPOINT_MODULE
  ?? '../../../client/dist/play/doom-mle-authority-103e15e913b3.js';
const iwadPath = process.env.DOOMDB_MLE_CHECKPOINT_IWAD
  ?? '../../../client/dist/play/freedoom1-7323bcc168c5.bin';
const tablePath = process.env.DOOMDB_MLE_CHECKPOINT_TABLES
  ?? '../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin';
const profilePath = process.env.DOOMDB_MLE_CHECKPOINT_PROFILE;
const checkpointOutputPath = process.env.DOOMDB_MLE_CHECKPOINT_BYTES;
const engine = await import(new URL(modulePath, here));
const iwad = fs.readFileSync(new URL(iwadPath, here));
const tables = fs.readFileSync(new URL(tablePath, here));

function load(bytes, allocate, write) {
  if (allocate(bytes.length) !== bytes.length) throw new Error('allocation mismatch');
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 1024 * 1024));
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`short load at ${offset}`);
    }
  }
}

load(iwad, engine.allocateIwad, engine.loadIwadChunk);
load(tables, engine.allocateTablePack, engine.loadTablePackChunk);
engine.initializeMultiplayerGame(2, 0, 3, 1, 1);
const neutral = new Uint8Array(32);
for (let tic = 1; tic <= 32; tic++) {
  if (engine.stepMultiplayerAuthoritative(2, 3, neutral) !== tic) {
    throw new Error(`frontier mismatch at ${tic}`);
  }
}

let session;
const post = (method, params = {}) => new Promise((resolve, reject) =>
  session.post(method, params, (error, result) =>
    error === null ? resolve(result) : reject(error)));
if (profilePath !== undefined) {
  session = new inspector.Session();
  session.connect();
  await post('Profiler.enable');
  await post('Profiler.start');
}
const started = performance.now();
const bytes = engine.checkpointLength();
const firstMs = performance.now() - started;
const checkpointHash = createHash('sha256');
const checkpointMaterial = checkpointOutputPath === undefined
  ? null : Buffer.alloc(bytes);
for (let offset = 0; offset < bytes; offset += 32767) {
  const chunk = Buffer.from(engine.checkpointChunk(
    offset, Math.min(32767, bytes - offset)));
  checkpointHash.update(chunk);
  if (checkpointMaterial !== null) chunk.copy(checkpointMaterial, offset);
}
const checkpointSha256 = checkpointHash.digest('hex');
if (checkpointMaterial !== null) fs.writeFileSync(checkpointOutputPath, checkpointMaterial);
let profile;
if (profilePath !== undefined) {
  ({profile} = await post('Profiler.stop'));
  session.disconnect();
  fs.writeFileSync(profilePath, JSON.stringify(profile));
}
const repeated = performance.now();
const repeatedBytes = engine.checkpointLength();
const repeatedMs = performance.now() - repeated;
if (repeatedBytes !== bytes) throw new Error('checkpoint length drift');
process.stdout.write(`PMLE_NODE_CHECKPOINT|PASS|tic=32|bytes=${bytes}`
  + `|first_ms=${firstMs.toFixed(3)}|repeated_ms=${repeatedMs.toFixed(3)}`
  + `|sha256=${checkpointSha256}`
  + `${profilePath === undefined ? '' : `|profile=${profilePath}`}\n`);
engine.release();
