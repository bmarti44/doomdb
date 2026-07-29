#!/usr/bin/env node

import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const authorityPath = path.join(
  root,
  'probes/mle/teavm-engine/target/javascript/'
    + 'doom-mle-presentation-engine-headless.js',
);
const baselinePath = path.join(
  root,
  'artifacts/performance/pmle-live-frame-authority/'
    + 'renderer-1f0bbaa10ce5.js',
);
const candidatePath = path.join(
  root,
  'probes/mle/free-live-teavm/target/javascript/'
    + 'doom-mle-free-live-unified-renderer.js',
);
const iwadPath = path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad',
);
const tablePath = path.join(
  root, 'probes/mle/teavm-engine/target/canonical-runtime-v2.bin',
);
const worldPackPath = path.join(
  root,
  'probes/mle/free-live-teavm/target/world-raster-pack/'
    + 'free-live-render.pack',
);
const compositorPackPath = path.join(
  root, 'probes/mle/target/free-live-renderer/free-live-render.pack',
);
const assetsPath = path.join(
  root, 'probes/mle/target/free-live-renderer/assets-v1',
);
const fixturePath = path.join(
  root, 'tests/fixtures/mle-live-deathmatch-2026-07-23.json',
);

for (const required of [
  authorityPath, baselinePath, candidatePath, iwadPath, tablePath,
  worldPackPath, compositorPackPath, fixturePath,
  path.join(assetsPath, 'wall_texture.bin'),
  path.join(assetsPath, 'flat.bin'),
  path.join(assetsPath, 'sprite_patch.bin'),
  path.join(assetsPath, 'ui_patch.bin'),
]) {
  if (!fs.existsSync(required)) {
    throw new Error(`required route-equivalence input is missing: ${required}`);
  }
}

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

function sha(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function initializeRenderer(renderer) {
  const worldPack = fs.readFileSync(worldPackPath);
  load(renderer.allocatePack, renderer.loadPackChunk, worldPack);
  if (renderer.finalizePack() !== worldPack.length) {
    throw new Error('world pack finalize mismatch');
  }
  for (const [name, allocate, write, finalize] of [
    ['wall_texture.bin', renderer.allocateWallTextures,
      renderer.loadWallTextureChunk, renderer.finalizeWallTextures],
    ['flat.bin', renderer.allocateFlatTextures,
      renderer.loadFlatTextureChunk, renderer.finalizeFlatTextures],
  ]) {
    const bytes = fs.readFileSync(path.join(assetsPath, name));
    load(allocate, write, bytes);
    if (finalize() !== bytes.length) {
      throw new Error(`${name} finalize mismatch`);
    }
  }
  const compositorPack = fs.readFileSync(compositorPackPath);
  load(
    renderer.allocateCompositorPack,
    renderer.loadCompositorPackChunk,
    compositorPack,
  );
  if (renderer.finalizeCompositorPack() !== compositorPack.length) {
    throw new Error('compositor pack finalize mismatch');
  }
  for (const [name, allocate, write, finalize] of [
    ['sprite_patch.bin', renderer.allocateCompositorSprites,
      renderer.loadCompositorSpriteChunk, renderer.finalizeCompositorSprites],
    ['ui_patch.bin', renderer.allocateCompositorUi,
      renderer.loadCompositorUiChunk, renderer.finalizeCompositorUi],
  ]) {
    const bytes = fs.readFileSync(path.join(assetsPath, name));
    load(allocate, write, bytes);
    if (finalize() !== bytes.length) {
      throw new Error(`${name} compositor finalize mismatch`);
    }
  }
  if (renderer.resetPresentationState() !== 9) {
    throw new Error('presentation-state reset mismatch');
  }
}

function render(renderer, worldSnapshot, compositorSnapshot) {
  renderer.loadCompactSnapshot(worldSnapshot);
  renderer.renderLoadedCompactFrameCoarse(worldSnapshot);
  renderer.composeWorldSpritesStage(compositorSnapshot);
  renderer.composeWeaponStage(compositorSnapshot);
  renderer.composeStatusStage(compositorSnapshot);
  const frame = renderer.frameNativeByRef();
  if (!(frame instanceof Uint8Array) || frame.byteLength !== 64_000) {
    throw new Error(`invalid composed frame: ${frame?.byteLength}`);
  }
  return frame;
}

const authority = await import(pathToFileURL(authorityPath).href);
const baseline = await import(
  `${pathToFileURL(baselinePath).href}?baseline=1`);
const candidate = await import(
  `${pathToFileURL(candidatePath).href}?candidate=1`);
load(
  authority.allocateIwad,
  authority.loadIwadChunk,
  fs.readFileSync(iwadPath),
);
load(
  authority.allocateTablePack,
  authority.loadTablePackChunk,
  fs.readFileSync(tablePath),
);
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
if (fixture.schema !== 1 || fixture.tics !== 5250
    || fixture.players !== 2 || fixture.mode !== 'DEATHMATCH') {
  throw new Error('accepted command-stream fixture contract mismatch');
}
const initialized = authority.initializeMultiplayerGame(
  fixture.players, 1, fixture.skill, fixture.episode, fixture.map);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`authority initialization failed: ${initialized}`);
}
initializeRenderer(baseline);
initializeRenderer(candidate);

