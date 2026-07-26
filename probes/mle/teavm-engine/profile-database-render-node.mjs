#!/usr/bin/env node
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const [artifactPath, fixturePath, iwadPath, tablePath,
  sampleText = '100', warmupText = '10', offsetText = '310'] =
  process.argv.slice(2);
if (!artifactPath || !fixturePath || !iwadPath || !tablePath) {
  throw new Error(
    'usage: profile-database-render-node.mjs ARTIFACT FIXTURE'
    + ' IWAD TABLES [SAMPLES WARMUP]');
}
const samples = Number(sampleText), warmup = Number(warmupText);
const offset = Number(offsetText);
if (!(samples === 5250 && warmup === 0 && offset === 0)
    && (!([100,300].includes(samples) && warmup === samples / 10)
      || !Number.isInteger(offset) || offset < 0)) {
  throw new Error(`unsupported corpus shape ${samples}/${warmup}/${offset}`);
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
if (rows.length !== fixture.tics || rows.length < samples + warmup) {
  throw new Error('command fixture expansion mismatch');
}
const expanded = Buffer.concat(rows.map(row =>
  Buffer.concat([Buffer.from([row.membership]), Buffer.from(row.command)])));
const expandedSha = createHash('sha256').update(expanded).digest('hex');
if (expandedSha !== fixture.expandedSha256) {
  throw new Error('command fixture digest mismatch');
}

const engine = await import(pathToFileURL(path.resolve(artifactPath)).href);
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
load(engine.allocateIwad, engine.loadIwadChunk,
  fs.readFileSync(iwadPath), 'IWAD');
load(engine.allocateTablePack, engine.loadTablePackChunk,
  fs.readFileSync(tablePath), 'table pack');
const initialized = engine.initializeMultiplayerGame(
  fixture.players, fixture.mode === 'DEATHMATCH' ? 1 : 0,
  fixture.skill, fixture.episode, fixture.map);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`presentation initialization failed: ${initialized}`);
}

let chain = Buffer.alloc(32), frontier = 0;
const unique = new Set();
const renderFrame = typeof engine.renderPlayerFrameByRef === 'function'
  ? engine.renderPlayerFrameByRef : engine.renderPlayerFrame;
const exportShape = renderFrame === engine.renderPlayerFrameByRef
  ? 'byte-array-by-ref' : 'uint8-copy';
for (let index = 0; index < offset + warmup + samples; index += 1) {
  const row = rows[index];
  frontier = engine.stepMultiplayerAuthoritative(
    fixture.players, row.membership, row.command);
  if (frontier !== index + 1) throw new Error(`frontier mismatch at ${frontier}`);
  if (frontier <= offset) continue;
  const frame = renderFrame(0);
  if (!ArrayBuffer.isView(frame) || frame.byteLength !== 64000) {
    throw new Error(`invalid frame at ${frontier}`);
  }
  if (frontier > offset + warmup) {
    const frameSha = createHash('sha256').update(frame).digest();
    const frameHex = frameSha.toString('hex');
    unique.add(frameHex);
    chain = createHash('sha256').update(chain).update(frameSha).digest();
  }
}
const artifact = fs.readFileSync(artifactPath);
console.log(
  `PMLE_OCI_PRESENTATION_ORACLE|PASS|samples=${samples}|warmup=${warmup}` +
  `|unique=${unique.size}|stream_offset=${offset}|frontier=${frontier}` +
  `|frame_bytes=64000|export_shape=${exportShape}` +
  `|artifact_sha256=${createHash('sha256').update(artifact).digest('hex')}` +
  `|stream_sha256=${expandedSha}|chain_sha256=${chain.toString('hex')}`);
engine.release();
