#!/usr/bin/env node

import {createHash} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = path.resolve(import.meta.dirname, '../..');
const liveRenderWidth = Number.parseInt(
  process.env.PMLE_FREE_LIVE_RENDER_WIDTH ?? '106', 10);
if (![64, 106, 160].includes(liveRenderWidth)) {
  throw new Error('PMLE_FREE_LIVE_RENDER_WIDTH must be 64, 106, or 160');
}
const livePixelScale = Math.floor(320 / liveRenderWidth);
const allowVisualVariant =
  process.env.PMLE_FREE_LIVE_ALLOW_VISUAL_VARIANT === 'YES';
const authorityPath = path.join(
  root,
  'probes/mle/teavm-engine/target/javascript/'
    + 'doom-mle-presentation-engine-headless.js',
);
const rendererPath = path.join(
  root,
  'probes/mle/free-live-teavm/target/javascript/'
    + 'doom-mle-free-live-unified-renderer.js',
);
const iwadPath = path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad',
);
const tablePath = path.join(
  root, 'probes/mle/teavm-engine/target/canonical-runtime-v2.bin',
);
const packPath = path.join(
  root,
  'probes/mle/free-live-teavm/target/world-raster-pack/'
    + 'free-live-render.pack',
);
const compositorPackPath = path.join(
  root, 'probes/mle/target/free-live-renderer/free-live-render.pack',
);
const assets = path.join(
  root, 'probes/mle/target/free-live-renderer/assets-v1',
);
const iwadBytes = fs.readFileSync(iwadPath);
const tableBytes = fs.readFileSync(tablePath);
const acceptedRoute = JSON.parse(fs.readFileSync(path.join(
  root, 'artifacts/t8.1-live/mocha-e1m1-skill3-route.json')));

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