let tic = 0;
let compared = 0;
const chain = createHash('sha256');
for (const run of fixture.runs) {
  const command = Uint8Array.from(Buffer.from(run.command, 'hex'));
  for (let repeat = 0; repeat < run.repeat; repeat += 1) {
    tic = authority.stepMultiplayerAuthoritative(
      fixture.players, run.membership, command,
    );
    const worldLength =
      authority.presentationWorldGeometryDeltaSnapshotLength(0);
    const worldSnapshot =
      authority.presentationWorldSnapshotNativeByRef().slice(0, worldLength);
    const compositorLength =
      authority.presentationCompositorSnapshotLength(0);
    const compositorSnapshot =
      authority.presentationWorldSnapshotNativeByRef()
        .slice(0, compositorLength);
    const before = render(baseline, worldSnapshot, compositorSnapshot);
    const after = render(candidate, worldSnapshot, compositorSnapshot);
    const beforeBuffer = Buffer.from(
      before.buffer, before.byteOffset, before.byteLength);
    const afterBuffer = Buffer.from(
      after.buffer, after.byteOffset, after.byteLength);
    if (!beforeBuffer.equals(afterBuffer)) {
      let firstDifference = -1;
      for (let offset = 0; offset < beforeBuffer.length; offset += 1) {
        if (beforeBuffer[offset] !== afterBuffer[offset]) {
          firstDifference = offset;
          break;
        }
      }
      throw new Error(
        `compact partial-depth frame mismatch at tic ${tic}`
          + ` offset ${firstDifference}:`
          + ` ${sha(beforeBuffer)}/${sha(afterBuffer)}`,
      );
    }
    const ticBytes = Buffer.allocUnsafe(4);
    ticBytes.writeUInt32LE(tic, 0);
    chain.update(ticBytes);
    chain.update(afterBuffer);
    compared += 1;
    if (compared % 500 === 0) {
      process.stdout.write(
        `PMLE_COMPACT_PARTIAL_DEPTH_ROUTE_PROGRESS|tic=${tic}`
          + `|frames=${compared}\n`,
      );
    }
  }
}

const baselineSha = sha(fs.readFileSync(baselinePath));
const candidateSha = sha(fs.readFileSync(candidatePath));
process.stdout.write(
  'PMLE_COMPACT_PARTIAL_DEPTH_ROUTE|PASS'
    + `|frames=${compared}|terminal_tic=${tic}`
    + `|baseline_sha256=${baselineSha}`
    + `|candidate_sha256=${candidateSha}`
    + `|frame_chain_sha256=${chain.digest('hex')}`
    + '|frame_bytes=64000|stages=world,sprites,weapon,status\n',
);
