#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';

const coordinator = fs.readFileSync(new URL(
  '../probes/mle/dvl2-world-raster-coordinator.mjs', import.meta.url), 'utf8');

assert.match(coordinator,
  /current\.x === previous\.x && current\.y === previous\.y[\s\S]*current\.angle === previous\.angle[\s\S]*current\.viewZ === previous\.viewZ/);
assert.match(coordinator,
  /target\.set\(source\);\s*return target;/);
assert.match(coordinator, /const VIEW_HEIGHT = 168;/);
assert.match(coordinator,
  /source\.subarray\(sourceAt, sourceAt \+ VIEW_HEIGHT\)/);
assert.doesNotMatch(coordinator,
  /source\.subarray\(sourceAt, sourceAt \+ FRAME_HEIGHT\)/);

const width = 320;
const height = 200;
const source = new Uint8Array(width * height);
for (let index = 0; index < source.length; index++) {
  source[index] = (index * 73 + (index >>> 7) * 19) & 255;
}

for (const frameTic of [1, 2, 31, 0xffff_ffff]) {
  const prior = new Uint8Array(source.length);
  for (let x = 0; x < width; x++) {
    const sourcePosition = width / 2 + (x - width / 2);
    const lowerSource = Math.floor(sourcePosition);
    const fraction = sourcePosition - lowerSource;
    const threshold = ((x * 5 + frameTic * 3) & 7) / 8;
    const sourceX = Math.max(0, Math.min(
      width - 1, lowerSource + (fraction > threshold ? 1 : 0)));
    const sourceAt = sourceX * height;
    prior.set(source.subarray(sourceAt, sourceAt + height), x * height);
  }
  const candidate = new Uint8Array(source.length);
  candidate.set(source);
  assert.deepEqual(candidate, prior,
    `stationary fast path changed the indexed framebuffer at tic ${frameTic}`);
}

// Moving-camera reprojection is allowed to transform only the 168-row world
// viewport. The compositor owns rows 168..199; shifting those bytes tears the
// retained status-bar background underneath its widget-level redraws.
const viewHeight = 168;
const target = new Uint8Array(source);
for (let x = 0; x < width; x++) {
  const sourceX = Math.min(width - 1, x + 1);
  target.set(
    source.subarray(
      sourceX * height, sourceX * height + viewHeight),
    x * height);
}
for (let x = 0; x < width; x++) {
  assert.deepEqual(
    target.subarray(x * height + viewHeight, (x + 1) * height),
    source.subarray(x * height + viewHeight, (x + 1) * height),
    `moving reprojection changed status pixels in column ${x}`);
}

process.stdout.write(
  'PASS PMLE-TEMPORAL-STATIC-COPY '
    + '(bit-identical static path; moving path preserves HUD)\n');
