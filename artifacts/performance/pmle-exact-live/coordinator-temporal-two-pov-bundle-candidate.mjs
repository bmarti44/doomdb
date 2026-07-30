import * as engine from 'doom_dvl2_engine';
import * as renderer from 'doom_live_renderer';
import * as compositor from 'doom_live_compositor';
import oracledb from 'mle-js-oracledb';

const exactPresentation =
  typeof renderer.renderPlayerFrameByRef === 'function';
// The exact presentation artifact wraps the same pinned Mocha simulation
// adapter and can own authority directly. Keeping a second initialized engine
// doubled every tic, checkpoint, and cold start without adding authority.
const authorityEngine = exactPresentation ? renderer : engine;
const unifiedCompositor =
  !exactPresentation && typeof renderer.allocateCompositorPack === 'function';
const compositorApi = unifiedCompositor ? renderer : compositor;

let retainedFrame;
let retainedSnapshot;
let retainedTic = 0;
let compositorSnapshot;
let compositorSnapshotLength = 0;
let nativeFrameSelections = 0;
let nativeSnapshotSelections = 0;
let retainedPaletteIndex = 0;
const FRAME_BYTES = 64000;
const LIVE_BATCH_HEADER_BYTES = 8;
const LIVE_BATCH_RECORD_BYTES = 8;
let retainedLiveBatch;
let retainedLiveBatchCapacity = 0;
let retainedLiveBatchCount = 0;
let retainedLiveBatchFirstTic = -1;
let retainedLiveBatchLastTic = -1;
let retainedOriginCheckpoint;
const MATCH_LIVE_BATCH_FRAMES = 2;
let retainedMatchLiveBatches = [undefined, undefined, undefined, undefined];
const MATCH_VIEW_HEADER_BYTES = 16;
let retainedMatchViews;
let retainedMatchViewIdentity;
let retainedPreparedMatchViews;
let retainedTemporalIdentity;
let retainedTemporalPreviousTic = -1;
let retainedTemporalDeferredTics = [];
let retainedTemporalPrevious;
let retainedTemporalExactBuffers = [undefined, undefined];
let retainedTemporalExactBufferIndex = 0;
let retainedTemporalSynthesis;
const TEMPORAL_SOLO_KEYFRAME_INTERVAL = 3;
const TEMPORAL_MULTIPLAYER_KEYFRAME_INTERVAL = 3;
const FRAME_WIDTH = 320;
const FRAME_HEIGHT = 200;
const VIEW_HEIGHT = 168;
const WORLD_RASTER_INTERVAL_TICS = 4;
let retainedWorldFrames = [undefined, undefined, undefined, undefined];
let retainedWorldCameras = [undefined, undefined, undefined, undefined];
const discardedAssets = new Map();

function allocateDiscardedAsset(kind, length) {
  if (!exactPresentation || !Number.isInteger(length) || length < 0) {
    throw new Error(`invalid discarded exact-render asset: ${kind}/${length}`);
  }
  discardedAssets.set(kind, {length, loaded: 0});
  return length;
}

function loadDiscardedAsset(kind, offset, chunk) {
  const state = discardedAssets.get(kind);
  if (state === undefined || !Number.isInteger(offset)
      || offset !== state.loaded || !ArrayBuffer.isView(chunk)
      || offset + chunk.byteLength > state.length) {
    throw new Error(`invalid discarded exact-render asset chunk: ${kind}`);
  }
  state.loaded += chunk.byteLength;
  return state.loaded;
}

function finalizeDiscardedAsset(kind) {
  const state = discardedAssets.get(kind);
  if (state === undefined || state.loaded !== state.length) {
    throw new Error(`incomplete discarded exact-render asset: ${kind}`);
  }
  return state.length;
}

function clearRetainedWorldFrames() {
  retainedWorldFrames = [undefined, undefined, undefined, undefined];
  retainedWorldCameras = [undefined, undefined, undefined, undefined];
}

function snapshotI32(snapshot, offset) {
  if (!(snapshot instanceof Uint8Array)
      || !Number.isInteger(offset) || offset < 0
      || offset > snapshot.byteLength - 4) {
    throw new Error(`invalid compositor i32 offset: ${offset}`);
  }
  return (snapshot[offset]
      | (snapshot[offset + 1] << 8)
      | (snapshot[offset + 2] << 16)
      | (snapshot[offset + 3] << 24));
}

function putU32Be(target, offset, value) {
  target[offset] = (value >>> 24) & 255;
  target[offset + 1] = (value >>> 16) & 255;
  target[offset + 2] = (value >>> 8) & 255;
  target[offset + 3] = value & 255;
}

function snapshotCamera(snapshot, tic) {
  return {
    tic,
    x: snapshotI32(snapshot, 36),
    y: snapshotI32(snapshot, 40),
    angle: snapshotI32(snapshot, 48) & 0xffff,
    viewZ: snapshotI32(snapshot, 52),
  };
}

function signedAngleDelta(current, previous) {
  let delta = (current - previous) & 0xffff;
  if (delta >= 0x8000) delta -= 0x10000;
  return delta;
}

function approximateDirection(angle) {
  // Eight deterministic fixed-point directions are sufficient for the
  // one-tic image-space motion estimate.  They avoid host floating-point
  // trigonometry and do not participate in simulation authority.
  const octant = ((angle + 0x1000) >>> 13) & 7;
  const diagonal = 46341; // round(65536 / sqrt(2)).
  switch (octant) {
    case 0: return [65536, 0];
    case 1: return [diagonal, diagonal];
    case 2: return [0, 65536];
    case 3: return [-diagonal, diagonal];
    case 4: return [-65536, 0];
    case 5: return [-diagonal, -diagonal];
    case 6: return [0, -65536];
    default: return [diagonal, -diagonal];
  }
}

function cacheRenderedWorld(playerSlot, frameTic, snapshot) {
  const frame = rendererFrameView(renderer);
  let cached = retainedWorldFrames[playerSlot];
  if (!(cached instanceof Uint8Array) || cached.byteLength !== FRAME_BYTES) {
    cached = new Uint8Array(FRAME_BYTES);
    retainedWorldFrames[playerSlot] = cached;
  }
  cached.set(frame);
  retainedWorldCameras[playerSlot] = snapshotCamera(snapshot, frameTic);
}

function synthesizeConfirmedWorld(playerSlot, frameTic, snapshot) {
  const source = retainedWorldFrames[playerSlot];
  const previous = retainedWorldCameras[playerSlot];
  if (!(source instanceof Uint8Array) || source.byteLength !== FRAME_BYTES
      || previous === undefined) {
    throw new Error(`confirmed world cache is absent for player ${playerSlot}`);
  }
  const current = snapshotCamera(snapshot, frameTic);
  const target = rendererFrameView(renderer);
  // Even when the camera is byte-for-byte stationary, copy only the world
  // viewport below. cachedRenderedWorld is captured before current weapon/HUD
  // composition, so copying all 200 rows can resurrect an older status bar
  // after the retained widget mask has already accepted the newer values.
  if (current.x === previous.x && current.y === previous.y
      && current.angle === previous.angle
      && current.viewZ === previous.viewZ) {
    for (let x = 0; x < FRAME_WIDTH; x++) {
      const at = x * FRAME_HEIGHT;
      target.set(source.subarray(at, at + VIEW_HEIGHT), at);
    }
    return target;
  }
  const [directionX, directionY] = approximateDirection(previous.angle);
  const dx = current.x - previous.x;
  const dy = current.y - previous.y;
  // Keep the projection in fixed-point until the image-space conversion.
  // Truncating x/y to whole map units here made Doom's sub-unit acceleration
  // invisible during the first moving tics and collapsed distinct confirmed
  // states into repeated framebuffers.
  const forwardFixed =
    (dx * directionX + dy * directionY) / 65536;
  const lateralFixed =
    (dx * -directionY + dy * directionX) / 65536;
  const turnColumns = signedAngleDelta(current.angle, previous.angle)
    * FRAME_WIDTH / 16384;
  const lateralColumns = Math.max(
    -12, Math.min(12, lateralFixed / (4 * 65536)));
  const zoom = 1024 - Math.max(
    -96, Math.min(96, forwardFixed * 12 / 65536));
  const vertical = Math.max(
    -6, Math.min(6, Math.round((current.viewZ - previous.viewZ) / 65536)));
  for (let x = 0; x < FRAME_WIDTH; x++) {
    const centered = x - FRAME_WIDTH / 2;
    const sourcePosition =
      FRAME_WIDTH / 2 + centered * zoom / 1024
        + turnColumns + lateralColumns;
    const lowerSource = Math.floor(sourcePosition);
    const fraction = sourcePosition - lowerSource;
    // Ordered selection between adjacent source columns preserves subpixel
    // camera motion in an indexed framebuffer without inventing palette
    // colors. The phase changes each confirmed tic, preventing slow turns
    // from collapsing into repeated complete frames.
    const threshold = ((x * 5 + frameTic * 3) & 7) / 8;
    const sourceX = Math.max(0, Math.min(
      FRAME_WIDTH - 1,
      lowerSource + (fraction > threshold ? 1 : 0),
    ));
    const sourceAt = sourceX * FRAME_HEIGHT;
    const targetAt = x * FRAME_HEIGHT;
    if (vertical === 0) {
      target.set(
        source.subarray(sourceAt, sourceAt + VIEW_HEIGHT), targetAt);
    } else if (vertical > 0) {
      target.fill(source[sourceAt], targetAt, targetAt + vertical);
      target.set(
        source.subarray(sourceAt, sourceAt + VIEW_HEIGHT - vertical),
        targetAt + vertical);
    } else {
      const shift = -vertical;
      target.set(
        source.subarray(sourceAt + shift, sourceAt + VIEW_HEIGHT), targetAt);
      target.fill(
        source[sourceAt + VIEW_HEIGHT - 1],
        targetAt + VIEW_HEIGHT - shift, targetAt + VIEW_HEIGHT);
    }
  }
  return target;
}

