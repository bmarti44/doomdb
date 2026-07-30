#!/usr/bin/env node

import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '..');
const coordinatorPath = path.resolve(
  process.argv[2] ?? path.join(
    root, 'artifacts/performance/pmle-exact-live/'
      + 'coordinator-temporal-solo-candidate.mjs'));
const keyframeInterval = Number.parseInt(process.argv[3] ?? '2', 10);
if (![2,3].includes(keyframeInterval)) {
  throw new Error('temporal coordinator test interval must be 2 or 3');
}
const rendererPath = path.join(
  root, 'artifacts/performance/pmle-exact-live/'
    + 'renderer-bsp-precomputed-geometry-production.js');
const iwadPath = path.join(
  root, 'client/dist/play/freedoom1-7323bcc168c5.bin');
const tablePath = path.join(
  root, 'client/dist/play/canonical-runtime-v2-058cd0df9444.bin');
const temporary = mkdtempSync(path.join(os.tmpdir(), 'doomdb-temporal-solo-'));

globalThis.__doomdbTemporalWrites = [];
globalThis.OracleBlob = class OracleBlob {
  static LOB_READWRITE = 2;
  open() {}
  write(position, bytes) {
    assert.equal(position, 1);
    this.bytes = Uint8Array.from(bytes);
  }
  close() {}
};

function load(allocate, write, bytes, label) {
  assert.equal(allocate(bytes.byteLength), bytes.byteLength, `${label} allocate`);
  for (let offset = 0; offset < bytes.byteLength; offset += 16_000) {
    const chunk = bytes.subarray(offset, offset + 16_000);
    assert.equal(write(offset, chunk), offset + chunk.byteLength, `${label} load`);
  }
}

function playerCamera(api) {
  const length = api.presentationWorldSnapshotLength(0);
  assert.ok(Number.isInteger(length) && length >= 56,
    `invalid player world snapshot length ${length}`);
  const bytes = api.presentationWorldSnapshotChunk(0, length);
  assert.ok(bytes instanceof Uint8Array && bytes.byteLength === length,
    'invalid player world snapshot payload');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return {
    x: view.getInt32(36, true),
    y: view.getInt32(40, true),
    angle: view.getInt32(48, true) & 0xffff,
  };
}

