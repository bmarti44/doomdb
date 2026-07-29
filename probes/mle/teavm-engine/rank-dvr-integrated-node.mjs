#!/usr/bin/env node
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {performance} from 'node:perf_hooks';
import {pathToFileURL} from 'node:url';

const [presentationPath, codecPath, fixturePath, iwadPath, tablePath] =
  process.argv.slice(2);
if (![presentationPath, codecPath, fixturePath, iwadPath, tablePath]
    .every(Boolean)) {
  throw new Error(
    'usage: rank-dvr-integrated-node.mjs PRESENTATION CODEC FIXTURE IWAD TABLES',
  );
}

const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const rows = [];
for (const run of fixture.runs) {
  for (let index = 0; index < run.repeat; index += 1) {
    rows.push({
      membership: run.membership,
      command: Uint8Array.from(Buffer.from(run.command, 'hex')),
    });
  }
}
if (rows.length !== fixture.tics || rows.length !== 5250) {
  throw new Error(`DVR codec requires the exact 5250-tic stream: ${rows.length}`);
}
const expanded = Buffer.concat(rows.map(row =>
  Buffer.concat([Buffer.from([row.membership]), Buffer.from(row.command)])));
const streamSha = createHash('sha256').update(expanded).digest('hex');
if (streamSha !== fixture.expandedSha256) {
  throw new Error('DVR codec command-stream digest mismatch');
}

const presentation = await import(pathToFileURL(path.resolve(
  presentationPath)).href);
const codec = await import(pathToFileURL(path.resolve(codecPath)).href);
if (codec.codecId() !== 'DOOM_DFR1_RLE' || codec.codecVersion() !== 1) {
  throw new Error('DVR codec identity mismatch');
}
if (presentation.dvrCodecId() !== 'DOOM_DFR1_RLE'
    || presentation.dvrCodecVersion() !== 1
    || typeof presentation.renderPlayerFrameCompressed !== 'function') {
  throw new Error('integrated presentation codec exports are missing');
}

const load = (allocate, write, bytes, label) => {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation failed`);
  }
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset,
      Math.min(bytes.length, offset + 1024 * 1024));
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} load failed at ${offset}`);
    }
  }
};
load(presentation.allocateIwad, presentation.loadIwadChunk,
  fs.readFileSync(iwadPath), 'IWAD');
load(presentation.allocateTablePack, presentation.loadTablePackChunk,
  fs.readFileSync(tablePath), 'table pack');
const initialized = presentation.initializeMultiplayerGame(
  fixture.players, fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill, fixture.episode, fixture.map);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`DVR presentation initialization failed: ${initialized}`);
}

const samples = [];
let frameChain = Buffer.alloc(32);
let compressedChain = Buffer.alloc(32);
for (let index = 0; index < rows.length; index += 1) {
  const row = rows[index];
  const tic = presentation.stepMultiplayerAuthoritative(
    fixture.players, row.membership, row.command);
  if (tic !== index + 1) throw new Error(`DVR frontier mismatch at ${tic}`);
  const started = performance.now();
  const compressed = presentation.renderPlayerFrameCompressed(0);
  const renderCompressMs = performance.now() - started;
  const restored = codec.decompressFrame(compressed);
  const frame = presentation.renderPlayerFrame(0);
  if (!(frame instanceof Uint8Array) || frame.byteLength !== 64000) {
    throw new Error(`DVR exact frame mismatch at tic ${tic}`);
  }
  if (!(restored instanceof Uint8Array)
      || !Buffer.from(restored).equals(Buffer.from(frame))) {
    throw new Error(`DVR codec round trip mismatch at tic ${tic}`);
  }
  const frameSha = createHash('sha256').update(frame).digest();
  const compressedSha = createHash('sha256').update(compressed).digest();
  frameChain = createHash('sha256').update(frameChain).update(frameSha).digest();
  compressedChain = createHash('sha256')
    .update(compressedChain).update(compressedSha).digest();
  samples.push({tic, renderCompressMs, compressedBytes: compressed.byteLength});
}
presentation.release();

const percentile = (values, fraction) => {
  const ordered = values.toSorted((left, right) => left - right);
  return ordered[Math.ceil(ordered.length * fraction) - 1];
};
const summarize = selected => ({
  samples: selected.length,
  renderCompressP50Ms:
    percentile(selected.map(row => row.renderCompressMs), 0.5),
  renderCompressP95Ms:
    percentile(selected.map(row => row.renderCompressMs), 0.95),
  compressedP50Bytes:
    percentile(selected.map(row => row.compressedBytes), 0.5),
  compressedP95Bytes:
    percentile(selected.map(row => row.compressedBytes), 0.95),
  ratioP50: percentile(selected.map(row => row.compressedBytes / 64000), 0.5),
  ratioP95: percentile(selected.map(row => row.compressedBytes / 64000), 0.95),
});
const whole = summarize(samples);
const peak = summarize(samples.filter(row => row.tic >= 101 && row.tic <= 800));
const quiet = summarize(samples.filter(row => row.tic >= 4401));
const presentationBytes = fs.readFileSync(presentationPath);
const codecBytes = fs.readFileSync(codecPath);
const output = {
  schema: 1,
  classification: 'NODE_REFERENCE_NOT_OCI_GATE',
  codec: 'DOOM_DFR1_RLE',
  codecVersion: 1,
  tics: samples.length,
  frameBytes: 64000,
  presentationSha256:
    createHash('sha256').update(presentationBytes).digest('hex'),
  codecSha256: createHash('sha256').update(codecBytes).digest('hex'),
  streamSha256: streamSha,
  frameChainSha256: frameChain.toString('hex'),
  compressedChainSha256: compressedChain.toString('hex'),
  whole,
  peak,
  quiet,
};
console.log(JSON.stringify(output));
console.log(
  `PMLE_DVR_INTEGRATED_NODE|PASS|codec=DOOM_DFR1_RLE|version=1|tics=5250`
  + `|frame_chain_sha256=${output.frameChainSha256}`
  + `|compressed_chain_sha256=${output.compressedChainSha256}`
  + `|ratio_p50=${whole.ratioP50.toFixed(6)}`
  + `|ratio_p95=${whole.ratioP95.toFixed(6)}`
  + `|render_compress_p95_ms=${whole.renderCompressP95Ms.toFixed(3)}`
  + `|presentation_sha256=${output.presentationSha256}`
  + `|codec_sha256=${output.codecSha256}`
  + `|stream_sha256=${streamSha}`,
);
