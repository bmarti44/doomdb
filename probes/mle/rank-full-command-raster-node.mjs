import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';

const root = path.resolve(import.meta.dirname, '../..');
const artifactPath = process.argv[2]
  ?? path.join(root,
    'probes/mle/free-raster-teavm/target/javascript/'
    + 'doom-mle-free-raster-kernel.js');
const packPath = process.argv[3]
  ?? path.join(root,
    'probes/mle/teavm-engine/target/full-command-capture-v6.bin');
const module = await import(pathToFileURL(artifactPath).href);
const {
  allocateFullCommandPack,
  loadFullCommandPackChunk,
  finalizeFullCommandPack,
  renderFullCommandFrame,
  renderFullCommandBatch,
  fullCommandFrameCount,
  fullCommandFrameTic,
  fullCommandFramePlayer,
  fullCommandCount,
  prepareFullCommandViewport,
  prepareFullCommandFrame,
  fullCommandViewportChunk,
  fullCommandViewportDigest,
  fullCommandFrameChunk,
  fullCommandFrameDigest,
} = module.FullCommandRasterKernel ?? {};

for (const [name, value] of Object.entries({
  allocateFullCommandPack,
  loadFullCommandPackChunk,
  finalizeFullCommandPack,
  renderFullCommandFrame,
  renderFullCommandBatch,
  fullCommandFrameCount,
  fullCommandFrameTic,
  fullCommandFramePlayer,
  fullCommandCount,
  prepareFullCommandViewport,
  prepareFullCommandFrame,
  fullCommandViewportChunk,
  fullCommandViewportDigest,
  fullCommandFrameChunk,
  fullCommandFrameDigest,
})) {
  if (typeof value !== 'function') throw new Error(`missing export ${name}`);
}

const pack = fs.readFileSync(packPath);
if (allocateFullCommandPack(pack.length) !== pack.length) {
  throw new Error('full-command allocation failed');
}
for (let offset = 0; offset < pack.length; offset += 1024 * 1024) {
  const chunk = pack.subarray(offset, Math.min(pack.length, offset + 1024 * 1024));
  if (loadFullCommandPackChunk(offset, chunk) !== offset + chunk.length) {
    throw new Error(`short full-command load at ${offset}`);
  }
}
const frames = finalizeFullCommandPack();
if (frames !== 192 || fullCommandFrameCount() !== frames) {
  throw new Error(`unexpected full-command frame count ${frames}`);
}

let commands = 0;
const viewport = Buffer.alloc(320 * 168);
const fullFrame = Buffer.alloc(320 * 200);
for (let frame = 0; frame < frames; frame += 1) {
  renderFullCommandFrame(frame);
  if (prepareFullCommandViewport() !== viewport.length) {
    throw new Error(`viewport preparation failed at frame ${frame}`);
  }
  for (let offset = 0; offset < viewport.length; offset += 32767) {
    const size = Math.min(32767, viewport.length - offset);
    const chunk = fullCommandViewportChunk(offset, size);
    if (!ArrayBuffer.isView(chunk) || chunk.length !== size) {
      throw new Error(`short viewport chunk at ${frame}/${offset}`);
    }
    viewport.set(chunk, offset);
  }
  const actual = createHash('sha256').update(viewport).digest('hex');
  const expected = Buffer.from(fullCommandViewportDigest(frame)).toString('hex');
  if (actual !== expected) {
    throw new Error(
      `viewport mismatch at frame=${frame}`
      + ` tic=${fullCommandFrameTic(frame)}`
      + ` player=${fullCommandFramePlayer(frame)}`
      + ` commands=${fullCommandCount(frame)}`
      + ` actual=${actual} expected=${expected}`,
    );
  }
  if (prepareFullCommandFrame() !== fullFrame.length) {
    throw new Error(`full-frame preparation failed at frame ${frame}`);
  }
  for (let offset = 0; offset < fullFrame.length; offset += 32767) {
    const size = Math.min(32767, fullFrame.length - offset);
    const chunk = fullCommandFrameChunk(offset, size);
    if (!ArrayBuffer.isView(chunk) || chunk.length !== size) {
      throw new Error(`short full-frame chunk at ${frame}/${offset}`);
    }
    fullFrame.set(chunk, offset);
  }
  const actualFull = createHash('sha256').update(fullFrame).digest('hex');
  const expectedFull = Buffer.from(fullCommandFrameDigest(frame)).toString('hex');
  if (actualFull !== expectedFull) {
    throw new Error(
      `full-frame mismatch at frame=${frame}`
      + ` tic=${fullCommandFrameTic(frame)}`
      + ` player=${fullCommandFramePlayer(frame)}`
      + ` actual=${actualFull} expected=${expectedFull}`,
    );
  }
  commands += fullCommandCount(frame);
}

const samples = [];
for (let iteration = 0; iteration < 20; iteration += 1) {
  const start = performance.now();
  renderFullCommandBatch(0, frames);
  samples.push((performance.now() - start) / frames);
}
samples.sort((a, b) => a - b);
const percentile = (fraction) =>
  samples[Math.max(0, Math.ceil(samples.length * fraction) - 1)];
console.log(
  `PMLE_FULL_COMMAND_RASTER_NODE|PASS|frames=${frames}|commands=${commands}`
  + `|viewport_exact=${frames}|full_frame_exact=${frames}`
  + `|ms_per_frame_p50=${percentile(.5).toFixed(6)}`
  + `|ms_per_frame_p95=${percentile(.95).toFixed(6)}`
  + `|artifact_sha256=${createHash('sha256')
    .update(fs.readFileSync(artifactPath)).digest('hex')}`
  + `|pack_sha256=${createHash('sha256').update(pack).digest('hex')}`,
);
