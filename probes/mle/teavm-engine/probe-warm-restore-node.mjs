import fs from 'node:fs';

const here = new URL('./', import.meta.url);
const modulePath = process.env.DOOMDB_MLE_WARM_RESTORE_MODULE
  ?? './target/javascript/doom-mle-simulation-engine-headless.js';
const engine = await import(new URL(modulePath, here));
const iwad = fs.readFileSync(new URL(
  '../../../client/dist/play/freedoom1-7323bcc168c5.bin', here));
const tables = fs.readFileSync(new URL(
  '../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin', here));
const neutral = new Uint8Array(32);

function transfer(bytes, allocate, write) {
  if (allocate(bytes.length) !== bytes.length) throw new Error('allocation mismatch');
  for (let offset = 0; offset < bytes.length; offset += 32767) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 32767));
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`transfer mismatch at ${offset}`);
    }
  }
}

function initialize(deathmatch = 0) {
  transfer(iwad, engine.allocateIwad, engine.loadIwadChunk);
  transfer(tables, engine.allocateTablePack, engine.loadTablePackChunk);
  const status = engine.initializeMultiplayerGame(2, deathmatch, 3, 1, 1);
  if (!status.startsWith('state=multiplayer-initialized|gametic=0|')) {
    throw new Error(`initialization failed: ${status}`);
  }
}

function checkpoint() {
  const bytes = new Uint8Array(engine.checkpointLength());
  for (let offset = 0; offset < bytes.length; offset += 32767) {
    bytes.set(engine.checkpointChunk(
      offset, Math.min(32767, bytes.length - offset)), offset);
  }
  return bytes;
}

function loadCheckpoint(bytes) {
  transfer(bytes, engine.allocateCheckpoint, engine.loadCheckpointChunk);
}

initialize();
for (let tic = 1; tic <= 32; tic++) {
  if (engine.stepMultiplayerAuthoritative(2, 3, neutral) !== tic) {
    throw new Error(`source frontier mismatch at ${tic}`);
  }
}
const bytes = checkpoint();
const expected = [];
for (let tic = 33; tic <= 96; tic++) {
  engine.stepMultiplayerAuthoritative(2, 3, neutral);
  expected.push(engine.canonicalState());
}
engine.release();

initialize();
loadCheckpoint(bytes);
const wrongTic = engine.restoreCheckpointWarm(31);
if (!wrongTic.startsWith('error|')) {
  throw new Error(`warm restore accepted wrong frontier: ${wrongTic}`);
}
loadCheckpoint(bytes);
const restored = engine.restoreCheckpointWarm(32);
if (!restored.startsWith('state=restored|gametic=32|')) {
  throw new Error(`warm restore failed: ${restored}`);
}
for (let tic = 33; tic <= 96; tic++) {
  engine.stepMultiplayerAuthoritative(2, 3, neutral);
  const actual = engine.canonicalState();
  if (actual !== expected[tic - 33]) {
    throw new Error(`warm restore continuation divergence at tic ${tic}`);
  }
}
engine.release();

initialize(1);
loadCheckpoint(bytes);
const wrongMode = engine.restoreCheckpointWarm(32);
if (!wrongMode.startsWith('error|')
    || !wrongMode.includes('warm checkpoint origin does not match')) {
  throw new Error(`warm restore accepted wrong mode: ${wrongMode}`);
}
engine.release();

process.stdout.write('PMLE_WARM_RESTORE_NODE|PASS|checkpoint_tic=32'
  + `|continuation_tics=${expected.length}|checkpoint_bytes=${bytes.length}`
  + '|wrong_tic=reject|wrong_mode=reject\n');
