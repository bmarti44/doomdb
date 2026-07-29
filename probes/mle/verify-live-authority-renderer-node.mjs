#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

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
const assetDirectory = process.argv[7] ?? path.join(
  root, 'probes/mle/target/free-live-renderer/assets-v1',
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
for (const [kind, allocate, write, finalize] of [
  ['wall_texture', renderer.allocateWallTextures,
    renderer.loadWallTextureChunk, renderer.finalizeWallTextures],
  ['flat', renderer.allocateFlatTextures,
    renderer.loadFlatTextureChunk, renderer.finalizeFlatTextures],
  ['sprite_patch', renderer.allocateSpriteTextures,
    renderer.loadSpriteTextureChunk, renderer.finalizeSpriteTextures],
  ['ui_patch', renderer.allocateUiTextures,
    renderer.loadUiTextureChunk, renderer.finalizeUiTextures],
]) {
  const bytes = fs.readFileSync(path.join(assetDirectory, `${kind}.bin`));
  load(allocate, write, bytes);
  if (finalize() !== bytes.length) {
    throw new Error(`${kind} finalize mismatch`);
  }
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
const worldSnapshots = [new Set(), new Set()];
const renderChecksums = [new Set(), new Set()];
const frameHashes = [new Set(), new Set()];
const firstFrameStats = [];
const firstWorldStats = [];
const selectedPresentationStats = [];
let minimumWorldSnapshotBytes = Number.MAX_SAFE_INTEGER;
let maximumWorldSnapshotBytes = 0;
const frameDirectory = process.env.PMLE_FREE_LIVE_FRAME_DIR;
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
    const worldLength = authority.presentationWorldSnapshotLength(player);
    minimumWorldSnapshotBytes = Math.min(
      minimumWorldSnapshotBytes, worldLength);
    maximumWorldSnapshotBytes = Math.max(
      maximumWorldSnapshotBytes, worldLength);
    const world = new Uint8Array(worldLength);
    for (let offset = 0; offset < worldLength; offset += 4096) {
      const size = Math.min(4096, worldLength - offset);
      const chunk = authority.presentationWorldSnapshotChunk(offset, size);
      if (!(chunk instanceof Uint8Array) || chunk.length !== size) {
        throw new Error(`short world snapshot ${tic}/${player}/${offset}`);
      }
      world.set(chunk, offset);
    }
    worldSnapshots[player].add(
      createHash('sha256').update(world).digest('hex'),
    );
    renderChecksums[player].add(renderer.renderWorldSnapshot(world));
    const frame = Buffer.from(renderer.frameByRef());
    if (frame.length !== 320 * 200) {
      throw new Error(`invalid complete frame ${tic}/${player}`);
    }
    frameHashes[player].add(createHash('sha256').update(frame).digest('hex'));
    renderer.loadWorldDynamicsStage(world);
    renderer.renderLoadedWorldGeometryStage(world);
    renderer.renderWorldSpritesStage(world);
    renderer.renderWeaponStage(world);
    renderer.renderStatusStage(world);
    const stagedFrame = Buffer.from(renderer.frameByRef());
    if (!stagedFrame.equals(frame)) {
      throw new Error(`staged renderer mismatch ${tic}/${player}`);
    }
    if (tic === 1) {
      const worldView = new DataView(
        world.buffer, world.byteOffset, world.byteLength);
      firstWorldStats[player] = {
        readyWeapon: worldView.getInt32(64, true),
        psprite0State: worldView.getInt32(88, true),
        psprite0X: worldView.getInt32(92, true) >> 16,
        psprite0Y: worldView.getInt32(96, true) >> 16,
        psprite0Sprite: worldView.getInt32(100, true),
        psprite0Frame: worldView.getInt32(104, true),
      };
      const hud = Buffer.alloc(320 * 32);
      for (let x = 0; x < 320; x += 1) {
        frame.copy(hud, x * 32, x * 200 + 168, x * 200 + 200);
      }
      firstFrameStats[player] = {
        hudDistinct: new Set(hud).size,
        hudNonzero: hud.reduce(
          (count, value) => count + (value === 0 ? 0 : 1), 0),
      };
    }
    if (player === 0 && (tic === 1 || tic === 48 || tic === 96)) {
      const worldView = new DataView(
        world.buffer, world.byteOffset, world.byteLength);
      selectedPresentationStats.push({
        tic,
        psprite0: {
          state: worldView.getInt32(88, true),
          x: worldView.getInt32(92, true) >> 16,
          y: worldView.getInt32(96, true) >> 16,
          sprite: worldView.getInt32(100, true),
          frame: worldView.getInt32(104, true),
        },
        psprite1: {
          state: worldView.getInt32(108, true),
          x: worldView.getInt32(112, true) >> 16,
          y: worldView.getInt32(116, true) >> 16,
          sprite: worldView.getInt32(120, true),
          frame: worldView.getInt32(124, true),
        },
      });
    }
    if (frameDirectory && player === 0 && (tic === 1 || tic === 48 || tic === 96)) {
      fs.mkdirSync(frameDirectory, {recursive: true});
      fs.writeFileSync(path.join(frameDirectory, `live-tic-${tic}.bin`), frame);
    }
  }
}
authority.release();

