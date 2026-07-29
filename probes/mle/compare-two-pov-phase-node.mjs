#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const coordinatorPath = path.join(
  root, 'probes/mle/dvl2-world-raster-coordinator.mjs');
const authorityPath = path.join(
  root, 'artifacts/performance/pmle-live-frame-hud/'
    + 'authority-candidate-66dd235cde82.js');
const rendererPath = path.join(
  root, 'artifacts/performance/pmle-live-frame-hud/'
    + 'renderer-c60a34dd81d6.js');
const exactPath = path.join(
  root, 'artifacts/performance/pmle-database-frames/'
    + 'presentation-decps-lean-byref-status-cache-4646503ae116.js');
const fixture = JSON.parse(fs.readFileSync(path.join(
  root, 'tests/fixtures/mle-live-deathmatch-2026-07-23.json')));
const iwad = fs.readFileSync(path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad'));
const tablePack = fs.readFileSync(path.join(
  root, 'probes/mle/teavm-engine/target/canonical-runtime-v2.bin'));
const inputs = [
  ['RendererPack', 'loadRendererPackChunk', 'world-raster-pack/free-live-render.pack'],
  ['WallTextures', 'loadWallTextureChunk', '../../target/free-live-renderer/assets-v1/wall_texture.bin'],
  ['FlatTextures', 'loadFlatTextureChunk', '../../target/free-live-renderer/assets-v1/flat.bin'],
  ['CompositorPack', 'loadCompositorPackChunk', '../../target/free-live-renderer/free-live-render.pack'],
  ['CompositorSprites', 'loadCompositorSpriteChunk', '../../target/free-live-renderer/assets-v1/sprite_patch.bin'],
  ['CompositorUi', 'loadCompositorUiChunk', '../../target/free-live-renderer/assets-v1/ui_patch.bin'],
].map(([kind, loader, relative]) => [
  kind,
  loader,
  fs.readFileSync(path.resolve(
    root, 'probes/mle/free-live-teavm/target', relative)),
]);

const stubUrl = 'data:text/javascript,'
  + encodeURIComponent('export default {};');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'doomdb-two-pov-phase-'));

function coordinatorModule(source, label) {
  const authorityUrl = `${pathToFileURL(authorityPath).href}?phase=${label}`;
  const rendererUrl = `${pathToFileURL(rendererPath).href}?phase=${label}`;
  const transformed = source
    .replace(
      "import * as engine from 'doom_dvl2_engine';",
      `import * as engine from '${authorityUrl}';`)
    .replace(
      "import * as renderer from 'doom_live_renderer';",
      `import * as renderer from '${rendererUrl}';`)
    .replace(
      "import * as compositor from 'doom_live_compositor';",
      `import * as compositor from '${rendererUrl}';`)
    .replace(
      "import oracledb from 'mle-js-oracledb';",
      `import oracledb from '${stubUrl}';`);
  const output = path.join(temporary, `${label}.mjs`);
  fs.writeFileSync(output, transformed);
  return import(pathToFileURL(output).href);
}

function baselineSource() {
  return execFileSync(
    'git', ['show', 'HEAD:probes/mle/dvl2-world-raster-coordinator.mjs'],
    {cwd: root, encoding: 'utf8', maxBuffer: 2 * 1024 * 1024});
}

function load(allocate, write, bytes, label) {
  if (allocate(bytes.length) !== bytes.length) {
    throw new Error(`${label} allocation failed`);
  }
  for (let offset = 0; offset < bytes.length; offset += 16_000) {
    const chunk = bytes.subarray(offset, offset + 16_000);
    if (write(offset, chunk) !== offset + chunk.length) {
      throw new Error(`${label} load failed at ${offset}`);
    }
  }
}

function canonicalSha(api) {
  const text = api.canonicalState();
  return createHash('sha256').update(text).digest('hex');
}

function commands() {
  const expanded = [];
  for (const run of fixture.runs) {
    for (let repeat = 0; repeat < run.repeat; repeat++) {
      expanded.push({
        membership: run.membership,
        bytes: Uint8Array.from(Buffer.from(run.command, 'hex')),
      });
    }
  }
  if (expanded.length !== fixture.tics) {
    throw new Error('command fixture expansion mismatch');
  }
  return expanded;
}