function sha(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

const authority = await import(pathToFileURL(authorityPath).href);
const renderer = await import(pathToFileURL(rendererPath).href);
load(authority.allocateIwad, authority.loadIwadChunk, iwadBytes);
load(
  authority.allocateTablePack,
  authority.loadTablePackChunk,
  tableBytes,
);
const initialized = authority.initializeMultiplayerGame(2, 0, 3, 1, 1);
if (!initialized.includes('state=multiplayer-initialized|gametic=0|')) {
  throw new Error(`authority initialization failed: ${initialized}`);
}

const pack = fs.readFileSync(packPath);
load(renderer.allocatePack, renderer.loadPackChunk, pack);
if (renderer.finalizePack() !== pack.length) {
  throw new Error('dynamic world pack finalize mismatch');
}
for (const [name, allocate, write, finalize] of [
  ['wall_texture.bin', renderer.allocateWallTextures,
    renderer.loadWallTextureChunk, renderer.finalizeWallTextures],
  ['flat.bin', renderer.allocateFlatTextures,
    renderer.loadFlatTextureChunk, renderer.finalizeFlatTextures],
]) {
  const bytes = fs.readFileSync(path.join(assets, name));
  load(allocate, write, bytes);
  if (finalize() !== bytes.length) {
    throw new Error(`${name} finalize mismatch`);
  }
}
const compositorPack = fs.readFileSync(compositorPackPath);
load(
  renderer.allocateCompositorPack,
  renderer.loadCompositorPackChunk,
  compositorPack,
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
  const bytes = fs.readFileSync(path.join(assets, name));
  load(allocate, write, bytes);
  if (finalize() !== bytes.length) {
    throw new Error(`${name} compositor finalize mismatch`);
  }
}

const length = authority.presentationWorldGeometryAndSidesSnapshotLength(0);
const exported = authority.presentationWorldSnapshotNativeByRef();
if (!(exported instanceof Uint8Array) || length > exported.byteLength) {
  throw new Error('authority native world snapshot shape mismatch');
}
const baseline = exported.slice(0, length);
if (process.env.PMLE_DVL2_SNAPSHOT_BIN) {
  fs.writeFileSync(process.env.PMLE_DVL2_SNAPSHOT_BIN, baseline);
}
const header = new DataView(
  baseline.buffer, baseline.byteOffset, baseline.byteLength);
const sectorCount = header.getInt32(16, true);
const sectorOffset = header.getInt32(24, true);
const sideCount = header.getInt32(192, true);
const sideOffset = header.getInt32(196, true);
if (header.getInt32(0, true) !== 0x324c5644
    || header.getInt32(4, true) !== 2
    || header.getInt32(20, true) !== 0
    || sectorCount < 1 || sideCount < 1
    || length !== sideOffset + sideCount * 8) {
  throw new Error('DVL2 geometry+sidedef snapshot contract mismatch');
}

function render(snapshot) {
  renderer.loadCompactSnapshot(snapshot);
  renderer.renderLoadedCompactFrameCoarse(snapshot);
  const frame = renderer.frameNativeByRef();
  if (!(frame instanceof Uint8Array) || frame.byteLength !== 64_000) {
    throw new Error('dynamic world framebuffer shape mismatch');
  }
  for (let logical = 0; logical < liveRenderWidth; logical += 1) {
    const source = logical * livePixelScale * 200;
    for (let copy = 1; copy < livePixelScale; copy += 1) {
      const target = source + copy * 200;
      if (!Buffer.from(frame.subarray(source, source + 168)).equals(
        Buffer.from(frame.subarray(target, target + 168)),
      )) {
        throw new Error(
          `coarse horizontal expansion mismatch at ${logical}/${copy}`,
        );
      }
    }
  }
  const tailSource =
    (liveRenderWidth - 1) * livePixelScale * 200;
  for (let column = liveRenderWidth * livePixelScale;
       column < 320; column += 1) {
    if (!Buffer.from(frame.subarray(
      tailSource, tailSource + 168)).equals(
      Buffer.from(frame.subarray(column * 200, column * 200 + 168)),
    )) {
      throw new Error(`coarse horizontal tail mismatch at ${column}`);
    }
  }
  const solidDepth=renderer.solidDepthByRef();
  const wallDepth=renderer.wallDepthByRef();
  if(!ArrayBuffer.isView(solidDepth)||solidDepth.length!==liveRenderWidth
      ||!ArrayBuffer.isView(wallDepth)
      ||wallDepth.length!==liveRenderWidth*168) {
    throw new Error('retained wall-depth shape mismatch');
  }
  let partialPixels;
  if(typeof renderer.partialDepthPixelCount==='function') {
    partialPixels=renderer.partialDepthPixelCount();
  } else {
    partialPixels=0;
    for(let x=0;x<liveRenderWidth;x+=1) {
      const solid=solidDepth[x];
      const base=x*168;
      for(let y=0;y<168;y+=1) {
        const wall=wallDepth[base+y];
        if(Number.isFinite(wall)
            &&(!Number.isFinite(solid)||wall<solid))partialPixels+=1;
      }
    }
  }
  maximumPartialWallDepthPixels=Math.max(
    maximumPartialWallDepthPixels,partialPixels);
  return sha(frame);
}

let maximumPartialWallDepthPixels=0;
const baselineSha = render(baseline);
const baselineRepeatSha = render(baseline);
if (baselineRepeatSha !== baselineSha) {
  throw new Error(
    `identical DVL2 snapshot is not frame-deterministic: `
      + `${baselineSha}/${baselineRepeatSha}`,
  );
}
if (process.env.PMLE_DVL2_FRAME_PPM) {
  const count = iwadBytes.readUInt32LE(4);
  const directory = iwadBytes.readUInt32LE(8);
  let palette;
  for (let index = 0; index < count; index += 1) {
    const at = directory + index * 16;
    const name = iwadBytes.toString('ascii', at + 8, at + 16)
      .replace(/\0.*$/s, '');
    if (name !== 'PLAYPAL') continue;
    const offset = iwadBytes.readUInt32LE(at);
    palette = iwadBytes.subarray(offset, offset + 768);
    break;
  }
  if (!palette || palette.length !== 768) {
    throw new Error('PLAYPAL palette missing from visual capture IWAD');
  }
  const frame = renderer.frameNativeByRef();
  const rgb = Buffer.alloc(320 * 200 * 3);
  for (let y = 0; y < 200; y += 1) {
    for (let x = 0; x < 320; x += 1) {
      const color = frame[x * 200 + y] & 255;
      palette.copy(rgb, (y * 320 + x) * 3, color * 3, color * 3 + 3);
    }
  }
  fs.writeFileSync(
    process.env.PMLE_DVL2_FRAME_PPM,
    Buffer.concat([Buffer.from('P6\n320 200\n255\n'), rgb]),
  );
}

const dirtyLength =
  authority.presentationWorldGeometryDeltaSnapshotLength(0);
const dirtyExport = authority.presentationWorldSnapshotNativeByRef();
const dirtyBaseline = dirtyExport.slice(0, dirtyLength);
const dirtyHeader = new DataView(
  dirtyBaseline.buffer, dirtyBaseline.byteOffset, dirtyBaseline.byteLength);
const dirtySectorCount = dirtyHeader.getInt32(16, true);
const dirtySideOffset = dirtyHeader.getInt32(196, true);
let dirtyFrameSha;
try {
  dirtyFrameSha = render(dirtyBaseline);
} catch (error) {
  throw new Error(
    `DVL6 renderer rejected initial snapshot: `
      + `magic=${dirtyHeader.getInt32(0, true).toString(16)} `
      + `version=${dirtyHeader.getInt32(4, true)} `
      + `sectors=${dirtyHeader.getInt32(16, true)}/${sectorCount} `
      + `mobjs=${dirtyHeader.getInt32(20, true)} `
      + `sectorOffset=${dirtyHeader.getInt32(24, true)} `
      + `mobjOffset=${dirtyHeader.getInt32(28, true)} `
      + `headerLength=${dirtyHeader.getInt32(32, true)} `
      + `sides=${dirtyHeader.getInt32(192, true)}/${sideCount} `
      + `sideOffset=${dirtySideOffset} `
      + `sideBytes=${dirtyHeader.getInt32(200, true)} `
      + `sectorBytes=${dirtyHeader.getInt32(204, true)} `
      + `actualLength=${dirtyLength}: ${error.message}`,
    { cause: error },
  );
}
if (dirtyHeader.getInt32(0, true) !== 0x364c5644
    || dirtyHeader.getInt32(4, true) !== 6
    || dirtyHeader.getInt32(16, true) !== sectorCount
    || dirtyHeader.getInt32(192, true) !== sideCount
    || dirtyHeader.getInt32(200, true) !== 18
    || dirtyHeader.getInt32(204, true) !== 18
    || dirtySideOffset !== sectorOffset + dirtySectorCount * 18
    || dirtyLength !== dirtySideOffset + sideCount * 18
    || dirtyFrameSha !== baselineSha) {
  throw new Error(
    `DVL6 initial dirty-world snapshot contract mismatch: `
      + `magic=${dirtyHeader.getInt32(0, true).toString(16)} `
      + `version=${dirtyHeader.getInt32(4, true)} `
      + `sectors=${dirtyHeader.getInt32(16, true)}/${sectorCount} `
      + `sides=${dirtyHeader.getInt32(192, true)}/${sideCount} `
      + `sideOffset=${dirtySideOffset}/`
      + `${sectorOffset + dirtySectorCount * 18} `
      + `sectorBytes=${dirtyHeader.getInt32(204, true)} `
      + `sideBytes=${dirtyHeader.getInt32(200, true)} `
      + `length=${dirtyLength}/${dirtySideOffset + sideCount * 18} `
      + `frame=${dirtyFrameSha}/${baselineSha}`,
  );
}
const steadyLength =
  authority.presentationWorldGeometryDeltaSnapshotLength(0);
const steadyExport = authority.presentationWorldSnapshotNativeByRef();
const steadyBaseline = steadyExport.slice(0, steadyLength);
const steadyHeader = new DataView(
  steadyBaseline.buffer, steadyBaseline.byteOffset, steadyBaseline.byteLength);
if (steadyHeader.getInt32(0, true) !== 0x364c5644
    || steadyHeader.getInt32(4, true) !== 6
    || steadyHeader.getInt32(16, true) !== 0
    || steadyHeader.getInt32(192, true) !== 0
    || steadyHeader.getInt32(196, true) !== sectorOffset
    || steadyLength !== sectorOffset
    || render(steadyBaseline) !== baselineSha) {
  throw new Error('DVL6 unchanged world state was not suppressed exactly');
}

const sectorLength = authority.presentationWorldGeometrySnapshotLength(0);
const sectorExport = authority.presentationWorldSnapshotNativeByRef();
const sectorBaseline = sectorExport.slice(0, sectorLength);
const sectorHeader = new DataView(
  sectorBaseline.buffer, sectorBaseline.byteOffset, sectorBaseline.byteLength);
if (sectorHeader.getInt32(0, true) !== 0x334c5644
    || sectorHeader.getInt32(4, true) !== 3
    || sectorHeader.getInt32(16, true) !== sectorCount
    || sectorHeader.getInt32(192, true) !== 0
    || render(sectorBaseline) !== baselineSha) {
  throw new Error('DVL3 sector-only update did not retain initialized sides');
}
for (let dirty = 0; dirty < dirtySectorCount; dirty += 1) {
  const at = sectorOffset + dirty * 18;
  const sector = dirtyHeader.getUint16(at, true);
  const baselineAt = sectorOffset + sector * 16;
  if (sector !== dirty
      || dirtyHeader.getInt32(at + 2, true)
          !== sectorHeader.getInt32(baselineAt, true)
      || dirtyHeader.getInt32(at + 6, true)
          !== sectorHeader.getInt32(baselineAt + 4, true)
      || dirtyHeader.getInt16(at + 10, true)
          !== sectorHeader.getInt16(baselineAt + 8, true)
      || dirtyHeader.getUint16(at + 12, true)
          !== sectorHeader.getUint16(baselineAt + 10, true)
      || dirtyHeader.getUint16(at + 14, true)
          !== sectorHeader.getUint16(baselineAt + 12, true)
      || dirtyHeader.getInt16(at + 16, true)
          !== sectorHeader.getInt16(baselineAt + 14, true)) {
    throw new Error(`DVL6 initial sector mismatch: ${dirty}/${sector}`);
  }
}

const heights = sectorBaseline.slice();
const heightsView = new DataView(
  heights.buffer, heights.byteOffset, heights.byteLength);
for (let sector = 0; sector < sectorCount; sector += 1) {
  const at = sectorOffset + sector * 16;
  const floor = heightsView.getInt32(at, true);
  const ceiling = heightsView.getInt32(at + 4, true);
  if (ceiling - floor >= 32 * 65_536) {
    heightsView.setInt32(at, floor + 8 * 65_536, true);
    heightsView.setInt32(at + 4, ceiling - 8 * 65_536, true);
  }
}
const heightsSha = render(heights);
const afterHeightsSha = render(sectorBaseline);
const dirtyHeights = dirtyBaseline.slice();
const dirtyHeightsView = new DataView(
  dirtyHeights.buffer, dirtyHeights.byteOffset, dirtyHeights.byteLength);
for (let dirty = 0; dirty < dirtySectorCount; dirty += 1) {
  const at = sectorOffset + dirty * 18;
  const floor = dirtyHeightsView.getInt32(at + 2, true);
  const ceiling = dirtyHeightsView.getInt32(at + 6, true);
  if (ceiling - floor >= 32 * 65_536) {
    dirtyHeightsView.setInt32(at + 2, floor + 8 * 65_536, true);
    dirtyHeightsView.setInt32(at + 6, ceiling - 8 * 65_536, true);
  }
}
const dirtyHeightsSha = render(dirtyHeights);
const dirtyHeightsRestoredSha = render(dirtyBaseline);

const lights = sectorBaseline.slice();
const lightsView = new DataView(
  lights.buffer, lights.byteOffset, lights.byteLength);
for (let sector = 0; sector < sectorCount; sector += 1) {
  lightsView.setInt16(sectorOffset + sector * 16 + 8, 0, true);
}
const lightsSha = render(lights);
const afterLightsSha = render(sectorBaseline);
const dirtyLights = dirtyBaseline.slice();
const dirtyLightsView = new DataView(
  dirtyLights.buffer, dirtyLights.byteOffset, dirtyLights.byteLength);
for (let dirty = 0; dirty < dirtySectorCount; dirty += 1) {
  dirtyLightsView.setInt16(sectorOffset + dirty * 18 + 10, 0, true);
}
const dirtyLightsSha = render(dirtyLights);
const dirtyLightsRestoredSha = render(dirtyBaseline);

const sides = baseline.slice();
const sidesView = new DataView(
  sides.buffer, sides.byteOffset, sides.byteLength);
for (let side = 0; side < sideCount; side += 1) {
  sidesView.setUint16(sideOffset + side * 8 + 4, 1, true);
}
const sidesSha = render(sides);
const restoredSha = render(baseline);
const dirtySides = dirtyBaseline.slice();
const dirtySidesView = new DataView(
  dirtySides.buffer, dirtySides.byteOffset, dirtySides.byteLength);
for (let dirty = 0; dirty < sideCount; dirty += 1) {
  dirtySidesView.setUint16(dirtySideOffset + dirty * 18 + 6, 1, true);
}
const dirtySidesSha = render(dirtySides);
const dirtyRestoredSha = render(dirtyBaseline);
const dirtyOffsets = dirtyBaseline.slice();
const dirtyOffsetsView = new DataView(
  dirtyOffsets.buffer, dirtyOffsets.byteOffset, dirtyOffsets.byteLength);
for (let dirty = 0; dirty < sideCount; dirty += 1) {
  const at = dirtySideOffset + dirty * 18 + 10;
  dirtyOffsetsView.setInt32(
    at, dirtyOffsetsView.getInt32(at, true) + 65_536, true);
}
const dirtyOffsetsSha = render(dirtyOffsets);
const dirtyOffsetsRestoredSha = render(dirtyBaseline);

if (new Set([
  baselineSha, heightsSha, lightsSha, sidesSha, dirtyOffsetsSha,
]).size !== 5
    || dirtySidesSha !== sidesSha
    || dirtyHeightsSha !== heightsSha
    || dirtyLightsSha !== lightsSha
    || afterHeightsSha !== baselineSha
    || afterLightsSha !== baselineSha
    || dirtyHeightsRestoredSha !== baselineSha
    || dirtyLightsRestoredSha !== baselineSha
    || restoredSha !== baselineSha
    || dirtyRestoredSha !== baselineSha
    || dirtyOffsetsRestoredSha !== baselineSha) {
  throw new Error(
    `dynamic world mutation did not affect deterministic pixels: `
      + `${baselineSha}/${heightsSha}/${afterHeightsSha}`
      + `/${lightsSha}/${afterLightsSha}/${sidesSha}/${restoredSha}`
      + `/${dirtyHeightsSha}/${dirtyHeightsRestoredSha}`
      + `/${dirtyLightsSha}/${dirtyLightsRestoredSha}`
      + `/${dirtySidesSha}/${dirtyRestoredSha}`
      + `/${dirtyOffsetsSha}/${dirtyOffsetsRestoredSha}`,
  );
}

for (let tic = 0; tic < 8; tic += 1) {
  authority.stepMultiplayerAuthoritative(2, 3, new Uint8Array(32));
}
const animatedLength =
  authority.presentationWorldGeometryDeltaSnapshotLength(0);
const animatedExport = authority.presentationWorldSnapshotNativeByRef();
const animatedDelta = animatedExport.slice(0, animatedLength);
const animatedHeader = new DataView(
  animatedDelta.buffer, animatedDelta.byteOffset, animatedDelta.byteLength);
const animatedSectorCount = animatedHeader.getInt32(16, true);
const animatedDirtyCount = animatedHeader.getInt32(192, true);
const animatedSideOffset = animatedHeader.getInt32(196, true);
const animatedFullLength =
  authority.presentationWorldGeometryAndSidesSnapshotLength(0);
const animatedFullExport = authority.presentationWorldSnapshotNativeByRef();
const animatedFull = animatedFullExport.slice(0, animatedFullLength);
const animatedFullView = new DataView(
  animatedFull.buffer, animatedFull.byteOffset, animatedFull.byteLength);
const exactAnimatedSides = new Map();
for (let side = 0; side < sideCount; side += 1) {
  const baselineAt = sideOffset + side * 8;
  const currentAt = sideOffset + side * 8;
  const values = [
    animatedFullView.getUint16(currentAt, true),
    animatedFullView.getUint16(currentAt + 2, true),
    animatedFullView.getUint16(currentAt + 4, true),
    animatedFullView.getUint16(currentAt + 6, true),
  ];
  if (values.some(
    (value, index) =>
      value !== header.getUint16(baselineAt + index * 2, true),
  )) {
    exactAnimatedSides.set(side, values);
  }
}
if (animatedHeader.getInt32(0, true) !== 0x364c5644
    || animatedDirtyCount < exactAnimatedSides.size
    || animatedSideOffset !== sectorOffset + animatedSectorCount * 18
    || animatedLength !== animatedSideOffset + animatedDirtyCount * 18) {
  throw new Error('DVL6 animation-boundary dirty count is not exact');
}
let animatedOffsetSides = 0;
for (let dirty = 0; dirty < animatedDirtyCount; dirty += 1) {
  const at = animatedSideOffset + dirty * 18;
  const side = animatedHeader.getUint16(at, true);
  const currentAt = sideOffset + side * 8;
  const initialAt = dirtySideOffset + side * 18;
  if (dirtyHeader.getUint16(initialAt, true) !== side
      || animatedFullView.getUint16(currentAt, true)
          !== animatedHeader.getUint16(at + 2, true)
      || animatedFullView.getUint16(currentAt + 2, true)
          !== animatedHeader.getUint16(at + 4, true)
      || animatedFullView.getUint16(currentAt + 4, true)
          !== animatedHeader.getUint16(at + 6, true)
      || animatedFullView.getUint16(currentAt + 6, true)
          !== animatedHeader.getUint16(at + 8, true)) {
    throw new Error(`DVL6 animation-boundary side mismatch: ${side}`);
  }
  const offsetChanged =
    dirtyHeader.getInt32(initialAt + 10, true)
        !== animatedHeader.getInt32(at + 10, true)
    || dirtyHeader.getInt32(initialAt + 14, true)
        !== animatedHeader.getInt32(at + 14, true);
  const textureChanged = exactAnimatedSides.delete(side);
  if (!textureChanged && !offsetChanged) {
    throw new Error(`DVL6 emitted an unchanged side: ${side}`);
  }
  if (offsetChanged) animatedOffsetSides += 1;
}
if (exactAnimatedSides.size !== 0) {
  throw new Error('DVL6 animation-boundary omitted translated sides');
}

const compositorLength = authority.presentationCompositorSnapshotLength(0);
const compositorExport = authority.presentationWorldSnapshotNativeByRef();
const compositor = compositorExport.slice(0, compositorLength);
const compositorView = new DataView(
  compositor.buffer, compositor.byteOffset, compositor.byteLength);
const compositorMobjs = compositorView.getInt32(20, true);
if (compositorView.getInt32(0, true) !== 0x344c5644
    || compositorView.getInt32(4, true) !== 4
    || compositorMobjs < 2
    || compositorLength !== 208 + compositorMobjs * 24) {
  throw new Error('DVC4 compact mobj fixture is unavailable');
}

function dvc4WithRecords(records) {
  const snapshot = new Uint8Array(208 + records.length * 24);
  snapshot.set(compositor.subarray(0, 208));
  const view = new DataView(
    snapshot.buffer, snapshot.byteOffset, snapshot.byteLength);
  view.setInt32(20, records.length, true);
  view.setInt32(32, snapshot.length, true);
  records.forEach((record, index) => {
    if (record.byteLength !== 24) {
      throw new Error('invalid compact mobj record fixture');
    }
    snapshot.set(record, 208 + index * 24);
  });
  return snapshot;
}

function viewPixels() {
  const frame = renderer.frameNativeByRef();
  const view = Buffer.alloc(320 * 168);
  for (let x = 0; x < 320; x += 1) {
    view.set(frame.subarray(x * 200, x * 200 + 168), x * 168);
  }
  return view;
}

function resetCurrentWorld() {
  renderer.loadCompactSnapshot(animatedFull);
  renderer.renderLoadedCompactFrameCoarse(animatedFull);
  return viewPixels();
}

let visibleRecord = null;
let visibleRecordIndex = -1;
for (let mobj = 0; mobj < compositorMobjs; mobj += 1) {
  const record = compositor.slice(208 + mobj * 24, 208 + (mobj + 1) * 24);
  const before = resetCurrentWorld();
  renderer.composeWorldSpritesStage(dvc4WithRecords([record]));
  if (!viewPixels().equals(before)) {
    visibleRecord = record;
    visibleRecordIndex = mobj;
    break;
  }
}
if (visibleRecord === null) {
  throw new Error('DVC4 fixture contains no pixel-visible world sprite');
}

resetCurrentWorld();
renderer.composeWorldSpritesStage(dvc4WithRecords([visibleRecord]));
const oneSpriteSha = sha(viewPixels());
const skippedRecord = visibleRecord.slice();
const skippedView = new DataView(
  skippedRecord.buffer, skippedRecord.byteOffset, skippedRecord.byteLength);
skippedView.setInt32(0, compositorView.getInt32(36, true), true);
skippedView.setInt32(4, compositorView.getInt32(40, true), true);
resetCurrentWorld();
renderer.composeWorldSpritesStage(
  dvc4WithRecords([skippedRecord, visibleRecord]));
const recordOneSpriteSha = sha(viewPixels());
if (recordOneSpriteSha !== oneSpriteSha) {
  throw new Error(
    `DVC4 record-one sprite addressing mismatch: `
      + `${visibleRecordIndex}/${oneSpriteSha}/${recordOneSpriteSha}`,
  );
}

resetCurrentWorld();
renderer.composeWorldSpritesStage(compositor);
renderer.composeWeaponStage(compositor);
renderer.composeStatusStage(compositor);
function statusSha() {
  const frame = renderer.frameNativeByRef();
  const status = Buffer.alloc(320 * 32);
  for (let x = 0; x < 320; x += 1) {
    status.set(
      frame.subarray(x * 200 + 168, x * 200 + 200),
      x * 32,
    );
  }
  return sha(status);
}
const statusBaselineSha = statusSha();
renderer.composeStatusStage(compositor);
if (statusSha() !== statusBaselineSha) {
  throw new Error('unchanged retained status bar is not pixel-stable');
}
const retainedStatusFrame = renderer.frameNativeByRef();
retainedStatusFrame[168] ^= 1;
if (statusSha() === statusBaselineSha) {
  throw new Error('status reset fixture did not corrupt retained pixels');
}
if (renderer.resetPresentationState() !== 10) {
  throw new Error('retained presentation reset rejected');
}
renderer.composeStatusStage(compositor);
if (statusSha() !== statusBaselineSha) {
  throw new Error('retained presentation reset did not rebuild status pixels');
}
const damaged = compositor.slice();
new DataView(
  damaged.buffer, damaged.byteOffset, damaged.byteLength,
).setInt32(56, 17, true);
renderer.composeStatusStage(damaged);
const statusDamagedSha = statusSha();
renderer.composeStatusStage(compositor);
if (statusDamagedSha === statusBaselineSha
    || statusSha() !== statusBaselineSha) {
  throw new Error('retained status signature missed or retained a HUD mutation');
}
for (const [name, offset, value] of [
  ['ammo', 72, compositorView.getInt32(72, true) + 7],
  ['armor', 60, compositorView.getInt32(60, true) + 13],
  ['cards', 144, compositorView.getInt32(144, true) ^ 1],
  ['face', 8, compositorView.getInt32(8, true) + 17],
]) {
  const mutated = compositor.slice();
  new DataView(
    mutated.buffer, mutated.byteOffset, mutated.byteLength,
  ).setInt32(offset, value, true);
  renderer.composeStatusStage(mutated);
  if (statusSha() === statusBaselineSha) {
    throw new Error(`retained status ${name} widget did not change`);
  }
  renderer.composeStatusStage(compositor);
  if (statusSha() !== statusBaselineSha) {
    throw new Error(`retained status ${name} widget did not restore exactly`);
  }
}

let scrollingEpisode = 0;
let scrollingMap = 0;
let scrollingSides = 0;
scrollingSearch:
for (let episode = 1; episode <= 4; episode += 1) {
  for (let map = 1; map <= 9; map += 1) {
    authority.release();
    load(authority.allocateIwad, authority.loadIwadChunk, iwadBytes);
    load(
      authority.allocateTablePack,
      authority.loadTablePackChunk,
      tableBytes,
    );
    authority.initializeMultiplayerGame(2, 0, 3, episode, map);
    const seedLength =
      authority.presentationWorldGeometryDeltaSnapshotLength(0);
    const seed = authority.presentationWorldSnapshotNativeByRef()
      .slice(0, seedLength);
    const seedView = new DataView(
      seed.buffer, seed.byteOffset, seed.byteLength);
    const seedSides = seedView.getInt32(192, true);
    const seedSideOffset = seedView.getInt32(196, true);
    if (seedView.getInt32(0, true) !== 0x364c5644
        || seedView.getInt32(200, true) !== 18
        || seedLength !== seedSideOffset + seedSides * 18) {
      throw new Error(`invalid DVL6 scrolling seed at E${episode}M${map}`);
    }
    authority.stepMultiplayerAuthoritative(2, 3, new Uint8Array(32));
    const updateLength =
      authority.presentationWorldGeometryDeltaSnapshotLength(0);
    const update = authority.presentationWorldSnapshotNativeByRef()
      .slice(0, updateLength);
    const updateView = new DataView(
      update.buffer, update.byteOffset, update.byteLength);
    const updateSides = updateView.getInt32(192, true);
    const updateSideOffset = updateView.getInt32(196, true);
    for (let dirty = 0; dirty < updateSides; dirty += 1) {
      const at = updateSideOffset + dirty * 18;
      const side = updateView.getUint16(at, true);
      const initialAt = seedSideOffset + side * 18;
      if (seedView.getUint16(initialAt, true) !== side) {
        throw new Error(`unordered DVL6 seed side ${side}`);
      }
      if (seedView.getInt32(initialAt + 10, true)
              !== updateView.getInt32(at + 10, true)
          || seedView.getInt32(initialAt + 14, true)
              !== updateView.getInt32(at + 14, true)) {
        scrollingSides += 1;
      }
    }
    if (scrollingSides > 0) {
      scrollingEpisode = episode;
      scrollingMap = map;
      break scrollingSearch;
    }
  }
}
if (scrollingSides === 0) {
  throw new Error('no live IWAD scrolling wall reached the DVL6 offset delta');
}

authority.release();
load(authority.allocateIwad, authority.loadIwadChunk, iwadBytes);
load(
  authority.allocateTablePack,
  authority.loadTablePackChunk,
  tableBytes,
);
authority.initializeSinglePlayerGame();
const switchSeedLength =
  authority.presentationWorldGeometryDeltaSnapshotLength(0);
const switchSeed = authority.presentationWorldSnapshotNativeByRef()
  .slice(0, switchSeedLength);
const switchSeedView = new DataView(
  switchSeed.buffer, switchSeed.byteOffset, switchSeed.byteLength);
const switchSideCount = switchSeedView.getInt32(192, true);
const switchSideOffset = switchSeedView.getInt32(196, true);
const switchSideState = new Uint16Array(switchSideCount * 3);
for (let side = 0; side < switchSideCount; side += 1) {
  const at = switchSideOffset + side * 18;
  if (switchSeedView.getUint16(at, true) !== side) {
    throw new Error(`unordered DVL6 switch seed side ${side}`);
  }
  switchSideState[side * 3] = switchSeedView.getUint16(at + 2, true);
  switchSideState[side * 3 + 1] = switchSeedView.getUint16(at + 4, true);
  switchSideState[side * 3 + 2] = switchSeedView.getUint16(at + 6, true);
}
let switchTic = 0;
let switchSide = -1;
let routeTic = 0;
let turnHeld = 0;
function routeVector(command) {
  const forward = Math.abs(command.forward) > 1 ? command.forward
    : command.forward * (command.run ? 50 : 25);
  const side = Math.abs(command.strafe) > 1 ? command.strafe
    : command.strafe * (command.run ? 40 : 24);
  const mouseTurn = Math.abs(command.turn) > 1;
  if (command.turn === 0 || mouseTurn) turnHeld = 0;
  else turnHeld += 1;
  const magnitude = mouseTurn ? Math.abs(command.turn) * 256
    : turnHeld < 6 ? 320 : command.run ? 1280 : 640;
  const turn = command.turn === 0
    ? 0 : -Math.sign(command.turn) * magnitude;
  let buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0)
    | (command.weapon > 0 ? 4 | ((command.weapon - 1) << 3) : 0);
  if (command.pause) buttons = 129;
  const consistency = (command.automap ? 2 : 0)
    | (command.menu !== 'NONE' ? 4 : 0) | (command.cheat ? 8 : 0);
  return {forward, side, turn, consistency, buttons};
}
switchSearch:
for (const run of acceptedRoute.runs) {
  for (let repeat = 0; repeat < run.repeat; repeat += 1) {
    const vector = routeVector(run.command);
    routeTic += 1;
    authority.stepSinglePlayerCommand(
      vector.forward, vector.side, vector.turn,
      vector.consistency, vector.buttons);
    const updateLength =
      authority.presentationWorldGeometryDeltaSnapshotLength(0);
    const update = authority.presentationWorldSnapshotNativeByRef()
      .slice(0, updateLength);
    const updateView = new DataView(
      update.buffer, update.byteOffset, update.byteLength);
    const count = updateView.getInt32(192, true);
    const offset = updateView.getInt32(196, true);
    for (let dirty = 0; dirty < count; dirty += 1) {
      const at = offset + dirty * 18;
      const side = updateView.getUint16(at, true);
      const changed =
        switchSideState[side * 3] !== updateView.getUint16(at + 2, true)
        || switchSideState[side * 3 + 1]
            !== updateView.getUint16(at + 4, true)
        || switchSideState[side * 3 + 2]
            !== updateView.getUint16(at + 6, true);
      switchSideState[side * 3] = updateView.getUint16(at + 2, true);
      switchSideState[side * 3 + 1] = updateView.getUint16(at + 4, true);
      switchSideState[side * 3 + 2] = updateView.getUint16(at + 6, true);
      if (changed && run.command.use === 1 && routeTic % 8 !== 0) {
        switchTic = routeTic;
        switchSide = side;
        break switchSearch;
      }
    }
  }
}
if (switchSide < 0) {
  throw new Error(
    'accepted E1M1 route did not prove a live DVL6 switch texture delta');
}

