#!/usr/bin/env node

import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const rendererPath = path.resolve(process.argv[2] ?? path.join(
  root, 'probes/mle/free-live-teavm/target/javascript/'
    + 'doom-mle-free-live-unified-renderer.js'));
const outputDirectory = path.resolve(process.argv[3] ?? '/tmp/doomdb-render-compare');
const captureTics = new Set(
  (process.argv[4] ?? '1,32,96').split(',').map(Number));
if ([...captureTics].some(tic => !Number.isInteger(tic) || tic < 1)) {
  throw new Error('capture tics must be positive integers');
}
if (captureTics.size !== 1) {
  throw new Error(
    'visual comparison accepts one tic per fresh exact-renderer process');
}
const lastTic = Math.max(...captureTics);
const authorityPath = path.join(
  root, 'artifacts/performance/pmle-live-frame-hud/'
    + 'authority-candidate-66dd235cde82.js');
const exactPath = path.join(
  root, 'artifacts/performance/pmle-database-frames/'
    + 'presentation-decps-lean-byref-status-cache-4646503ae116.js');
const fixturePath = path.join(
  root, 'tests/fixtures/mle-live-deathmatch-2026-07-23.json');
const iwadPath = path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad');
const tablePath = path.join(
  root, 'probes/mle/teavm-engine/target/canonical-runtime-v2.bin');
const worldPackPath = path.join(
  root, 'probes/mle/free-live-teavm/target/world-raster-pack/'
    + 'free-live-render.pack');
const compositorPackPath = path.join(
  root, 'probes/mle/target/free-live-renderer/free-live-render.pack');
const assetsPath = path.join(
  root, 'probes/mle/target/free-live-renderer/assets-v1');

for (const required of [
  rendererPath, authorityPath, exactPath, fixturePath, iwadPath, tablePath,
  worldPackPath, compositorPackPath,
  path.join(assetsPath, 'wall_texture.bin'),
  path.join(assetsPath, 'flat.bin'),
  path.join(assetsPath, 'sprite_patch.bin'),
  path.join(assetsPath, 'ui_patch.bin'),
]) {
  if (!fs.existsSync(required)) {
    throw new Error(`visual comparison input is missing: ${required}`);
  }
}

const load = (allocate, write, bytes, label) => {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation failed`);
  }
  for (let offset = 0; offset < bytes.length; offset += 16_000) {
    const chunk = bytes.subarray(offset, offset + 16_000);
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} load failed at ${offset}`);
    }
  }
};
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const canonicalSha = engine => {
  const length = engine.canonicalStateLength();
  const hash = createHash('sha256');
  for (let offset = 0; offset < length; offset += 32_000) {
    const chunk = engine.canonicalStateChunk(
      offset, Math.min(32_000, length - offset));
    if (!ArrayBuffer.isView(chunk)) {
      throw new Error(`canonical state chunk is not a byte view at ${offset}`);
    }
    hash.update(chunk);
  }
  return hash.digest('hex');
};

const iwad = fs.readFileSync(iwadPath);
const authority = await import(pathToFileURL(authorityPath).href);
const exactEngine = await import(pathToFileURL(exactPath).href);
const renderer = await import(
  `${pathToFileURL(rendererPath).href}?visual=${Date.now()}`);
load(authority.allocateIwad, authority.loadIwadChunk, iwad, 'IWAD');
load(
  authority.allocateTablePack,
  authority.loadTablePackChunk,
  fs.readFileSync(tablePath),
  'table pack',
);
load(exactEngine.allocateIwad, exactEngine.loadIwadChunk, iwad, 'exact IWAD');
load(
  exactEngine.allocateTablePack,
  exactEngine.loadTablePackChunk,
  fs.readFileSync(tablePath),
  'exact table pack',
);
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
if (fixture.schema !== 1 || fixture.tics !== 5250
    || fixture.players !== 2 || fixture.mode !== 'DEATHMATCH') {
  throw new Error('visual comparison fixture contract mismatch');
}
const initialized = authority.initializeMultiplayerGame(
  fixture.players, 1, fixture.skill, fixture.episode, fixture.map);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`authority initialization failed: ${initialized}`);
}
const exactInitialized = exactEngine.initializeMultiplayerGame(
  fixture.players, 1, fixture.skill, fixture.episode, fixture.map);
