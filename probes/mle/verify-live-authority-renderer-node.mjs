#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const authorityPath = process.argv[2] ?? path.join(
  root,
  'probes/mle/teavm-engine/target/javascript/'
    + 'doom-mle-presentation-engine-headless.js',
);
const rendererPath = process.argv[3] ?? path.join(
  root,
  'probes/mle/free-live-teavm/target/javascript/'
    + 'doom-mle-free-live-renderer.js',
);
const iwadPath = process.argv[4] ?? path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad',
);
const tablePath = process.argv[5] ?? path.join(
  root, 'probes/mle/teavm-engine/target/canonical-runtime-v2.bin',
);
const rendererPackPath = process.argv[6] ?? path.join(
  root, 'probes/mle/target/free-live-renderer/free-live-render.pack',
);

const authority = await import(pathToFileURL(authorityPath).href);
const renderer = await import(pathToFileURL(rendererPath).href);
const iwad = fs.readFileSync(iwadPath);
const tables = fs.readFileSync(tablePath);
const rendererPack = fs.readFileSync(rendererPackPath);

function load(allocate, write, bytes) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`allocation rejected ${bytes.length}`);
  }
  for (let offset = 0; offset < bytes.length; offset += 16_000) {
    const chunk = bytes.subarray(offset, offset + 16_000);
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`short load at ${offset}`);
    }
  }
}

load(authority.allocateIwad, authority.loadIwadChunk, iwad);
load(authority.allocateTablePack, authority.loadTablePackChunk, tables);
const state = authority.initializeMultiplayerGame(2, 0, 3, 1, 1);
if (!state.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`authority initialization failed: ${state}`);
}
load(renderer.allocatePack, renderer.loadPackChunk, rendererPack);
if (renderer.finalizePack() !== rendererPack.length) {
  throw new Error('renderer pack finalize mismatch');
}

function commands(tic) {
  const result = new Uint8Array(32);
  result[0] = tic % 7 === 0 ? 25 : 0;
  result[1] = tic % 11 === 0 ? 0xe8 : 0;
  result[2] = tic % 5 === 0 ? 0xfd : 0;
  result[3] = tic % 5 === 0 ? 0x80 : 0;
  result[8] = tic % 9 === 0 ? 18 : 0;
  result[9] = tic % 13 === 0 ? 24 : 0;
  result[10] = tic % 6 === 0 ? 0x02 : 0;
  result[11] = tic % 6 === 0 ? 0x80 : 0;
  return result;
}

const snapshots = [new Set(), new Set()];
const renderChecksums = [new Set(), new Set()];
for (let tic = 1; tic <= 96; tic += 1) {
  if (authority.stepMultiplayerAuthoritative(2, 3, commands(tic)) !== tic) {
    throw new Error(`authority frontier mismatch at ${tic}`);
  }
  for (let player = 0; player < 2; player += 1) {
    const snapshot = authority.presentationPlayerSnapshot(player);
    if (!(snapshot instanceof Uint8Array) || snapshot.byteLength !== 32) {
      throw new Error(`invalid authority snapshot ${tic}/${player}`);
    }
    snapshots[player].add(Buffer.from(snapshot).toString('hex'));
    renderChecksums[player].add(
      renderer.renderPlayerSnapshotGeometry(snapshot),
    );
  }
}
authority.release();

if (snapshots.some(set => set.size < 50)
    || renderChecksums.some(set => set.size < 25)) {
  throw new Error(
    `insufficient live variation snapshots=${snapshots.map(set => set.size)}`
      + ` renders=${renderChecksums.map(set => set.size)}`,
  );
}

process.stdout.write(
  'PMLE_LIVE_AUTHORITY_RENDERER_NODE|PASS|tics=96|players=2'
  + `|snapshot_unique=${snapshots.map(set => set.size).join(',')}`
  + `|render_checksum_unique=${renderChecksums.map(set => set.size).join(',')}`
  + '|snapshot_bytes=32|authority=MOCHA_TEAVM'
  + '|renderer=SPECIALIZED_TEAVM_MLE|client=NO_RENDER_LOGIC\n',
);
