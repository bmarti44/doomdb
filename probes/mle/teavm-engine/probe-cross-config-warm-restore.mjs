import fs from 'node:fs';
import {
  allocateCheckpoint,
  allocateIwad,
  allocateTablePack,
  canonicalState,
  checkpointChunk,
  checkpointLength,
  initializeMultiplayerGame,
  loadCheckpointChunk,
  loadIwadChunk,
  loadTablePackChunk,
  release,
  restoreCheckpoint,
} from './target/javascript/doom-mle-simulation-engine-headless.js';

const [iwadPath, tablePackPath] = process.argv.slice(2);
if (!iwadPath || !tablePackPath) {
  throw new Error(
    'usage: node probe-cross-config-warm-restore.mjs IWAD CANONICAL_TABLE_PACK',
  );
}

const iwad = fs.readFileSync(iwadPath);
const tables = fs.readFileSync(tablePackPath);
const chunkBytes = 1024 * 1024;

function transfer(bytes, allocate, load, label) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation mismatch`);
  }
  for (let offset = 0; offset < bytes.length; offset += chunkBytes) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + chunkBytes));
    if (load(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} transfer mismatch at ${offset}`);
    }
  }
}

function initialize(players, deathmatch, skill, episode, map) {
  transfer(iwad, allocateIwad, loadIwadChunk, 'IWAD');
  transfer(tables, allocateTablePack, loadTablePackChunk, 'table pack');
  initializeMultiplayerGame(players, deathmatch, skill, episode, map);
}

function saveCheckpoint() {
  const bytes = new Uint8Array(checkpointLength());
  for (let offset = 0; offset < bytes.length; offset += 32767) {
    const chunk = checkpointChunk(offset, Math.min(32767, bytes.length - offset));
    bytes.set(chunk, offset);
  }
  return bytes;
}

function restore(bytes) {
  if (allocateCheckpoint(bytes.length) !== bytes.length) {
    throw new Error('checkpoint allocation mismatch');
  }
  for (let offset = 0; offset < bytes.length; offset += 32767) {
    const chunk = bytes.subarray(offset, Math.min(bytes.length, offset + 32767));
    if (loadCheckpointChunk(offset, chunk) !== offset + chunk.length) {
      throw new Error(`checkpoint transfer mismatch at ${offset}`);
    }
  }
  const status = restoreCheckpoint(0);
  if (!status.startsWith('state=restored|gametic=0|')) {
    throw new Error(`checkpoint restore failed: ${status}`);
  }
}

for (const target of [
  {players: 2, deathmatch: 0, skill: 2, episode: 1, map: 1},
  {players: 2, deathmatch: 1, skill: 4, episode: 1, map: 1},
]) {
  initialize(
    target.players, target.deathmatch, target.skill, target.episode, target.map,
  );
  const expected = canonicalState();
  const checkpoint = saveCheckpoint();
  release();

  // This is the deploy-time pool configuration. The current checkpoint loader
  // validates map-sized arrays before InitNew, so the pool is deliberately
  // E1M1-scoped. A successful restore proves it can retarget skill and mode.
  initialize(2, 0, 3, 1, 1);
  restore(checkpoint);
  const actual = canonicalState();
  if (actual !== expected) {
    throw new Error(`cross-config restore divergence: ${JSON.stringify({
      target, expected, actual,
    })}`);
  }
  process.stdout.write(
    `PMLE_CROSS_CONFIG_WARM_RESTORE|PASS|players=${target.players}`
      + `|deathmatch=${target.deathmatch}|skill=${target.skill}`
      + `|episode=${target.episode}|map=${target.map}`
      + `|checkpoint_bytes=${checkpoint.length}\n`,
  );
  release();
}