function paletteIndexFromSnapshot(snapshot) {
  // This is Doom's damage/bonus branch exactly. Berserk fade and radiation
  // require two additional authoritative power counters and remain fenced as
  // a declared fidelity gap until the next authority artifact batch.
  const damage = Math.max(0, snapshotI32(snapshot, 128));
  const bonus = Math.max(0, snapshotI32(snapshot, 132));
  if (damage !== 0) return 1 + Math.min(7, (damage + 7) >> 3);
  if (bonus !== 0) return 9 + Math.min(3, (bonus + 7) >> 3);
  return 0;
}

function rendererFrameView(api) {
  let exported;
  if (unifiedCompositor) {
    if (typeof api.frameNativeByRef !== 'function') {
      throw new Error('native framebuffer export is required in unified mode');
    }
    exported = api.frameNativeByRef();
    nativeFrameSelections++;
  } else {
    exported = api.frameByRef();
  }
  if (!ArrayBuffer.isView(exported) || exported.byteLength !== 64000) {
    throw new Error(`invalid retained framebuffer: ${exported?.byteLength}`);
  }
  return exported instanceof Uint8Array
    ? exported
    : new Uint8Array(
      exported.buffer, exported.byteOffset, exported.byteLength);
}

export function allocateIwad(length) {
  return authorityEngine.allocateIwad(length);
}
export function loadIwadChunk(offset, chunk) {
  return authorityEngine.loadIwadChunk(offset, chunk);
}
export function allocateTablePack(length) {
  return authorityEngine.allocateTablePack(length);
}
export function loadTablePackChunk(offset, chunk) {
  return authorityEngine.loadTablePackChunk(offset, chunk);
}
export const allocateRendererPack = length => exactPresentation
  ? allocateDiscardedAsset('WORLD', length) : renderer.allocatePack(length);
export const loadRendererPackChunk = (offset, chunk) =>
  exactPresentation ? loadDiscardedAsset('WORLD', offset, chunk)
    : renderer.loadPackChunk(offset, chunk);
export const finalizeRendererPack = () => exactPresentation
  ? finalizeDiscardedAsset('WORLD') : renderer.finalizePack();
export const allocateWallTextures = length =>
  exactPresentation ? allocateDiscardedAsset('WALL', length)
    : renderer.allocateWallTextures(length);
export const loadWallTextureChunk = (offset, chunk) =>
  exactPresentation ? loadDiscardedAsset('WALL', offset, chunk)
    : renderer.loadWallTextureChunk(offset, chunk);
export const finalizeWallTextures = () => exactPresentation
  ? finalizeDiscardedAsset('WALL') : renderer.finalizeWallTextures();
export const allocateFlatTextures = length =>
  exactPresentation ? allocateDiscardedAsset('FLAT', length)
    : renderer.allocateFlatTextures(length);
export const loadFlatTextureChunk = (offset, chunk) =>
  exactPresentation ? loadDiscardedAsset('FLAT', offset, chunk)
    : renderer.loadFlatTextureChunk(offset, chunk);
export const finalizeFlatTextures = () => exactPresentation
  ? finalizeDiscardedAsset('FLAT') : renderer.finalizeFlatTextures();
export const allocateCompositorPack = length =>
  exactPresentation ? allocateDiscardedAsset('COMPOSITOR', length)
    : compositorApi.allocateCompositorPack
    ? compositorApi.allocateCompositorPack(length)
    : compositorApi.allocatePack(length);
export const loadCompositorPackChunk = (offset, chunk) =>
  exactPresentation ? loadDiscardedAsset('COMPOSITOR', offset, chunk)
    : compositorApi.loadCompositorPackChunk
    ? compositorApi.loadCompositorPackChunk(offset, chunk)
    : compositorApi.loadPackChunk(offset, chunk);
export const finalizeCompositorPack = () =>
  exactPresentation ? finalizeDiscardedAsset('COMPOSITOR')
    : compositorApi.finalizeCompositorPack
    ? compositorApi.finalizeCompositorPack()
    : compositorApi.finalizePack();
export const allocateCompositorSprites = length =>
  exactPresentation ? allocateDiscardedAsset('SPRITE', length)
    : compositorApi.allocateCompositorSprites
    ? compositorApi.allocateCompositorSprites(length)
    : compositorApi.allocateSpriteTextures(length);
export const loadCompositorSpriteChunk = (offset, chunk) =>
  exactPresentation ? loadDiscardedAsset('SPRITE', offset, chunk)
    : compositorApi.loadCompositorSpriteChunk
    ? compositorApi.loadCompositorSpriteChunk(offset, chunk)
    : compositorApi.loadSpriteTextureChunk(offset, chunk);
export const finalizeCompositorSprites = () =>
  exactPresentation ? finalizeDiscardedAsset('SPRITE')
    : compositorApi.finalizeCompositorSprites
    ? compositorApi.finalizeCompositorSprites()
    : compositorApi.finalizeSpriteTextures();
export const allocateCompositorUi = length =>
  exactPresentation ? allocateDiscardedAsset('UI', length)
    : compositorApi.allocateCompositorUi
    ? compositorApi.allocateCompositorUi(length)
    : compositorApi.allocateUiTextures(length);
export const loadCompositorUiChunk = (offset, chunk) =>
  exactPresentation ? loadDiscardedAsset('UI', offset, chunk)
    : compositorApi.loadCompositorUiChunk
    ? compositorApi.loadCompositorUiChunk(offset, chunk)
    : compositorApi.loadUiTextureChunk(offset, chunk);
export const finalizeCompositorUi = () =>
  exactPresentation ? finalizeDiscardedAsset('UI')
    : compositorApi.finalizeCompositorUi
    ? compositorApi.finalizeCompositorUi()
    : compositorApi.finalizeUiTextures();
export function initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map) {
  if (!exactPresentation && renderer.resetPresentationState() !== 10) {
    throw new Error('renderer presentation state reset failed');
  }
  clearRetainedWorldFrames();
  const authoritative = authorityEngine.initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map);
  return authoritative;
}
export const canonicalState = () => authorityEngine.canonicalState();
export const currentState = () => authorityEngine.currentState();
export const memoryDiagnostic = () => authorityEngine.memoryDiagnostic();
export const presentationWorldSnapshotLength = playerSlot =>
  authorityEngine.presentationWorldSnapshotLength(playerSlot);
export const presentationWorldSnapshotChunk = (offset, length) =>
  authorityEngine.presentationWorldSnapshotChunk(offset, length);
export const checkpointLength = () => authorityEngine.checkpointLength();
export const checkpointChunk = (offset, length) =>
  authorityEngine.checkpointChunk(offset, length);