if (!exactInitialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`exact initialization failed: ${exactInitialized}`);
}

load(
  renderer.allocatePack,
  renderer.loadPackChunk,
  fs.readFileSync(worldPackPath),
  'world pack',
);
if (renderer.finalizePack() !== fs.statSync(worldPackPath).size) {
  throw new Error('world pack finalize mismatch');
}
for (const [name, allocate, write, finalize] of [
  ['wall_texture.bin', renderer.allocateWallTextures,
    renderer.loadWallTextureChunk, renderer.finalizeWallTextures],
  ['flat.bin', renderer.allocateFlatTextures,
    renderer.loadFlatTextureChunk, renderer.finalizeFlatTextures],
]) {
  const bytes = fs.readFileSync(path.join(assetsPath, name));
  load(allocate, write, bytes, name);
  if (finalize() !== bytes.length) throw new Error(`${name} finalize mismatch`);
}
const compositorPack = fs.readFileSync(compositorPackPath);
load(
  renderer.allocateCompositorPack,
  renderer.loadCompositorPackChunk,
  compositorPack,
  'compositor pack',
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
  load(allocate, write, bytes, name);
  if (finalize() !== bytes.length) throw new Error(`${name} finalize mismatch`);
}
renderer.resetPresentationState();

const rows = [];
for (const run of fixture.runs) {
  const command = Uint8Array.from(Buffer.from(run.command, 'hex'));
  for (let repeat = 0; repeat < run.repeat; repeat += 1) {
    rows.push({membership: run.membership, command});
  }
}

const wadCount = iwad.readUInt32LE(4);
const wadDirectory = iwad.readUInt32LE(8);
let palette;
for (let index = 0; index < wadCount; index += 1) {
  const at = wadDirectory + index * 16;
  const name = iwad.toString('ascii', at + 8, at + 16)
    .replace(/\0.*$/s, '');
  if (name !== 'PLAYPAL') continue;
  const offset = iwad.readUInt32LE(at);
  palette = iwad.subarray(offset, offset + 768);
  break;
}
if (!palette || palette.length !== 768) {
  throw new Error('PLAYPAL palette missing');
}
fs.mkdirSync(outputDirectory, {recursive: true});
const ppm = (frame, columnMajor) => {
  const rgb = Buffer.alloc(320 * 200 * 3);
  for (let y = 0; y < 200; y += 1) {
    for (let x = 0; x < 320; x += 1) {
      const color = frame[columnMajor ? x * 200 + y : y * 320 + x] & 255;
      palette.copy(rgb, (y * 320 + x) * 3, color * 3, color * 3 + 3);
    }
  }
  return Buffer.concat([Buffer.from('P6\n320 200\n255\n'), rgb]);
};