if (snapshots.some(set => set.size < 50)
    || worldSnapshots.some(set => set.size < 90)
    || renderChecksums.some(set => set.size < 25)
    || frameHashes.some(set => set.size < 50)
    || firstFrameStats.some(
      stats => stats.hudDistinct < 16 || stats.hudNonzero < 8000)) {
  throw new Error(
    `insufficient live variation snapshots=${snapshots.map(set => set.size)}`
      + ` world=${worldSnapshots.map(set => set.size)}`
      + ` renders=${renderChecksums.map(set => set.size)}`
      + ` frames=${frameHashes.map(set => set.size)}`
      + ` hud=${JSON.stringify(firstFrameStats)}`,
  );
}
const titleChecksum = renderer.renderTitleFrame();
const titleHash = createHash('sha256')
  .update(Buffer.from(renderer.frameByRef())).digest('hex');
if (frameDirectory) {
  fs.writeFileSync(
    path.join(frameDirectory, 'title.bin'),
    Buffer.from(renderer.frameByRef()),
  );
}
const menuHashes = [];
for (const [page, name] of [
  [0, 'main-menu'], [1, 'episode-menu'], [2, 'skill-menu'],
  [3, 'options-menu'],
]) {
  renderer.renderMenuSelectionFrame(page, page % 2, 8);
  const bytes = Buffer.from(renderer.frameByRef());
  menuHashes.push(createHash('sha256').update(bytes).digest('hex'));
  if (frameDirectory) {
    fs.writeFileSync(path.join(frameDirectory, `${name}.bin`), bytes);
  }
}
const screenHashes = [];
for (const screen of [1, 2, 4, 5, 6, 7, 8]) {
  renderer.renderScreenFrame(screen);
  screenHashes.push(createHash('sha256')
    .update(Buffer.from(renderer.frameByRef())).digest('hex'));
}
if (new Set([titleHash, ...menuHashes]).size !== 5
    || new Set(screenHashes).size !== screenHashes.length) {
  throw new Error('database menu/screen frames are not distinct');
}

process.stdout.write(
  'PMLE_LIVE_AUTHORITY_RENDERER_NODE|PASS|tics=96|players=2'
  + `|snapshot_unique=${snapshots.map(set => set.size).join(',')}`
  + `|world_unique=${worldSnapshots.map(set => set.size).join(',')}`
  + `|render_checksum_unique=${renderChecksums.map(set => set.size).join(',')}`
  + `|frame_unique=${frameHashes.map(set => set.size).join(',')}`
  + `|hud_distinct=${firstFrameStats.map(value => value.hudDistinct).join(',')}`
  + `|pov0_psprite=${JSON.stringify(firstWorldStats[0])}`
  + `|selected_psprites=${JSON.stringify(selectedPresentationStats)}`
  + `|title_sha256=${titleHash}|menu_sha256=${menuHashes.join(',')}`
  + `|screen_sha256=${screenHashes.join(',')}`
  + `|player_snapshot_bytes=32|world_snapshot_bytes_min=${minimumWorldSnapshotBytes}`
  + `|world_snapshot_bytes_max=${maximumWorldSnapshotBytes}`
  + '|world_format=DVL2|authority=MOCHA_TEAVM'
  + '|renderer=SPECIALIZED_GAMEPLAY_TEAVM_MLE'
  + '|client=NOT_TESTED_BY_THIS_GATE\n',
);
