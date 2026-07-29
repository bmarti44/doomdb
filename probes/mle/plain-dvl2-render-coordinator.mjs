import * as engine from 'doom_dvl2_engine';
import * as renderer from 'doom_plain_renderer';

let retainedFrame;
let retainedSnapshot;
let ignoredAssetLength = 0;

export function allocateIwad(length) {
  return engine.allocateIwad(length);
}
export function loadIwadChunk(offset, chunk) {
  return engine.loadIwadChunk(offset, chunk);
}
export function allocateTablePack(length) {
  return engine.allocateTablePack(length);
}
export function loadTablePackChunk(offset, chunk) {
  return engine.loadTablePackChunk(offset, chunk);
}
export function allocateRendererPack(length) {
  return renderer.allocatePack(length);
}
export function loadRendererPackChunk(offset, chunk) {
  return renderer.loadPackChunk(offset, chunk);
}
export function finalizeRendererPack() {
  return renderer.finalizePack();
}
export function allocateWallTextures(length) {
  return renderer.allocateWallTextures(length);
}
export function loadWallTextureChunk(offset, chunk) {
  return renderer.loadWallTextureChunk(offset, chunk);
}
export function finalizeWallTextures() {
  return renderer.finalizeWallTextures();
}
export function allocateFlatTextures(length) {
  return renderer.allocateFlatTextures(length);
}
export function loadFlatTextureChunk(offset, chunk) {
  return renderer.loadFlatTextureChunk(offset, chunk);
}
export function finalizeFlatTextures() {
  return renderer.finalizeFlatTextures();
}
export function setColumnRange(start, end) {
  return renderer.setColumnRange(start, end);
}
export function allocateSpriteTextures(length) {
  ignoredAssetLength = length;
  return length;
}
export function loadSpriteTextureChunk(offset, chunk) {
  return offset + chunk.byteLength;
}
export function finalizeSpriteTextures() {
  return ignoredAssetLength;
}
export function allocateUiTextures(length) {
  ignoredAssetLength = length;
  return length;
}
export function loadUiTextureChunk(offset, chunk) {
  return offset + chunk.byteLength;
}
export function finalizeUiTextures() {
  return ignoredAssetLength;
}
export function initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map) {
  return engine.initializeMultiplayerGame(
    activePlayers, deathmatch, skill, episode, map);
}

function currentSnapshot(playerSlot) {
  const length = engine.presentationWorldSnapshotLength(playerSlot);
  const exported = engine.presentationWorldSnapshotByRef();
  if (!ArrayBuffer.isView(exported)
      || length < 208 || length > exported.byteLength) {
    throw new Error(
      `invalid retained DVL2 snapshot: ${length}/${exported?.byteLength}`);
  }
  const bytes = exported instanceof Uint8Array
    ? exported
    : new Uint8Array(exported.buffer, exported.byteOffset, exported.byteLength);
  retainedSnapshot = bytes.subarray(0, length);
  return retainedSnapshot;
}

function retainRenderedFrame() {
  const exported = renderer.frameByRef();
  if (!ArrayBuffer.isView(exported) || exported.byteLength !== 64000) {
    throw new Error(`invalid retained frame: ${exported?.byteLength}`);
  }
  retainedFrame = exported instanceof Uint8Array
    ? exported
    : new Uint8Array(exported.buffer, exported.byteOffset, exported.byteLength);
}

export function renderCurrentFrame(playerSlot) {
  const checksum = renderer.renderWorldGeometry(currentSnapshot(playerSlot));
  retainRenderedFrame();
  return checksum;
}
export function stepAndRender(
    activePlayers, membershipMask, commands, playerSlot) {
  const tic = engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
  renderCurrentFrame(playerSlot);
  return tic;
}
export function stepAndRenderStatic(
    activePlayers, membershipMask, commands, playerSlot) {
  const tic = engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
  renderer.renderWorldGeometryStatic(currentSnapshot(playerSlot));
  retainRenderedFrame();
  return tic;
}
export function stepAndRenderFast(
    activePlayers, membershipMask, commands, playerSlot) {
  const tic = engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
  renderer.renderWorldFastGeometryStatic(currentSnapshot(playerSlot));
  retainRenderedFrame();
  return tic;
}
export function stepAndGenerateCommands(
    activePlayers, membershipMask, commands, playerSlot) {
  const tic = engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
  renderer.renderWorldCommandGeometryStatic(currentSnapshot(playerSlot));
  return tic;
}
export function stepOnly(activePlayers, membershipMask, commands) {
  return engine.stepMultiplayerAuthoritative(
    activePlayers, membershipMask, commands);
}
export function loadCurrentDynamics(playerSlot) {
  return renderer.loadWorldDynamicsStage(currentSnapshot(playerSlot));
}
export function renderLoadedWalls() {
  const checksum = renderer.renderLoadedWorldWalls(retainedSnapshot);
  retainRenderedFrame();
  return checksum;
}
export function renderLoadedGeometry() {
  const checksum = renderer.renderLoadedWorldGeometry(retainedSnapshot);
  retainRenderedFrame();
  return checksum;
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
export function rendererStats() {
  return renderer.stats();
}
export function release() {
  engine.release();
  retainedFrame = undefined;
}