async function prepare(source, label) {
  const api = await coordinatorModule(source, label);
  load(api.allocateIwad, api.loadIwadChunk, iwad, `${label} IWAD`);
  load(
    api.allocateTablePack, api.loadTablePackChunk, tablePack,
    `${label} table pack`);
  for (const [kind, loader, bytes] of inputs) {
    load(
      api[`allocate${kind}`], api[loader], bytes,
      `${label} ${kind}`);
    const finalized = api[`finalize${kind}`]();
    if (finalized !== bytes.length) {
      throw new Error(`${label} ${kind} finalize mismatch`);
    }
  }
  const initialized = api.initializeMultiplayerGame(2, 1, 3, 1, 1);
  if (typeof initialized !== 'string'
      || !initialized.includes('state=multiplayer-initialized|gametic=0|')) {
    throw new Error(`${label} initialization mismatch`);
  }
  return api;
}

async function prepareExact() {
  const api = await import(`${pathToFileURL(exactPath).href}?phase=exact`);
  load(api.allocateIwad, api.loadIwadChunk, iwad, 'exact IWAD');
  load(
    api.allocateTablePack, api.loadTablePackChunk, tablePack,
    'exact table pack');
  const initialized = api.initializeMultiplayerGame(2, 1, 3, 1, 1);
  if (typeof initialized !== 'string'
      || !initialized.includes('state=multiplayer-initialized|gametic=0|')) {
    throw new Error('exact initialization mismatch');
  }
  return api;
}

function percentile(values, fraction) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
}

async function run(api, stream, frames) {
  const timings = [];
  const firstFrames = [];
  for (let index = 0; index < frames; index++) {
    const command = stream[index];
    const tic = api.stepOnly(2, command.membership, command.bytes);
    if (tic !== index + 1) throw new Error(`frontier mismatch at ${tic}`);
    const started = performance.now();
    for (let player = 0; player < 2; player++) {
      api.renderConfirmedTemporalFrame(player, tic);
      if (index < 16) {
        firstFrames.push(Buffer.from(api.frameChunk(0, 64_000)));
      }
    }
    timings.push(performance.now() - started);
  }
  return {
    timings,
    firstFrames,
    canonicalSha256: canonicalSha(api),
  };
}

async function exactFrames(api, stream, frames = 16) {
  const output = [];
  for (let index = 0; index < frames; index++) {
    const command = stream[index];
    const tic = api.stepMultiplayerAuthoritative(
      2, command.membership, command.bytes);
    if (tic !== index + 1) throw new Error(`exact frontier mismatch at ${tic}`);
    for (let player = 0; player < 2; player++) {
      output.push(Buffer.from(api.renderPlayerFrameByRef(player)));
    }
  }
  return output;
}

function meanDifferencePercent(frames, exact) {
  let different = 0;
  let pixels = 0;
  for (let index = 0; index < exact.length; index++) {
    const actual = frames[index];
    const expected = exact[index];
    for (let y = 0; y < 200; y++) {
      for (let x = 0; x < 320; x++) {
        if (actual[x * 200 + y] !== expected[y * 320 + x]) different++;
        pixels++;
      }
    }
  }
  return different * 100 / pixels;
}

const stream = commands();
const frames = Math.min(
  Number.parseInt(process.argv[2] ?? '600', 10), stream.length);
if (!Number.isInteger(frames) || frames < 32) {
  throw new Error('frame count must be at least 32');
}
const baseline = await prepare(baselineSource(), 'baseline');
const candidate = await prepare(
  fs.readFileSync(coordinatorPath, 'utf8'), 'candidate');
const baselineResult = await run(baseline, stream, frames);
const candidateResult = await run(candidate, stream, frames);
const exact = await prepareExact();
const referenceFrames = await exactFrames(exact, stream);
if (baselineResult.canonicalSha256 !== candidateResult.canonicalSha256) {
  throw new Error('phase shift changed authoritative simulation state');
}
const mean = values =>
  values.reduce((sum, value) => sum + value, 0) / values.length;
const report = (label, result) => ({
  label,
  meanMs: mean(result.timings),
  p50Ms: percentile(result.timings, .5),
  p95Ms: percentile(result.timings, .95),
  p99Ms: percentile(result.timings, .99),
  maxMs: Math.max(...result.timings),
});
process.stdout.write(
  `PMLE_TWO_POV_PHASE_NODE|DIAGNOSTIC_NOT_GATE|frames=${frames}`
  + `|baseline=${JSON.stringify(report('baseline', baselineResult))}`
  + `|candidate=${JSON.stringify(report('candidate', candidateResult))}`
  + `|first_32_frame_differences=${
    candidateResult.firstFrames.filter(
      (value, index) => !value.equals(baselineResult.firstFrames[index])).length}`
  + `|baseline_exact_difference_percent=${
    meanDifferencePercent(baselineResult.firstFrames, referenceFrames).toFixed(3)}`
  + `|candidate_exact_difference_percent=${
    meanDifferencePercent(candidateResult.firstFrames, referenceFrames).toFixed(3)}`
  + `|canonical_sha256=${candidateResult.canonicalSha256}\n`);