export function allocateCheckpoint(length) {
  return authorityEngine.allocateCheckpoint(length);
}
export function loadCheckpointChunk(offset, chunk) {
  return authorityEngine.loadCheckpointChunk(offset, chunk);
}
export function restoreCheckpoint(expectedTic) {
  if (!exactPresentation && renderer.resetPresentationState() !== 10) {
    throw new Error('renderer presentation state reset failed');
  }
  clearRetainedWorldFrames();
  return authorityEngine.restoreCheckpoint(expectedTic);
}
export function restoreCheckpointWarm(expectedTic) {
  if (!exactPresentation && renderer.resetPresentationState() !== 10) {
    throw new Error('renderer presentation state reset failed');
  }
  clearRetainedWorldFrames();
  return typeof authorityEngine.restoreCheckpointWarm === 'function'
    ? authorityEngine.restoreCheckpointWarm(expectedTic)
    : authorityEngine.restoreCheckpoint(expectedTic);
}

export function captureOriginCheckpoint() {
  const length = authorityEngine.checkpointLength();
  if (!Number.isInteger(length) || length < 1 || length > 64 * 1024 * 1024) {
    throw new Error(`invalid origin checkpoint length: ${length}`);
  }
  retainedOriginCheckpoint = new Uint8Array(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const chunk = authorityEngine.checkpointChunk(
      offset, Math.min(32767, length - offset));
    if (!(chunk instanceof Uint8Array)
        || chunk.byteLength !== Math.min(32767, length - offset)) {
      throw new Error(`short origin checkpoint capture at ${offset}`);
    }
    retainedOriginCheckpoint.set(chunk, offset);
  }
  return length;
}

export function restoreOriginCheckpoint() {
  if (!(retainedOriginCheckpoint instanceof Uint8Array)) {
    throw new Error('origin checkpoint is not retained');
  }
  if (allocateCheckpoint(retainedOriginCheckpoint.byteLength)
      !== retainedOriginCheckpoint.byteLength) {
    throw new Error('origin checkpoint allocation failed');
  }
  for (let offset = 0; offset < retainedOriginCheckpoint.byteLength;
       offset += 32767) {
    const chunk = retainedOriginCheckpoint.subarray(
      offset, Math.min(retainedOriginCheckpoint.byteLength, offset + 32767));
    if (loadCheckpointChunk(offset, chunk) !== offset + chunk.length) {
      throw new Error(`short origin checkpoint load at ${offset}`);
    }
  }
  if (!exactPresentation && renderer.resetPresentationState() !== 10) {
    throw new Error('origin presentation-state reset failed');
  }
  clearRetainedWorldFrames();
  const restored = authorityEngine.restoreCheckpoint(0);
  if (typeof restored !== 'string'
      || !restored.startsWith('state=restored|gametic=0|')) {
    throw new Error(`origin checkpoint restore mismatch: ${restored}`);
  }
  retainedTic = 0;
  retainedFrame = undefined;
  retainedSnapshot = undefined;
  compositorSnapshot = undefined;
  compositorSnapshotLength = 0;
  return 0;
}

function currentWorldGeometrySnapshot(playerSlot) {
  const length =
    authorityEngine.presentationWorldGeometryDeltaSnapshotLength(playerSlot);
  // The one-time DVL6 seed includes every indexed sector and side, including
  // fixed-point texture offsets, and can exceed RAW's 32,767-byte SQL limit.
  // It remains a same-isolate native Uint8Array and never crosses the SQL
  // boundary; steady indexed deltas stay compact.
  if (!Number.isInteger(length) || length < 208
      || length > 16 * 1024 * 1024) {
    throw new Error(`invalid retained world geometry snapshot: ${length}`);
  }
  let exported;
  if (unifiedCompositor) {
    if (typeof authorityEngine.presentationWorldSnapshotNativeByRef
        !== 'function') {
      throw new Error('native world snapshot export is required in unified mode');
    }
    exported = authorityEngine.presentationWorldSnapshotNativeByRef();
  } else {
    exported = authorityEngine.presentationWorldSnapshotByRef();
  }
  if (!ArrayBuffer.isView(exported) || length > exported.byteLength) {
    throw new Error(
      `invalid retained world geometry backing: ${exported?.byteLength}`);
  }
  const bytes = exported instanceof Uint8Array
    ? exported
    : new Uint8Array(exported.buffer, exported.byteOffset, exported.byteLength);
  retainedSnapshot = bytes.subarray(0, length);
  return retainedSnapshot;
}

function currentFullWorldGeometrySnapshot(playerSlot) {
  const length =
    authorityEngine.presentationWorldGeometryAndSidesSnapshotLength(playerSlot);
  if (!Number.isInteger(length) || length < 208
      || length > 16 * 1024 * 1024) {
    throw new Error(`invalid full world geometry snapshot: ${length}`);
  }
  let exported;
  if (unifiedCompositor) {
    if (typeof authorityEngine.presentationWorldSnapshotNativeByRef
        !== 'function') {
      throw new Error('native full world snapshot export is required');
    }
    exported = authorityEngine.presentationWorldSnapshotNativeByRef();
  } else {
    exported = authorityEngine.presentationWorldSnapshotByRef();
  }
  if (!ArrayBuffer.isView(exported) || length > exported.byteLength) {
    throw new Error(
      `invalid full world geometry backing: ${exported?.byteLength}`);
  }
  const bytes = exported instanceof Uint8Array
    ? exported
    : new Uint8Array(
      exported.buffer, exported.byteOffset, exported.byteLength);
  retainedSnapshot = bytes.subarray(0, length);
  return retainedSnapshot;
}

export function renderCurrentFrame(playerSlot) {
  const snapshot = currentWorldGeometrySnapshot(playerSlot);
  renderer.loadCompactSnapshot(snapshot);
  const checksum = renderer.renderLoadedCompactFrameCoarse(snapshot);
  if (!(retainedFrame instanceof Uint8Array)) {
    retainedFrame = rendererFrameView(renderer);
  }
  return checksum;
}

export function prepareCurrentSnapshot(playerSlot, fullWorld = false) {
  return (fullWorld
    ? currentFullWorldGeometrySnapshot(playerSlot)
    : currentWorldGeometrySnapshot(playerSlot)).byteLength;
}

export function loadPreparedDynamics() {
  if (!(retainedSnapshot instanceof Uint8Array)) {
    throw new Error('DVL3 snapshot is not prepared');
  }
  const loaded = renderer.loadCompactSnapshot(retainedSnapshot);
  return loaded;
}

export function renderPreparedFrame() {
  if (!(retainedSnapshot instanceof Uint8Array)) {
    throw new Error('DVL3 snapshot is not prepared');
  }
  const checksum = renderer.renderLoadedCompactFrameCoarse(retainedSnapshot);
  if (!unifiedCompositor) {
    const exported = renderer.frameByRef();
    retainedFrame = exported instanceof Uint8Array
      ? exported
      : new Uint8Array(
        exported.buffer, exported.byteOffset, exported.byteLength);
  }
  return checksum;
}

export function composeCurrentFrame(playerSlot) {
  prepareCurrentComposition(playerSlot);
  copyCurrentCompositionBuffers();
  const checksum = compositorApi.composeCompactSnapshot(compositorSnapshot);
  retainedFrame = rendererFrameView(compositorApi);
  return checksum;
}

export function prepareCurrentComposition(playerSlot) {
  buildCurrentComposition(playerSlot);
  return exportCurrentComposition();
}

export function buildCurrentComposition(playerSlot) {
  const length =
    authorityEngine.presentationCompositorSnapshotLength(playerSlot);
  if (!Number.isInteger(length) || length < 208 || length > 32767) {
    throw new Error(`invalid built compositor snapshot: ${length}`);
  }
  compositorSnapshotLength = length;
  compositorSnapshot = undefined;
  return length;
}

export function exportCurrentComposition() {
  const length = compositorSnapshotLength;
  if (!Number.isInteger(length) || length < 208 || length > 32767) {
    throw new Error('compositor snapshot must be built before export');
  }
  let exported;
  if (unifiedCompositor) {
    if (typeof authorityEngine.presentationWorldSnapshotNativeByRef
        !== 'function') {
      throw new Error('native snapshot export is required in unified mode');
    }
    exported = authorityEngine.presentationWorldSnapshotNativeByRef();
    nativeSnapshotSelections++;
  } else {
    exported = authorityEngine.presentationWorldSnapshotByRef();
  }
  if (!ArrayBuffer.isView(exported)
      || length < 208 || length > exported.byteLength) {
    throw new Error(`invalid retained compositor snapshot: ${length}`);
  }
  const bytes = exported instanceof Uint8Array
    ? exported
    : new Uint8Array(exported.buffer, exported.byteOffset, exported.byteLength);
  compositorSnapshot = bytes.subarray(0, length);
  return length;
}