try {
  const stubPath = path.join(temporary, 'oracledb.mjs');
  writeFileSync(stubPath, `
export default {
  BIND_OUT: 3003,
  ORACLE_BLOB: 2019,
  defaultConnection() {
    return {
      execute(sql, binds) {
        const payload = new globalThis.OracleBlob();
        globalThis.__doomdbTemporalWrites.push({sql, binds, payload});
        return {rowsAffected: 1, outBinds: {payload: [payload]}};
      },
    };
  },
};
`);
  const rendererUrl = pathToFileURL(rendererPath).href;
  const transformed = readFileSync(coordinatorPath, 'utf8')
    .replace(
      "import * as engine from 'doom_dvl2_engine';",
      `import * as engine from '${rendererUrl}';`)
    .replace(
      "import * as renderer from 'doom_live_renderer';",
      `import * as renderer from '${rendererUrl}';`)
    .replace(
      "import * as compositor from 'doom_live_compositor';",
      `import * as compositor from '${rendererUrl}';`)
    .replace(
      "import oracledb from 'mle-js-oracledb';",
      `import oracledb from '${pathToFileURL(stubPath).href}';`);
  const modulePath = path.join(temporary, 'coordinator.mjs');
  writeFileSync(modulePath, transformed);
  const api = await import(pathToFileURL(modulePath).href);
  const iwad = new Uint8Array(readFileSync(iwadPath));
  const tables = new Uint8Array(readFileSync(tablePath));
  const reloadAuthorityAssets = label => {
    load(api.allocateIwad, api.loadIwadChunk, iwad, `${label} IWAD`);
    load(
      api.allocateTablePack, api.loadTablePackChunk, tables,
      `${label} tables`);
  };
  reloadAuthorityAssets('initial');
  const initialized = api.initializeMultiplayerGame(2, 0, 3, 1, 1);
  assert.match(initialized, /state=multiplayer-initialized\|gametic=0\|/);

  const matchId = '0123456789abcdef0123456789abcdef';
  const command = new Uint8Array(32);
  command[0] = 25;
  const writesPerTic = [];
  let cameraAtFirstForwardTic;
  for (let tic = 1; tic <= 7; tic++) {
    assert.equal(api.stepOnly(2, 1, command), tic, `step tic ${tic}`);
    if (tic === 1) cameraAtFirstForwardTic = playerCamera(api);
    const before = globalThis.__doomdbTemporalWrites.length;
    assert.equal(
      api.prepareMatchViews(matchId, 1, 1, 1, tic), 64_016,
      `prepare tic ${tic}`);
    assert.equal(
      api.publishPreparedMatchViews(matchId, 1, 1, 1, tic), 64_016,
      `publish tic ${tic}`);
    writesPerTic.push(globalThis.__doomdbTemporalWrites.length - before);
  }
  assert.deepEqual(
    writesPerTic,
    keyframeInterval === 2
      ? [1, 0, 2, 0, 2, 0, 2]
      : [1, 0, 0, 3, 0, 0, 3]);
  const writes = globalThis.__doomdbTemporalWrites;
  assert.deepEqual(writes.map(entry => entry.binds.frameTic), [1,2,3,4,5,6,7]);
  for (const [index, entry] of writes.entries()) {
    const bytes = entry.payload.bytes;
    assert.equal(bytes.byteLength, 64_016);
    assert.deepEqual([...bytes.subarray(0, 4)], [68,80,68,49]);
    assert.equal(new DataView(
      bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(4), index + 1);
    assert.equal(bytes[8], 1);
    assert.equal(bytes[11], 1);
  }
  const exactEndpointDiffs=[];
  for(let tic=1;tic+keyframeInterval<=7;tic+=keyframeInterval) {
    const previous=writes[tic-1].payload.bytes;
    const current=writes[tic+keyframeInterval-1].payload.bytes;
    let changed=0;
    for(let offset=16;offset<64_016;offset+=1) {
      if(previous[offset]!==current[offset])changed+=1;
    }
    exactEndpointDiffs.push(changed);
    assert.ok(changed>=1_000,
      `current-camera keyframes changed only ${changed} pixels at tic ${tic}`);
  }

  // Every intermediate frame is the exact spatial phase mix between adjacent
  // keyframes. This checks every pixel, not a sampled visual checksum.
  for (let priorTic = 1;
      priorTic + keyframeInterval <= 7;
      priorTic += keyframeInterval) {
    const previous = writes[priorTic - 1].payload.bytes;
    const current =
      writes[priorTic + keyframeInterval - 1].payload.bytes;
    assert.equal(previous[9], current[9], `palette changed at tic ${priorTic}`);
    for (let phase = 1; phase < keyframeInterval; phase++) {
      const synthetic = writes[priorTic + phase - 1].payload.bytes;
      const tic = priorTic + phase;
      for (let row = 0; row < 200; row++) {
        for (let column = 0; column < 320; column++) {
          const offset = 16 + row * 320 + column;
          const choosePrevious = keyframeInterval === 2
            ? ((row + column + tic) & 1) === 0
            : ((row * 320 + column + tic) % 3) >= phase;
          const expected = choosePrevious
            ? previous[offset] : current[offset];
          assert.equal(
            synthetic[offset], expected,
            `synthetic mismatch tic=${tic} row=${row} column=${column}`);
        }
      }
    }
  }

  // A changed framebuffer is not sufficient evidence that controls work:
  // weapon/world animation changes pixels while the player remains still.
  // Pin the authoritative pose exported by the same retained MLE engine.
  const cameraAfterHeldForward = playerCamera(api);
  const forwardDisplacement = Math.hypot(
    cameraAfterHeldForward.x - cameraAtFirstForwardTic.x,
    cameraAfterHeldForward.y - cameraAtFirstForwardTic.y);
  assert.ok(forwardDisplacement > 0,
    'held forward command did not move the authoritative player');
  const turnLeft = new Uint8Array(32);
  new DataView(turnLeft.buffer).setInt16(2, 320, false);
  for (let tic = 8; tic <= 14; tic++) {
    assert.equal(api.stepOnly(2, 1, turnLeft), tic, `turn step tic ${tic}`);
  }
  const cameraAfterHeldTurn = playerCamera(api);
  assert.notEqual(cameraAfterHeldTurn.angle, cameraAfterHeldForward.angle,
    'held turn command did not rotate the authoritative player');

  // A new generation cannot inherit a prior-generation interpolation source.
  api.release();
  reloadAuthorityAssets('recovery');
  const recovered = api.initializeMultiplayerGame(2, 0, 3, 1, 1);
  assert.match(recovered, /state=multiplayer-initialized\|gametic=0\|/);
  assert.equal(api.stepOnly(2, 1, command), 1);
  let before = globalThis.__doomdbTemporalWrites.length;
  assert.equal(api.prepareMatchViews(matchId, 1, 1, 2, 1), 64_016);
  assert.equal(api.publishPreparedMatchViews(matchId, 1, 1, 2, 1), 64_016);
  assert.equal(globalThis.__doomdbTemporalWrites.length - before, 1);
  assert.equal(globalThis.__doomdbTemporalWrites.at(-1).binds.frameTic, 1);

  // Multiplayer remains the complete exact-every-tic shared-view path.
  api.release();
  reloadAuthorityAssets('multiplayer');
  const multiplayer = api.initializeMultiplayerGame(2, 1, 3, 1, 1);
  assert.match(multiplayer, /state=multiplayer-initialized\|gametic=0\|/);
  for (let tic = 1; tic <= 4; tic++) {
    assert.equal(api.stepOnly(2, 3, command), tic);
    before = globalThis.__doomdbTemporalWrites.length;
    assert.equal(api.prepareMatchViews(matchId, 3, 1, 3, tic), 128_016);
    assert.equal(api.publishPreparedMatchViews(matchId, 3, 1, 3, tic), 128_016);
    assert.equal(globalThis.__doomdbTemporalWrites.length - before, 1);
    const payload = globalThis.__doomdbTemporalWrites.at(-1).payload.bytes;
    assert.equal(payload.byteLength, 128_016);
    assert.equal(payload[8], 3);
    assert.equal(
      new DataView(payload.buffer,payload.byteOffset,payload.byteLength)
        .getUint32(4),
      tic);
  }
  api.release();
  process.stdout.write(
    'PASS PMLE-TEMPORAL-SOLO-COORDINATOR '
      + `tics=7 writes=7 interval=${keyframeInterval}`
      + ` exact=${keyframeInterval===2?4:3}`
      + ` synthesized=${keyframeInterval===2?3:4}`
      + ` forward_displacement=${forwardDisplacement.toFixed(3)}`
      + ` turn_delta=${
        (cameraAfterHeldTurn.angle-cameraAfterHeldForward.angle+65536)%65536}`
      + ` keyframe_changed_pixels=${exactEndpointDiffs.join('/')}`
      + ' movement=PASS consecutive=YES generation_reset=PASS'
      + ' multiplayer_exact=PASS\n');
} finally {
  rmSync(temporary, {recursive: true, force: true});
}