const expectedPixelHashes = {
  baseline: '42cab1d280283be5e18ef9f7ca3eb9bc610341aff7ccdda3df10256cacfc5a8c',
  heights: 'da6a380fbdd6e5ce07a4c925e89ebb0d628ccf4244a0c1c6f080a367266c3ff7',
  lights: '4822f53df79c213f601ac33732bfd50c8309d4672545c134ea26e05eb1650430',
  sides: '27f53aed73d0e21d5905fe9454416ed456e737644ef4ab0ad052ac5dfc548a63',
  offsets: 'e5eb8f3d83a46b28b36f38e0e39a1f6a24c9f46cac1450a2123fea9b37a9a03f',
  sprite: '08e6c2116f1309ac30196f7cd1b67330e0ad2a412c2882aada8ddab12ad23472',
  status: '152ba482162a0f4b88b1347aa54d7585888950fc3bd97fb117f26a8eb23d7f49',
  damagedStatus:
    '9a0d02035cb262c12bbc0f4b5b1951674fba4f4a53a349a68a08b727711b407c',
};
for (const [name, actual, expected] of [
  ['baseline', baselineSha, expectedPixelHashes.baseline],
  ['heights', heightsSha, expectedPixelHashes.heights],
  ['lights', lightsSha, expectedPixelHashes.lights],
  ['sides', sidesSha, expectedPixelHashes.sides],
  ['offsets', dirtyOffsetsSha, expectedPixelHashes.offsets],
  ['sprite', oneSpriteSha, expectedPixelHashes.sprite],
  ['status', statusBaselineSha, expectedPixelHashes.status],
  ['damagedStatus', statusDamagedSha, expectedPixelHashes.damagedStatus],
]) {
  if (!allowVisualVariant && actual !== expected) {
    throw new Error(
      `single-column pixel-equivalence mismatch for ${name}: `
        + `${actual}/${expected}`,
    );
  }
}
if(maximumPartialWallDepthPixels<1) {
  throw new Error('accepted dynamic route did not exercise partial-wall depth');
}