export function copyCurrentCompositionBuffers() {
  if (!(compositorSnapshot instanceof Uint8Array)) {
    throw new Error('compositor snapshot is not prepared');
  }
  if (unifiedCompositor) {
    return 64000;
  }
  const sourceFrame = renderer.frameByRef();
  const targetFrame = compositorApi.frameByRef();
  const sourceSolid = renderer.solidDepthByRef();
  const targetSolid = compositorApi.solidDepthByRef();
  const sourceWall = renderer.wallDepthByRef();
  const targetWall = compositorApi.wallDepthByRef();
  if (!ArrayBuffer.isView(sourceFrame) || !ArrayBuffer.isView(targetFrame)
      || sourceFrame.byteLength !== 64000 || targetFrame.byteLength !== 64000
      || sourceSolid.length > targetSolid.length
      || sourceWall.length !== targetWall.length) {
    throw new Error('world/compositor retained buffers do not match');
  }
  const sameFrame = targetFrame === sourceFrame
    || (targetFrame.buffer === sourceFrame.buffer
      && targetFrame.byteOffset === sourceFrame.byteOffset
      && targetFrame.byteLength === sourceFrame.byteLength);
  const sameSolid = targetSolid === sourceSolid
    || (targetSolid.buffer === sourceSolid.buffer
      && targetSolid.byteOffset === sourceSolid.byteOffset
      && targetSolid.byteLength === sourceSolid.byteLength);
  const sameWall = targetWall === sourceWall
    || (targetWall.buffer === sourceWall.buffer
      && targetWall.byteOffset === sourceWall.byteOffset
      && targetWall.byteLength === sourceWall.byteLength);
  if (!sameFrame) targetFrame.set(sourceFrame);
  if (!sameSolid) targetSolid.set(sourceSolid);
  // Split-module diagnostics must preserve whatever partial-wall depths their
  // renderer produced. Unified builds share the retained buffer and return
  // above; the selected specialized unified artifact may leave it invariant.
  if (!sameWall) targetWall.set(sourceWall);
  retainedFrame = targetFrame instanceof Uint8Array
    ? targetFrame
    : new Uint8Array(
      targetFrame.buffer, targetFrame.byteOffset, targetFrame.byteLength);
  return retainedFrame.byteLength;
}

export function composePreparedWorldSprites() {
  if (!(compositorSnapshot instanceof Uint8Array)) {
    throw new Error('compositor snapshot is not prepared');
  }
  return compositorApi.composeWorldSpritesStage(compositorSnapshot);
}

export function composePreparedWeapon() {
  if (!(compositorSnapshot instanceof Uint8Array)) {
    throw new Error('compositor snapshot is not prepared');
  }
  return compositorApi.composeWeaponStage(compositorSnapshot);
}

export function composePreparedStatus() {
  if (!(compositorSnapshot instanceof Uint8Array)) {
    throw new Error('compositor snapshot is not prepared');
  }
  const checksum = compositorApi.composeStatusStage(compositorSnapshot);
  if (unifiedCompositor) {
    retainedFrame = rendererFrameView(renderer);
  }
  return checksum;
}

/**
 * One-time, outside-timing proof that the unified coordinator selected both
 * native exports, that each is byte-identical to TeaVM's legacy clone, and
 * that the returned native view aliases the retained Java byte[] backing.
 */
export function verifyNativeViewContract() {
  if (!unifiedCompositor || nativeFrameSelections < 1
      || nativeSnapshotSelections < 1
      || typeof renderer.frameNativeByRef !== 'function'
      || typeof authorityEngine.presentationWorldSnapshotNativeByRef
        !== 'function') {
    throw new Error('native view paths were not selected');
  }
  const frame = renderer.frameNativeByRef();
  const frameClone = renderer.frameByRef();
  if (!(frame instanceof Uint8Array) || !ArrayBuffer.isView(frameClone)
      || frame.byteLength !== 64000 || frameClone.byteLength !== 64000) {
    throw new Error('native framebuffer contract shape mismatch');
  }
  for (let index = 0; index < frame.byteLength; index++) {
    if (frame[index] !== (frameClone[index] & 255)) {
      throw new Error(`native framebuffer differs at ${index}`);
    }
  }
  const frameBefore = frame[0];
  frame[0] = frameBefore ^ 1;
  if (renderer.frameNativeByRef()[0] !== (frameBefore ^ 1)
      || (frameClone[0] & 255) !== frameBefore) {
    frame[0] = frameBefore;
    throw new Error('native framebuffer does not alias retained storage');
  }
  frame[0] = frameBefore;

  const snapshot = authorityEngine.presentationWorldSnapshotNativeByRef();
  const snapshotClone = authorityEngine.presentationWorldSnapshotByRef();
  const length = compositorSnapshotLength;
  if (!(snapshot instanceof Uint8Array) || !ArrayBuffer.isView(snapshotClone)
      || length < 208 || length > snapshot.byteLength
      || snapshotClone.byteLength < length) {
    throw new Error('native snapshot contract shape mismatch');
  }
  for (let index = 0; index < length; index++) {
    if (snapshot[index] !== (snapshotClone[index] & 255)) {
      throw new Error(`native snapshot differs at ${index}`);
    }
  }
  const snapshotBefore = snapshot[length - 1];
  snapshot[length - 1] = snapshotBefore ^ 1;
  if (authorityEngine.presentationWorldSnapshotNativeByRef()[length - 1]
        !== (snapshotBefore ^ 1)
      || (snapshotClone[length - 1] & 255) !== snapshotBefore) {
    snapshot[length - 1] = snapshotBefore;
    throw new Error('native snapshot does not alias retained storage');
  }
  snapshot[length - 1] = snapshotBefore;
  return 3;
}

export function stepAndRender(
    activePlayers, membershipMask, commands, playerSlot) {
  const tic = stepOnly(activePlayers, membershipMask, commands);
  if (exactPresentation) {
    retainedFrame = renderer.renderPlayerFrameByRef(playerSlot);
  } else {
    renderCurrentFrame(playerSlot);
  }
  return tic;
}

export function stepOnly(activePlayers, membershipMask, commands) {
  retainedTic = authorityEngine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
  return retainedTic;
}

export function frameChunk(offset, length) {
  if (!(retainedFrame instanceof Uint8Array)
      || !Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length < 0
      || offset > retainedFrame.byteLength
      || length > retainedFrame.byteLength - offset) {
    throw new Error(`invalid retained frame chunk: ${offset}/${length}`);
  }
  return retainedFrame.subarray(offset, offset + length);
}

export function publishPreparedFrame(frameId) {
  if (!(retainedFrame instanceof Uint8Array)
      || retainedFrame.byteLength !== 64000
      || !Number.isInteger(frameId) || frameId < 0) {
    throw new Error(`invalid retained frame publication: ${frameId}`);
  }
  const payload = {
    dir: oracledb.BIND_IN,
    val: retainedFrame,
  };
  if (oracledb.DB_TYPE_BLOB !== undefined) {
    payload.type = oracledb.DB_TYPE_BLOB;
  }
  const result = oracledb.defaultConnection().execute(
    `update doom_dvl2_frame_ring
        set frame_tic=:frameId,payload=:payload
      where ring_slot=mod(:frameId,64)`,
    {frameId, payload},
  );
  if (result.rowsAffected !== 1) {
    throw new Error(
      `retained frame publication affected ${result.rowsAffected} rows`);
  }
  return retainedFrame.byteLength;
}

