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
  root, 'probes/mle/free-live-renderer.mjs',
);
const iwadPath = process.argv[4] ?? path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad',
);
const tablePath = process.argv[5] ?? path.join(
  root, 'probes/mle/teavm-engine/target/canonical-runtime-v2.bin',
);
const packPath = process.argv[6] ?? path.join(
  root, 'probes/mle/target/free-live-renderer/free-live-render.pack',
);
const assetDirectory = process.argv[7] ?? path.join(
  root, 'probes/mle/target/free-live-renderer/assets-v1',
);

const authority = await import(pathToFileURL(authorityPath).href);
const renderer = await import(
  `${pathToFileURL(rendererPath).href}?plain=${Date.now()}`);

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

load(authority.allocateIwad, authority.loadIwadChunk, fs.readFileSync(iwadPath));
load(
  authority.allocateTablePack,
  authority.loadTablePackChunk,
  fs.readFileSync(tablePath),
);
const initialized = authority.initializeMultiplayerGame(2, 0, 3, 1, 1);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`authority initialization failed: ${initialized}`);
}
const pack = fs.readFileSync(packPath);
load(renderer.allocatePack, renderer.loadPackChunk, pack);
if (renderer.finalizePack() !== pack.length) {
  throw new Error('plain renderer pack finalize mismatch');
}
for (const [kind, allocate, write, finalize] of [
  ['wall_texture', renderer.allocateWallTextures,
    renderer.loadWallTextureChunk, renderer.finalizeWallTextures],
  ['flat', renderer.allocateFlatTextures,
    renderer.loadFlatTextureChunk, renderer.finalizeFlatTextures],
]) {
  const bytes = fs.readFileSync(path.join(assetDirectory, `${kind}.bin`));
  load(allocate, write, bytes);
  if (finalize() !== bytes.length) throw new Error(`${kind} finalize mismatch`);
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

const hashes = new Set();
const output = process.env.PMLE_PLAIN_FRAME_DIR;
const fast = process.env.PMLE_PLAIN_FAST === 'YES';
let partitionMismatchMax = 0;
for (let tic = 1; tic <= 96; tic += 1) {
  if (authority.stepMultiplayerAuthoritative(2, 3, commands(tic)) !== tic) {
    throw new Error(`authority frontier mismatch at ${tic}`);
  }
  const length = authority.presentationWorldSnapshotLength(0);
  const retained = authority.presentationWorldSnapshotByRef();
  const world = retained.subarray(0, length);
  if (fast) renderer.renderWorldFastGeometryStatic(world);
  else renderer.renderWorldGeometry(world);
  const frame = Buffer.from(renderer.frameByRef());
  if (!fast && (tic === 1 || tic === 48 || tic === 96)) {
    renderer.setColumnRange(0, 159);
    renderer.renderWorldGeometry(world);
    const left = Buffer.from(renderer.frameByRef().subarray(0, 32000));
    renderer.setColumnRange(160, 319);
    renderer.renderWorldGeometry(world);
    const right = Buffer.from(renderer.frameByRef().subarray(32000, 64000));
    renderer.setColumnRange(0, 319);
    const joined = Buffer.concat([left, right]);
    if (!joined.equals(frame)) {
      let first = -1;
      let count = 0;
      for (let index = 0; index < frame.length; index += 1) {
        if (joined[index] !== frame[index]) {
          if (first < 0) first = index;
          count += 1;
        }
      }
      partitionMismatchMax = Math.max(partitionMismatchMax, count);
      if (count > 32) {
        throw new Error(
          `partitioned geometry mismatch at ${tic}: first=${first}`
          + ` count=${count} column=${Math.floor(first / 200)}`);
      }
    }
  }
  hashes.add(createHash('sha256').update(frame).digest('hex'));
  if (output && (tic === 1 || tic === 48 || tic === 96)) {
    fs.mkdirSync(output, {recursive: true});
    fs.writeFileSync(path.join(output, `plain-geometry-${tic}.bin`), frame);
  }
}
authority.release();
if (hashes.size < 50) {
  throw new Error(`plain renderer variation too low: ${hashes.size}`);
}
process.stdout.write(
  `PMLE_PLAIN_LIVE_GEOMETRY_NODE|PASS|tics=96|unique=${hashes.size}`
  + `|mode=${fast ? 'FAST_RAY' : 'BSP_VISPLANE'}`
  + `|partition_mismatch_max=${partitionMismatchMax}`
  + `|frame_bytes=64000|${renderer.stats()}\n`,
);