process.stdout.write(
  'PMLE_DVL2_DYNAMIC_WORLD_NODE|PASS'
    + `|snapshot_bytes=${length}|sector_update_bytes=${sectorLength}`
    + `|dirty_initial_bytes=${dirtyLength}|dirty_steady_bytes=${steadyLength}`
    + `|animation_dirty_sides=${animatedDirtyCount}`
    + `|animation_offset_sides=${animatedOffsetSides}`
    + `|scrolling_map=E${scrollingEpisode}M${scrollingMap}`
    + `|scrolling_sides=${scrollingSides}`
    + `|switch_tic=${switchTic}|switch_side=${switchSide}`
    + `|sectors=${sectorCount}|sides=${sideCount}`
    + `|baseline_sha256=${baselineSha}|heights_sha256=${heightsSha}`
    + `|lights_sha256=${lightsSha}|sides_sha256=${sidesSha}`
    + `|dirty_sides_sha256=${dirtySidesSha}`
    + `|dirty_offsets_sha256=${dirtyOffsetsSha}`
    + `|world_sprite_record=${visibleRecordIndex}`
    + `|world_sprite_sha256=${oneSpriteSha}`
    + '|world_sprite_record_one_exact=YES'
    + `|partial_wall_depth_pixels_max=${maximumPartialWallDepthPixels}`
    + `|status_sha256=${statusBaselineSha}`
    + `|status_mutation_sha256=${statusDamagedSha}`
    + `|visual_variant=${allowVisualVariant ? 'YES' : 'NO'}`
    + '|restore_exact=YES|status_restore_exact=YES'
    + '|status_widget_masks_exact=YES|frame_bytes=64000\n',
);