const terminals = [];
for (let index = 0; index < lastTic; index += 1) {
  const row = rows[index];
  const tic = authority.stepMultiplayerAuthoritative(
    fixture.players, row.membership, row.command);
  if (tic !== index + 1) throw new Error(`frontier mismatch at ${tic}`);
  const exactTic = exactEngine.stepMultiplayerAuthoritative(
    fixture.players, row.membership, row.command);
  if (exactTic !== tic) throw new Error(`exact frontier mismatch at ${tic}`);
  let authorityCanonicalSha;
  let exact;
  if (captureTics.has(tic)) {
    authorityCanonicalSha = canonicalSha(authority);
    const exactCanonicalSha = canonicalSha(exactEngine);
    if (authorityCanonicalSha !== exactCanonicalSha) {
      throw new Error(
        `canonical state mismatch at ${tic}: `
          + `${authorityCanonicalSha}/${exactCanonicalSha}`);
    }
    exact = Buffer.from(exactEngine.renderPlayerFrameByRef(0));
    if (exact.length !== 64_000) throw new Error(`exact frame shape ${tic}`);
  }
  const worldLength =
    authority.presentationWorldGeometryDeltaSnapshotLength(0);
  const world = authority.presentationWorldSnapshotNativeByRef()
    .slice(0, worldLength);
  const worldView = new DataView(
    world.buffer, world.byteOffset, world.byteLength);
  const compositorLength = authority.presentationCompositorSnapshotLength(0);
  const compositor = authority.presentationWorldSnapshotNativeByRef()
    .slice(0, compositorLength);
  renderer.loadCompactSnapshot(world);
  renderer.renderLoadedCompactFrameCoarse(world);
  renderer.composeWorldSpritesStage(compositor);
  renderer.composeWeaponStage(compositor);
  renderer.composeStatusStage(compositor);
  const candidate = Buffer.from(renderer.frameNativeByRef());
  if (candidate.length !== 64_000) {
    throw new Error(`candidate frame shape ${tic}`);
  }
  if (!captureTics.has(tic)) continue;

  let different = 0;
  let absolutePaletteDelta = 0;
  for (let y = 0; y < 200; y += 1) {
    for (let x = 0; x < 320; x += 1) {
      const expected = exact[y * 320 + x] & 255;
      const actual = candidate[x * 200 + y] & 255;
      if (expected !== actual) different += 1;
      absolutePaletteDelta += Math.abs(expected - actual);
    }
  }
  fs.writeFileSync(
    path.join(outputDirectory, `tic-${tic}-exact.ppm`),
    ppm(exact, false),
  );
  fs.writeFileSync(
    path.join(outputDirectory, `tic-${tic}-candidate.ppm`),
    ppm(candidate, true),
  );
  terminals.push({
    tic,
    exactSha: sha(exact),
    candidateSha: sha(candidate),
    different,
    meanPaletteDelta: absolutePaletteDelta / 64_000,
    playerX: worldView.getInt32(36, true),
    playerY: worldView.getInt32(40, true),
    angleHigh: worldView.getInt32(48, true),
    viewZ: worldView.getInt32(52, true),
    weaponSx: worldView.getInt32(92, true),
    weaponSy: worldView.getInt32(96, true),
    weaponSprite: worldView.getInt32(100, true),
    weaponFrame: worldView.getInt32(104, true),
    canonicalSha: authorityCanonicalSha,
  });
}
authority.release();
exactEngine.release();
if (terminals.length !== captureTics.size) {
  throw new Error('visual comparison did not capture every requested tic');
}
for (const row of terminals) {
  process.stdout.write(
    'PMLE_LIVE_RENDERER_VISUAL_COMPARE|DIAGNOSTIC_NOT_GATE'
      + `|tic=${row.tic}|different_pixels=${row.different}`
      + `|different_percent=${(row.different / 640).toFixed(3)}`
      + `|mean_palette_delta=${row.meanPaletteDelta.toFixed(3)}`
      + `|player_x=${row.playerX}|player_y=${row.playerY}`
      + `|angle_high=${row.angleHigh}|view_z=${row.viewZ}`
      + `|weapon_sx=${row.weaponSx}|weapon_sy=${row.weaponSy}`
      + `|weapon_sprite=${row.weaponSprite}|weapon_frame=${row.weaponFrame}`
      + `|canonical_sha256=${row.canonicalSha}`
      + `|exact_sha256=${row.exactSha}`
      + `|candidate_sha256=${row.candidateSha}`
      + `|renderer_sha256=${sha(fs.readFileSync(rendererPath))}\n`,
  );
}