export function publishPreparedFrameLocator(frameId) {
  if (!(retainedFrame instanceof Uint8Array)
      || retainedFrame.byteLength !== 64000
      || !Number.isInteger(frameId) || frameId < 0) {
    throw new Error(`invalid retained locator publication: ${frameId}`);
  }
  const result = oracledb.defaultConnection().execute(
    `update doom_dvl2_frame_ring
        set frame_tic=:frameId
      where ring_slot=mod(:frameId,64)
      returning payload into :payload`,
    {
      frameId,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1) {
    throw new Error('persistent frame locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  if (!(payload instanceof OracleBlob)) {
    throw new Error('frame-ring RETURNING did not produce OracleBlob');
  }
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, retainedFrame);
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the enclosing SQL call rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  return retainedFrame.byteLength;
}

/**
 * Diagnostic/prototype path for amortizing the MLE-to-SQL locator boundary.
 * Every record still contains one complete uncompressed database-rendered
 * framebuffer. DPB2 is also the existing client wire envelope, so ORDS can
 * return this persistent BLOB without a PL/SQL frame-reassembly pass.
 */
export function resetPreparedLiveFrameBatch(capacity) {
  if (!Number.isInteger(capacity) || capacity < 1 || capacity > 10) {
    throw new Error(`invalid live-frame batch capacity: ${capacity}`);
  }
  const length = LIVE_BATCH_HEADER_BYTES
    + capacity * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
  if (!(retainedLiveBatch instanceof Uint8Array)
      || retainedLiveBatch.byteLength !== length) {
    retainedLiveBatch = new Uint8Array(length);
  }
  retainedLiveBatchCapacity = capacity;
  retainedLiveBatchCount = 0;
  retainedLiveBatchFirstTic = -1;
  retainedLiveBatchLastTic = -1;
  retainedLiveBatch.set([68, 80, 66, 50], 0); // DPB2.
  putU32Be(retainedLiveBatch, 4, 0);
  return length;
}

export function appendPreparedLiveFrame(frameId, paletteIndex) {
  if (!(retainedFrame instanceof Uint8Array)
      || retainedFrame.byteLength !== FRAME_BYTES
      || !Number.isSafeInteger(frameId) || frameId < 0
      || !Number.isInteger(paletteIndex)
      || paletteIndex < 0 || paletteIndex > 13
      || retainedLiveBatchCount >= retainedLiveBatchCapacity) {
    throw new Error(
      `invalid live-frame batch append: ${frameId}/${paletteIndex}`
        + `/${retainedLiveBatchCount}/${retainedLiveBatchCapacity}`);
  }
  if (retainedLiveBatchCount > 0
      && frameId !== retainedLiveBatchLastTic + 1) {
    throw new Error(`non-consecutive live-frame batch tic: ${frameId}`);
  }
  const record = LIVE_BATCH_HEADER_BYTES
    + retainedLiveBatchCount * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
  if (frameId > 0xffffffff) {
    throw new Error(`DPB2 frame id exceeds uint32: ${frameId}`);
  }
  putU32Be(retainedLiveBatch, record, frameId >>> 0);
  retainedLiveBatch[record + 4] = paletteIndex;
  retainedLiveBatch[record + 5] = exactPresentation ? 1 : 0;
  retainedLiveBatch[record + 6] = 0;
  retainedLiveBatch[record + 7] = 0;
  retainedLiveBatch.set(retainedFrame, record + LIVE_BATCH_RECORD_BYTES);
  if (retainedLiveBatchCount === 0) retainedLiveBatchFirstTic = frameId;
  retainedLiveBatchLastTic = frameId;
  retainedLiveBatchCount++;
  putU32Be(retainedLiveBatch, 4, retainedLiveBatchCount);
  return retainedLiveBatchCount;
}

export function publishPreparedLiveFrameBatchLocator(batchId) {
  if (!(retainedLiveBatch instanceof Uint8Array)
      || retainedLiveBatchCount !== retainedLiveBatchCapacity
      || !Number.isSafeInteger(batchId) || batchId < 0) {
    throw new Error(
      `invalid retained live-frame batch: ${batchId}`
        + `/${retainedLiveBatchCount}/${retainedLiveBatchCapacity}`);
  }
  const length = LIVE_BATCH_HEADER_BYTES
    + retainedLiveBatchCount * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
  const result = oracledb.defaultConnection().execute(
    `update doom_dvl2_frame_ring
        set frame_tic=:frameId,payload=empty_blob()
      where ring_slot=mod(:batchId,64)
      returning payload into :payload`,
    {
      frameId: retainedLiveBatchLastTic,
      batchId,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1
      || !(result.outBinds.payload[0] instanceof OracleBlob)) {
    throw new Error('persistent live-frame batch locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, retainedLiveBatch.subarray(0, length));
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the enclosing SQL call rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  return length;
}

export function publishPreparedMatchFrameLocator(
    matchId, playerSlot, membershipEpoch, generation, frameTic,
    paletteIndex) {
  if (!(retainedFrame instanceof Uint8Array)
      || retainedFrame.byteLength !== 64000
      || typeof matchId !== 'string'
      || !/^[0-9a-f]{32}$/.test(matchId)
      || !Number.isInteger(playerSlot) || playerSlot < 0 || playerSlot > 3
      || !Number.isInteger(membershipEpoch) || membershipEpoch < 1
      || !Number.isInteger(generation) || generation < 1
      || !Number.isInteger(frameTic) || frameTic < 0
      || !Number.isInteger(paletteIndex)
      || paletteIndex < 0 || paletteIndex > 13) {
    throw new Error(
      `invalid match-frame publication: ${matchId}/${playerSlot}`
        + `/${membershipEpoch}/${generation}/${frameTic}`);
  }
  const result = oracledb.defaultConnection().execute(
    `update doom_match_live_frame
        set tic=:frameTic,palette_index=:paletteIndex,
            payload_bytes=64000,published_at=systimestamp
      where match_id=:matchId
        and player_slot=:playerSlot
        and ring_slot=mod(:frameTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload`,
    {
      matchId,
      playerSlot,
      membershipEpoch,
      generation,
      frameTic,
      paletteIndex,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1) {
    throw new Error('match-frame locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  if (!(payload instanceof OracleBlob)) {
    throw new Error('match-frame RETURNING did not produce OracleBlob');
  }
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, retainedFrame);
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the worker transaction rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  return retainedFrame.byteLength;
}

function renderCompleteMatchFrame(
    playerSlot, fullWorld = false, frameTic = undefined,
    worldRasterPhase = undefined) {
  if (exactPresentation) {
    const exported = renderer.renderPlayerFrameByRef(playerSlot);
    if (!ArrayBuffer.isView(exported) || exported.byteLength !== FRAME_BYTES) {
      throw new Error(
        `invalid exact presentation framebuffer: ${exported?.byteLength}`);
    }
    retainedFrame = exported instanceof Uint8Array
      ? exported
      : new Uint8Array(
        exported.buffer, exported.byteOffset, exported.byteLength);
    retainedPaletteIndex =
      typeof renderer.presentationPaletteIndex === 'function'
        ? renderer.presentationPaletteIndex()
        : 0;
    return retainedFrame;
  }
  if (fullWorld) {
    // DVL2 establishes every retained sector/sidedef baseline, but building
    // it intentionally does not consume the authority's DVL6 dirty cache.
    // Apply both before the first render so translated flats, animated walls,
    // scrolling offsets, and light changes cannot lag until tic 1.
    prepareCurrentSnapshot(playerSlot, true);
    loadPreparedDynamics();
  }
  prepareCurrentSnapshot(playerSlot, false);
  loadPreparedDynamics();
  const cachedCamera = retainedWorldCameras[playerSlot];
  const rasterPhaseDue = Number.isInteger(frameTic)
    && Number.isInteger(worldRasterPhase)
    && worldRasterPhase >= 0
    && worldRasterPhase < WORLD_RASTER_INTERVAL_TICS
    && frameTic % WORLD_RASTER_INTERVAL_TICS === worldRasterPhase;
  const synthesize = Number.isInteger(frameTic)
    && cachedCamera !== undefined
    && frameTic - cachedCamera.tic > 0
    && frameTic - cachedCamera.tic < WORLD_RASTER_INTERVAL_TICS
    && !rasterPhaseDue;
  if (synthesize) {
    synthesizeConfirmedWorld(playerSlot, frameTic, retainedSnapshot);
  } else {
    renderPreparedFrame();
    if (Number.isInteger(frameTic)) {
      cacheRenderedWorld(playerSlot, frameTic, retainedSnapshot);
    }
  }
  buildCurrentComposition(playerSlot);
  exportCurrentComposition();
  copyCurrentCompositionBuffers();
  composePreparedWorldSprites();
  composePreparedWeapon();
  composePreparedStatus();
  retainedPaletteIndex = paletteIndexFromSnapshot(compositorSnapshot);
  return retainedFrame;
}

/**
 * Candidate live path: every output is still a complete confirmed-state
 * framebuffer generated in this retained database session. Full world
 * rasterization runs at 35/4 Hz; the three intervening tics reproject the
 * preceding exact world image from each newly confirmed camera, then draw current
 * sprites, weapon, palette effects, and HUD. No client prediction is involved.
 */
export function renderConfirmedTemporalFrame(playerSlot, frameTic) {
  if (!Number.isInteger(frameTic) || frameTic < 1 || frameTic !== retainedTic) {
    throw new Error(
      `invalid confirmed temporal frame: ${frameTic}/${retainedTic}`);
  }
  // Two-view diagnostics use the same alternating phase as the production
  // shared-view path. Each player still receives one exact world raster every
  // four tics; the expensive calls no longer land on the same tic.
  const worldRasterPhase =
    (playerSlot * (WORLD_RASTER_INTERVAL_TICS / 2))
      % WORLD_RASTER_INTERVAL_TICS;
  renderCompleteMatchFrame(
    playerSlot, false, frameTic, worldRasterPhase);
  return retainedPaletteIndex;
}

export function prewarmCompleteRenderer(iterations) {
  if (!Number.isInteger(iterations) || iterations < 1 || iterations > 600) {
    throw new Error(`invalid complete-renderer prewarm: ${iterations}`);
  }
  for (let iteration = 0; iteration < iterations; iteration++) {
    renderCompleteMatchFrame(0);
  }
  return iterations;
}

function newMatchLiveBatch(
    matchId, playerSlot, membershipEpoch, generation) {
  const length = LIVE_BATCH_HEADER_BYTES
    + MATCH_LIVE_BATCH_FRAMES * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
  const state = {
    matchId,
    playerSlot,
    membershipEpoch,
    generation,
    bytes: new Uint8Array(length),
    count: 0,
    firstTic: -1,
    lastTic: -1,
    sequence: 0,
  };
  state.bytes.set([68, 80, 66, 50], 0); // DPB2.
  putU32Be(state.bytes, 4, 0);
  return state;
}

function resetMatchLiveBatchPayload(state) {
  state.count = 0;
  state.firstTic = -1;
  state.lastTic = -1;
  state.bytes.set([68, 80, 66, 50], 0);
  putU32Be(state.bytes, 4, 0);
}

function appendMatchLiveFrame(state, frameTic, paletteIndex) {
  if (!(retainedFrame instanceof Uint8Array)
      || retainedFrame.byteLength !== FRAME_BYTES
      || !Number.isInteger(frameTic) || frameTic < 0
      || frameTic > 0xffffffff
      || !Number.isInteger(paletteIndex)
      || paletteIndex < 0 || paletteIndex > 13
      || state.count >= MATCH_LIVE_BATCH_FRAMES
      || (state.count > 0 && frameTic !== state.lastTic + 1)) {
    throw new Error(
      `invalid match live-frame append: ${frameTic}/${paletteIndex}`
        + `/${state.count}/${state.lastTic}`);
  }
  const record = LIVE_BATCH_HEADER_BYTES
    + state.count * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
  putU32Be(state.bytes, record, frameTic >>> 0);
  state.bytes[record + 4] = paletteIndex;
  state.bytes[record + 5] = exactPresentation ? 1 : 0;
  state.bytes[record + 6] = 0;
  state.bytes[record + 7] = 0;
  state.bytes.set(retainedFrame, record + LIVE_BATCH_RECORD_BYTES);
  if (state.count === 0) state.firstTic = frameTic;
  state.lastTic = frameTic;
  state.count++;
  putU32Be(state.bytes, 4, state.count);
  return state.count;
}

function persistMatchLiveBatch(state) {
  if (state.count < 1 || state.count > MATCH_LIVE_BATCH_FRAMES) {
    throw new Error(`invalid match live-frame batch count: ${state.count}`);
  }
  const length = LIVE_BATCH_HEADER_BYTES
    + state.count * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
  const ringSlot = state.sequence % 64;
  const result = oracledb.defaultConnection().execute(
    `update doom_match_live_frame_batch
        set first_tic=:firstTic,last_tic=:lastTic,
            frame_count=:frameCount,payload_bytes=:payloadBytes,
            payload_blob=empty_blob(),published_at=systimestamp
      where match_id=:matchId
        and player_slot=:playerSlot
        and ring_slot=:ringSlot
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload`,
    {
      firstTic: state.firstTic,
      lastTic: state.lastTic,
      frameCount: state.count,
      payloadBytes: length,
      matchId: state.matchId,
      playerSlot: state.playerSlot,
      ringSlot,
      membershipEpoch: state.membershipEpoch,
      generation: state.generation,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1
      || !(result.outBinds.payload[0] instanceof OracleBlob)) {
    throw new Error('match live-frame batch locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, state.bytes.subarray(0, length));
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the worker transaction rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  state.sequence++;
  resetMatchLiveBatchPayload(state);
  return length;
}

export function renderAndPublishMatchFrame(
    matchId, playerSlot, membershipEpoch, generation, frameTic) {
  let state = retainedMatchLiveBatches[playerSlot];
  const changed = state === undefined
    || state.matchId !== matchId
    || state.membershipEpoch !== membershipEpoch
    || state.generation !== generation;
  // A retained slot can carry the preceding match's translated sector,
  // sidedef, lighting, and scrolling state. DVL6 is intentionally a delta
  // stream and therefore cannot establish a new generation's baseline.
  // Seed every match/generation once with the full DVL2 world snapshot, then
  // return to bounded dirty-index deltas for ordinary tics.
  if (changed && !exactPresentation) {
    if (typeof renderer.resetWorldState !== 'function'
        || renderer.resetWorldState() < 1) {
      throw new Error('renderer dynamic-world baseline reset failed');
    }
  }
  renderCompleteMatchFrame(playerSlot, changed, frameTic);
  if (changed) {
    state = newMatchLiveBatch(
      matchId, playerSlot, membershipEpoch, generation);
    retainedMatchLiveBatches[playerSlot] = state;
  }
  appendMatchLiveFrame(state, frameTic, retainedPaletteIndex);
  // Publish an immediate generation seed; ordinary play amortizes six exact
  // frames per persistent locator crossing.
  if (changed || state.count === MATCH_LIVE_BATCH_FRAMES) {
    persistMatchLiveBatch(state);
  }
  return FRAME_BYTES;
}


function resetTemporalSoloState() {
  retainedTemporalIdentity = undefined;
  retainedTemporalPreviousTic = -1;
  retainedTemporalDeferredTics = [];
  retainedTemporalPrevious = undefined;
}

function temporalSoloIdentityMatches(
    matchId, membershipEpoch, generation, playerMask) {
  return retainedTemporalIdentity !== undefined
    && retainedTemporalIdentity.matchId === matchId
    && retainedTemporalIdentity.membershipEpoch === membershipEpoch
    && retainedTemporalIdentity.generation === generation
    && retainedTemporalIdentity.playerMask === playerMask;
}

function temporalKeyframeInterval(playerMask) {
  return playerMask === 1
    ? TEMPORAL_SOLO_KEYFRAME_INTERVAL
    : TEMPORAL_MULTIPLAYER_KEYFRAME_INTERVAL;
}

function captureTemporalExact(payloadBytes) {
  retainedTemporalExactBufferIndex ^= 1;
  let target = retainedTemporalExactBuffers[retainedTemporalExactBufferIndex];
  if (!(target instanceof Uint8Array) || target.byteLength !== payloadBytes) {
    target = new Uint8Array(payloadBytes);
    retainedTemporalExactBuffers[retainedTemporalExactBufferIndex] = target;
  }
  target.set(retainedMatchViews.subarray(0, payloadBytes));
  return target;
}

function synthesizeTemporalSoloFrame(
    previous, current, frameTic, payloadBytes, numerator, denominator) {
  if (!(retainedTemporalSynthesis instanceof Uint8Array)
      || retainedTemporalSynthesis.byteLength !== payloadBytes) {
    retainedTemporalSynthesis = new Uint8Array(payloadBytes);
  }
  const output = retainedTemporalSynthesis;
  output.set(current.subarray(0, MATCH_VIEW_HEADER_BYTES), 0);
  putU32Be(output, 4, frameTic >>> 0);
  const playerMask = current[8];
  const samePalette = previous[9] === current[9]
    && (playerMask !== 3 || previous[10] === current[10]);
  const sameLayout = previous[11] === current[11];
  if (!samePalette || !sameLayout) {
    // Palette flashes are rare and fidelity wins over an invalid cross-palette
    // dither. Reuse the newer confirmed pixels for this one intermediate tic.
    output.set(current.subarray(MATCH_VIEW_HEADER_BYTES),
      MATCH_VIEW_HEADER_BYTES);
    return output;
  }
  const words = (payloadBytes - MATCH_VIEW_HEADER_BYTES) >>> 2;
  const totalRows = FRAME_HEIGHT * (playerMask === 3 ? 2 : 1);
  const previous32 = new Uint32Array(
    previous.buffer, previous.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  const current32 = new Uint32Array(
    current.buffer, current.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  const output32 = new Uint32Array(
    output.buffer, output.byteOffset + MATCH_VIEW_HEADER_BYTES, words);
  if (denominator === 2) {
    for (let row = 0; row < totalRows; row++) {
      const mask = ((row + frameTic) & 1) === 0
        ? 0x00ff00ff : 0xff00ff00;
      const inverse = ~mask;
      const start = row * (FRAME_WIDTH >>> 2);
      const end = start + (FRAME_WIDTH >>> 2);
      for (let index = start; index < end; index++) {
        output32[index] =
          (previous32[index] & mask) | (current32[index] & inverse);
      }
    }
  } else if (denominator === 3 && (numerator === 1 || numerator === 2)) {
    const masks = new Int32Array(3);
    for (let startMod = 0; startMod < 3; startMod++) {
      let mask = 0;
      for (let byte = 0; byte < 4; byte++) {
        if (((startMod + byte + frameTic) % 3) < numerator) {
          mask |= 255 << (byte * 8);
        }
      }
      masks[startMod] = mask;
    }
    for (let row = 0; row < totalRows; row++) {
      let index = row * (FRAME_WIDTH >>> 2);
      const end = index + (FRAME_WIDTH >>> 2);
      let phase = (row * FRAME_WIDTH) % 3;
      while (index + 2 < end) {
        let mask = masks[phase];
        output32[index] =
          (previous32[index] & ~mask) | (current32[index] & mask);
        mask = masks[(phase + 1) % 3];
        output32[index + 1] =
          (previous32[index + 1] & ~mask)
            | (current32[index + 1] & mask);
        mask = masks[(phase + 2) % 3];
        output32[index + 2] =
          (previous32[index + 2] & ~mask)
            | (current32[index + 2] & mask);
        index += 3;
      }
      while (index < end) {
        const mask = masks[phase];
        output32[index] =
          (previous32[index] & ~mask) | (current32[index] & mask);
        phase = (phase + 1) % 3;
        index++;
      }
    }
  } else {
    throw new Error(
      `invalid temporal phase: ${numerator}/${denominator}`);
  }
  return output;
}


function persistTemporalMatchViewBatch(
    payloads, matchId, playerMask, membershipEpoch, generation) {
  if (!Array.isArray(payloads) || payloads.length < 1 || payloads.length > 6
      || (playerMask !== 1 && playerMask !== 3)) {
    throw new Error('invalid temporal match-view batch');
  }
  const firstTic = payloads[0].tic;
  const lastTic = payloads[payloads.length - 1].tic;
  for (let index = 0; index < payloads.length; index++) {
    if (payloads[index].tic !== firstTic + index
        || !(payloads[index].payload instanceof Uint8Array)
        || payloads[index].payload.byteLength
          !== MATCH_VIEW_HEADER_BYTES
            + (playerMask === 3 ? 2 : 1) * FRAME_BYTES) {
      throw new Error('invalid temporal match-view batch sequence');
    }
  }
  let persistedBytes = 0;
  for (let playerSlot = 0; playerSlot < 2; playerSlot++) {
    if ((playerMask & (1 << playerSlot)) === 0) continue;
    const bytes = new Uint8Array(
      LIVE_BATCH_HEADER_BYTES
        + payloads.length * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES));
    bytes.set([68, 80, 66, 50], 0); // DPB2.
    putU32Be(bytes, 4, payloads.length);
    for (let index = 0; index < payloads.length; index++) {
      const entry = payloads[index];
      const record = LIVE_BATCH_HEADER_BYTES
        + index * (LIVE_BATCH_RECORD_BYTES + FRAME_BYTES);
      putU32Be(bytes, record, entry.tic >>> 0);
      bytes[record + 4] = entry.payload[9 + playerSlot];
      bytes[record + 5] = entry.payload[11];
      bytes.set(entry.payload.subarray(
        MATCH_VIEW_HEADER_BYTES + playerSlot * FRAME_BYTES,
        MATCH_VIEW_HEADER_BYTES + (playerSlot + 1) * FRAME_BYTES),
      record + LIVE_BATCH_RECORD_BYTES);
    }
    const result = oracledb.defaultConnection().execute(
      `update doom_match_live_frame_batch
          set first_tic=:firstTic,last_tic=:lastTic,
              frame_count=:frameCount,payload_bytes=:payloadBytes,
              payload_blob=empty_blob(),published_at=systimestamp
        where match_id=:matchId
          and player_slot=:playerSlot
          and ring_slot=:ringSlot
          and membership_epoch=:membershipEpoch
          and generation=:generation
        returning payload_blob into :payload`,
      {
        firstTic,
        lastTic,
        frameCount: payloads.length,
        payloadBytes: bytes.byteLength,
        matchId,
        playerSlot,
        ringSlot: lastTic % 64,
        membershipEpoch,
        generation,
        payload: {
          dir: oracledb.BIND_OUT,
          type: oracledb.ORACLE_BLOB,
        },
      },
    );
    if (result.rowsAffected !== 1
        || !Array.isArray(result.outBinds.payload)
        || result.outBinds.payload.length !== 1
        || !(result.outBinds.payload[0] instanceof OracleBlob)) {
      throw new Error('temporal match-view batch locator acquisition failed');
    }
    const payload = result.outBinds.payload[0];
    let opened = false;
    try {
      payload.open(OracleBlob.LOB_READWRITE);
      opened = true;
      payload.write(1, bytes);
    } catch (failure) {
      if (opened) {
        try {
          payload.close();
        } catch {
          // Preserve the write failure; the enclosing SQL call rolls back.
        }
      }
      throw failure;
    }
    payload.close();
    persistedBytes += bytes.byteLength;
  }
  return persistedBytes;
}

function persistTemporalMatchView(
    payloadBytes, matchId, playerMask,
    membershipEpoch, generation, frameTic) {
  const result = oracledb.defaultConnection().execute(
    `update doom_match_live_frame_views
        set tic=:frameTic,player_mask=:playerMask,
            payload_bytes=:payloadBytes,payload_blob=empty_blob(),
            published_at=systimestamp
      where match_id=:matchId
        and ring_slot=mod(:frameTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload`,
    {
      frameTic,
      playerMask,
      payloadBytes: payloadBytes.byteLength,
      matchId,
      membershipEpoch,
      generation,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1
      || !(result.outBinds.payload[0] instanceof OracleBlob)) {
    throw new Error('temporal match-view locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, payloadBytes);
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the enclosing SQL call rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  return payloadBytes.byteLength;
}

/**
 * Immediate shared-view path. Both complete authenticated POV framebuffers
 * cross one persistent locator, so every authoritative tic becomes visible
 * without doubling the batch-2 path's effective locator rate.
 */
export function prepareMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic) {
  if (typeof matchId !== 'string' || !/^[0-9a-f]{32}$/.test(matchId)
      || (playerMask !== 1 && playerMask !== 3)
      || !Number.isSafeInteger(membershipEpoch) || membershipEpoch < 1
      || !Number.isSafeInteger(generation) || generation < 1
      || !Number.isSafeInteger(frameTic) || frameTic < 1
      || frameTic > 0xffffffff) {
    throw new Error(
      `invalid shared match views: ${matchId}/${playerMask}`
        + `/${membershipEpoch}/${generation}/${frameTic}`);
  }
  const temporalSame = temporalSoloIdentityMatches(
    matchId, membershipEpoch, generation, playerMask);
  const temporalInterval = temporalKeyframeInterval(playerMask);
  if (temporalSame
      && retainedTemporalDeferredTics.length
        < temporalInterval - 1
      && frameTic === retainedTemporalPreviousTic
        + retainedTemporalDeferredTics.length + 1) {
    retainedTemporalDeferredTics.push(frameTic);
    retainedPreparedMatchViews = {
      matchId,
      playerMask,
      membershipEpoch,
      generation,
      frameTic,
      outputOffset: MATCH_VIEW_HEADER_BYTES
        + (playerMask === 3 ? 2 : 1) * FRAME_BYTES,
      temporalDeferred: true,
    };
    return retainedPreparedMatchViews.outputOffset;
  }
  if (!temporalSame) resetTemporalSoloState();
  const changed = retainedMatchViewIdentity === undefined
    || retainedMatchViewIdentity.matchId !== matchId
    || retainedMatchViewIdentity.membershipEpoch !== membershipEpoch
    || retainedMatchViewIdentity.generation !== generation;
  if (changed) {
    if (!exactPresentation
        && (typeof renderer.resetWorldState !== 'function'
        || renderer.resetWorldState() < 1)) {
      throw new Error('shared-view dynamic-world baseline reset failed');
    }
    clearRetainedWorldFrames();
    retainedMatchViewIdentity = {matchId, membershipEpoch, generation};
  }
  if (!(retainedMatchViews instanceof Uint8Array)
      || retainedMatchViews.byteLength
        !== MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES) {
    retainedMatchViews =
      new Uint8Array(MATCH_VIEW_HEADER_BYTES + 2 * FRAME_BYTES);
  }
  retainedMatchViews.fill(0, 0, MATCH_VIEW_HEADER_BYTES);
  retainedMatchViews.set([68, 80, 68, 49], 0); // DPD1.
  putU32Be(retainedMatchViews, 4, frameTic >>> 0);
  retainedMatchViews[8] = playerMask;
  retainedMatchViews[9] = 255;
  retainedMatchViews[10] = 255;
  retainedMatchViews[11] = exactPresentation ? 1 : 0;
  let outputOffset = MATCH_VIEW_HEADER_BYTES;
  let first = true;
  for (let playerSlot = 0; playerSlot < 2; playerSlot++) {
    if ((playerMask & (1 << playerSlot)) === 0) continue;
    const worldRasterPhase =
      (playerSlot * (WORLD_RASTER_INTERVAL_TICS / 2))
        % WORLD_RASTER_INTERVAL_TICS;
    renderCompleteMatchFrame(
      playerSlot, changed && first, frameTic, worldRasterPhase);
    retainedMatchViews[9 + playerSlot] = retainedPaletteIndex;
    retainedMatchViews.set(retainedFrame, outputOffset);
    outputOffset += FRAME_BYTES;
    first = false;
  }
  retainedPreparedMatchViews = {
    matchId,
    playerMask,
    membershipEpoch,
    generation,
    frameTic,
    outputOffset,
  };
  if (playerMask === 1 || playerMask === 3) {
    const current = captureTemporalExact(outputOffset);
    const payloads = [];
    if (temporalSame && retainedTemporalPrevious instanceof Uint8Array
        && retainedTemporalDeferredTics.length
          === temporalInterval - 1
        && retainedTemporalPreviousTic
          === frameTic - temporalInterval) {
      for (let phase = 0;
          phase < retainedTemporalDeferredTics.length; phase++) {
        const deferredTic = retainedTemporalDeferredTics[phase];
        // Copy because the retained synthesis buffer is reused for the next
        // phase before publication begins.
        const synthesized = new Uint8Array(outputOffset);
        synthesized.set(synthesizeTemporalSoloFrame(
          retainedTemporalPrevious, current, deferredTic, outputOffset,
          phase + 1, temporalInterval));
        payloads.push({tic: deferredTic, payload: synthesized});
      }
    }
    payloads.push({tic: frameTic, payload: current});
    retainedTemporalIdentity = {
      matchId, membershipEpoch, generation, playerMask};
    retainedTemporalPrevious = current;
    retainedTemporalPreviousTic = frameTic;
    retainedTemporalDeferredTics = [];
    retainedPreparedMatchViews.temporalPayloads = payloads;
  }
  return outputOffset;
}

export function publishPreparedMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic) {
  const prepared = retainedPreparedMatchViews;
  if (prepared === undefined
      || prepared.matchId !== matchId
      || prepared.playerMask !== playerMask
      || prepared.membershipEpoch !== membershipEpoch
      || prepared.generation !== generation
      || prepared.frameTic !== frameTic
      || !(retainedMatchViews instanceof Uint8Array)
      || prepared.outputOffset < MATCH_VIEW_HEADER_BYTES + FRAME_BYTES
      || prepared.outputOffset > retainedMatchViews.byteLength) {
    throw new Error('shared match-view publication is not prepared');
  }
  const outputOffset = prepared.outputOffset;
  if (prepared.temporalDeferred === true) {
    retainedPreparedMatchViews = undefined;
    return outputOffset;
  }
  if (Array.isArray(prepared.temporalPayloads)) {
    persistTemporalMatchViewBatch(
      prepared.temporalPayloads, matchId, playerMask,
      membershipEpoch, generation);
    retainedPreparedMatchViews = undefined;
    return outputOffset;
  }
  const result = oracledb.defaultConnection().execute(
    `update doom_match_live_frame_views
        set tic=:frameTic,player_mask=:playerMask,
            payload_bytes=:payloadBytes,payload_blob=empty_blob(),
            published_at=systimestamp
      where match_id=:matchId
        and ring_slot=mod(:frameTic,64)
        and membership_epoch=:membershipEpoch
        and generation=:generation
      returning payload_blob into :payload`,
    {
      frameTic,
      playerMask,
      payloadBytes: outputOffset,
      matchId,
      membershipEpoch,
      generation,
      payload: {
        dir: oracledb.BIND_OUT,
        type: oracledb.ORACLE_BLOB,
      },
    },
  );
  if (result.rowsAffected !== 1
      || !Array.isArray(result.outBinds.payload)
      || result.outBinds.payload.length !== 1
      || !(result.outBinds.payload[0] instanceof OracleBlob)) {
    throw new Error('shared match-view locator acquisition failed');
  }
  const payload = result.outBinds.payload[0];
  let opened = false;
  try {
    payload.open(OracleBlob.LOB_READWRITE);
    opened = true;
    payload.write(1, retainedMatchViews.subarray(0, outputOffset));
  } catch (failure) {
    if (opened) {
      try {
        payload.close();
      } catch {
        // Preserve the write failure; the worker transaction rolls back.
      }
    }
    throw failure;
  }
  payload.close();
  retainedPreparedMatchViews = undefined;
  return outputOffset;
}

export function renderAndPublishMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic) {
  prepareMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic);
  return publishPreparedMatchViews(
    matchId, playerMask, membershipEpoch, generation, frameTic);
}

export function flushMatchLiveFrameBatches(
    matchId, membershipEpoch, generation) {
  let flushed = 0;
  for (const state of retainedMatchLiveBatches) {
    if (state !== undefined && state.matchId === matchId
        && state.membershipEpoch === membershipEpoch
        && state.generation === generation && state.count > 0) {
      persistMatchLiveBatch(state);
      flushed++;
    }
  }
  return flushed;
}

export function release() {
  authorityEngine.release();
  if (!exactPresentation && renderer.resetPresentationState() !== 10) {
    throw new Error('renderer presentation state reset failed');
  }
  retainedFrame = undefined;
  retainedSnapshot = undefined;
  compositorSnapshot = undefined;
  compositorSnapshotLength = 0;
  retainedPaletteIndex = 0;
  nativeFrameSelections = 0;
  nativeSnapshotSelections = 0;
  retainedTic = 0;
  retainedOriginCheckpoint = undefined;
  retainedLiveBatch = undefined;
  retainedLiveBatchCapacity = 0;
  retainedLiveBatchCount = 0;
  retainedMatchLiveBatches = [undefined, undefined, undefined, undefined];
  retainedMatchViews = undefined;
  retainedMatchViewIdentity = undefined;
  retainedPreparedMatchViews = undefined;
  resetTemporalSoloState();
  retainedTemporalExactBuffers = [undefined, undefined];
  retainedTemporalSynthesis = undefined;
  discardedAssets.clear();
  clearRetainedWorldFrames();
}
