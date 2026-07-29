#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const artifactPath = process.argv[2] ?? path.join(
  root,
  'probes/mle/free-live-teavm/target/javascript/'
    + 'doom-mle-free-live-compositor.js',
);
const packPath = process.argv[3] ?? path.join(
  root, 'probes/mle/target/free-live-renderer/free-live-render.pack',
);
const assetDirectory = process.argv[4] ?? path.join(
  root, 'probes/mle/target/free-live-renderer/assets-v1',
);

const compositor = await import(pathToFileURL(artifactPath).href);
const load = (allocate, write, bytes) => {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`allocation rejected ${bytes.length}`);
  }
  for (let offset = 0; offset < bytes.length; offset += 16_000) {
    const chunk = bytes.subarray(offset, offset + 16_000);
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`short load at ${offset}`);
    }
  }
};

const pack = fs.readFileSync(packPath);
load(compositor.allocatePack, compositor.loadPackChunk, pack);
if (compositor.finalizePack() !== pack.length) {
  throw new Error('compositor pack finalize mismatch');
}
for (const [kind, allocate, write, finalize] of [
  ['sprite_patch', compositor.allocateSpriteTextures,
    compositor.loadSpriteTextureChunk, compositor.finalizeSpriteTextures],
  ['ui_patch', compositor.allocateUiTextures,
    compositor.loadUiTextureChunk, compositor.finalizeUiTextures],
]) {
  const bytes = fs.readFileSync(path.join(assetDirectory, `${kind}.bin`));
  load(allocate, write, bytes);
  if (finalize() !== bytes.length) {
    throw new Error(`${kind} finalize mismatch`);
  }
}

const putI32 = (bytes, offset, value) => {
  new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    .setInt32(offset, value, true);
};
const snapshot = ({
  tic = 1,
  health = 100,
  armor = 0,
  readyWeapon = 1,
  ammo = [50, 0, 0, 0],
  cards = 0,
  weapons = [0, 1],
  backpack = false,
  deathmatch = false,
  frags = 0,
} = {}) => {
  const bytes = new Uint8Array(208);
  putI32(bytes, 0, 0x344c5644); // DVC4
  putI32(bytes, 4, 4);
  putI32(bytes, 8, tic);
  putI32(bytes, 16, 0);
  putI32(bytes, 20, 0);
  putI32(bytes, 24, 208);
  putI32(bytes, 28, 208);
  putI32(bytes, 32, 208);
  putI32(bytes, 56, health);
  putI32(bytes, 60, armor);
  putI32(bytes, 64, readyWeapon);
  for (let index = 0; index < 4; index++) {
    putI32(bytes, 72 + index * 4, ammo[index]);
  }
  let presentationFlags = cards & 0x3f;
  for (const weapon of weapons) presentationFlags |= 1 << (8 + weapon);
  if (backpack) presentationFlags |= 1 << 17;
  if (deathmatch) presentationFlags |= 1 << 18;
  putI32(bytes, 144, presentationFlags);
  putI32(bytes, 148, frags);
  putI32(bytes, 164, 0);
  putI32(bytes, 192, 0);
  return bytes;
};
const frame = () => Uint8Array.from(compositor.frameByRef(), value => value & 255);
const difference = (left, right, x0, x1, y0 = 168, y1 = 200) => {
  let changed = 0;
  for (let x = x0; x < x1; x++) {
    for (let y = y0; y < y1; y++) {
      if (left[x * 200 + y] !== right[x * 200 + y]) changed++;
    }
  }
  return changed;
};

if (compositor.resetPresentationState() !== 10) {
  throw new Error('unexpected retained HUD state width');
}
compositor.composeStatusStage(snapshot());
const baseline = frame();

compositor.composeStatusStage(snapshot({
  tic: 18,
  health: 87,
  armor: 50,
  readyWeapon: 2,
  ammo: [37, 12, 80, 4],
  cards: (1 << 0) | (1 << 4),
  weapons: [0, 1, 2, 3],
  backpack: true,
}));
const equipped = frame();
const regions = {
  readyAmmo: difference(baseline, equipped, 4, 44),
  health: difference(baseline, equipped, 51, 99),
  arms: difference(baseline, equipped, 104, 142),
  face: difference(baseline, equipped, 142, 185),
  armor: difference(baseline, equipped, 182, 230),
  keys: difference(baseline, equipped, 238, 270),
  ammoTable: difference(baseline, equipped, 274, 320),
};
for (const [name, changed] of Object.entries(regions)) {
  if (changed < 1) throw new Error(`${name} HUD region did not change`);
}

compositor.composeStatusStage(snapshot({
  tic: 19,
  health: 87,
  armor: 50,
  readyWeapon: 2,
  ammo: [37, 12, 80, 4],
  cards: (1 << 0) | (1 << 4),
  weapons: [0, 1, 2, 3],
  backpack: true,
  deathmatch: true,
  frags: -3,
}));
const deathmatch = frame();
if (difference(equipped, deathmatch, 104, 142) < 1) {
  throw new Error('deathmatch frags did not replace the ARMS grid');
}

const stableInput = snapshot({
  tic: 19,
  health: 87,
  armor: 50,
  readyWeapon: 2,
  ammo: [37, 12, 80, 4],
  cards: (1 << 0) | (1 << 4),
  weapons: [0, 1, 2, 3],
  backpack: true,
  deathmatch: true,
  frags: -3,
});
compositor.composeStatusStage(stableInput);
const stable = frame();
if (difference(deathmatch, stable, 0, 320) !== 0) {
  throw new Error('unchanged retained HUD was not pixel-stable');
}

if (process.env.PMLE_HUD_PPM) {
  const iwad = fs.readFileSync(path.join(
    root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad',
  ));
  const count = iwad.readUInt32LE(4);
  const directory = iwad.readUInt32LE(8);
  let palette;
  for (let index = 0; index < count; index++) {
    const at = directory + index * 16;
    const name = iwad.toString('ascii', at + 8, at + 16)
      .replace(/\0.*$/s, '');
    if (name !== 'PLAYPAL') continue;
    const offset = iwad.readUInt32LE(at);
    palette = iwad.subarray(offset, offset + 768);
  }
  if (!palette || palette.length !== 768) {
    throw new Error('PLAYPAL palette missing');
  }
  const rgb = Buffer.alloc(320 * 200 * 3);
  for (let y = 0; y < 200; y++) {
    for (let x = 0; x < 320; x++) {
      const color = equipped[x * 200 + y];
      palette.copy(rgb, (y * 320 + x) * 3, color * 3, color * 3 + 3);
    }
  }
  fs.writeFileSync(
    process.env.PMLE_HUD_PPM,
    Buffer.concat([Buffer.from('P6\n320 200\n255\n'), rgb]),
  );
}

process.stdout.write(
  'PMLE_FREE_LIVE_HUD_NODE|PASS'
    + '|snapshot_bytes=208|retained_state=10'
    + '|widgets=ready_ammo,health_percent,arms_or_frags,animated_face,'
    + 'armor_percent,keys,current_and_max_ammo'
    + `|region_changes=${Object.values(regions).join(',')}`
    + '|deathmatch_negative_frags=YES|unchanged_pixel_stable=YES\n',
);
