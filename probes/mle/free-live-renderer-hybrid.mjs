import * as geometry from 'doom_free_generated_renderer';

const WIDTH = 320;
const HEIGHT = 200;
const PIXELS = WIDTH * HEIGHT;
const MAGIC = 0x31465244;
const COMMAND_BYTES = 24;
const CACHE_SIZE = 262144;

let pack;
let packView;
let wallTextures;
let wallTextureExpectedBytes;
let wallTextureElements;
let textureBase;
let textureWidth;
let textureHeight;
let sectorLight;
let colormaps;
let lightToBank;
let lightBankCount;
let litTextures;
let frame;
let backgroundColumn;
let cacheKeyA;
let cacheKeyB;
let cacheKeyC;
let cacheColumns;
let retainedCommandCount;
let retainedCommands;
let retainedPixelScale = 1;
let cacheHits;
let cacheMisses;

function u32(offset) {
  return packView.getUint32(offset, true);
}

export function allocatePack(length) {
  if (!Number.isInteger(length) || length < 288 || length > 1000000) {
    throw new Error(`invalid hybrid pack length ${length}`);
  }
  pack = new Uint8Array(length);
  packView = undefined;
  const generatedLength = geometry.allocatePack(length);
  if (generatedLength !== length) {
    throw new Error(`generated pack allocation mismatch ${generatedLength}`);
  }
  return length;
}

export function loadPackChunk(offset, chunk) {
  if (!(chunk instanceof Uint8Array)
      || !Number.isInteger(offset)
      || offset < 0
      || pack === undefined
      || offset + chunk.byteLength > pack.byteLength) {
    throw new Error('hybrid pack chunk is outside allocation');
  }
  pack.set(chunk, offset);
  const generatedOffset = geometry.loadPackChunk(offset, chunk);
  if (generatedOffset !== offset + chunk.byteLength) {
    throw new Error(`generated pack load mismatch ${generatedOffset}`);
  }
  return offset + chunk.byteLength;
}

export function finalizePack() {
  if (!(pack instanceof Uint8Array)) {
    throw new Error('hybrid pack is absent');
  }
  packView = new DataView(pack.buffer, pack.byteOffset, pack.byteLength);
  if (u32(0) !== MAGIC || u32(4) !== 7 || u32(76) !== pack.byteLength) {
    throw new Error('hybrid pack header mismatch');
  }
  const generatedLength = geometry.finalizePack();
  if (generatedLength !== pack.byteLength) {
    throw new Error(`generated pack finalize mismatch ${generatedLength}`);
  }
  const textureCount = u32(80);
  wallTextureElements = u32(84);
  wallTextureExpectedBytes = wallTextureElements * 2;
  textureBase = new Uint32Array(
    pack.buffer, pack.byteOffset + u32(88), textureCount);
  textureWidth = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(92), textureCount);
  textureHeight = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(96), textureCount);
  const sectorCount = u32(120);
  sectorLight = new Uint8Array(
    pack.buffer, pack.byteOffset + u32(132), sectorCount);
  colormaps = new Uint8Array(
    pack.buffer, pack.byteOffset + u32(136), 8192);
  frame = new Uint8Array(PIXELS);
  backgroundColumn = new Uint8Array(HEIGHT);
  for (let y = 0; y < HEIGHT; y += 1) {
    backgroundColumn[y] = y < HEIGHT / 2 ? 96 : 48;
  }
  cacheKeyA = new Int32Array(CACHE_SIZE);
  cacheKeyB = new Int32Array(CACHE_SIZE);
  cacheKeyC = new Int32Array(CACHE_SIZE);
  cacheColumns = new Array(CACHE_SIZE);
  return pack.byteLength;
}

export function allocateWallTextures(length) {
  if (!Number.isInteger(length) || length < 1 || length > 10000000) {
    throw new Error(`invalid hybrid wall texture length ${length}`);
  }
  wallTextures = new Uint8Array(length);
  return length;
}

export function loadWallTextureChunk(offset, chunk) {
  if (!(chunk instanceof Uint8Array)
      || !Number.isInteger(offset)
      || offset < 0
      || wallTextures === undefined
      || offset + chunk.byteLength > wallTextures.byteLength) {
    throw new Error('hybrid wall texture chunk is outside allocation');
  }
  wallTextures.set(chunk, offset);
  return offset + chunk.byteLength;
}

export function finalizeWallTextures() {
  if (!(wallTextures instanceof Uint8Array)
      || wallTextures.byteLength !== wallTextureExpectedBytes) {
    throw new Error(
      `hybrid wall texture length mismatch `
      + `${wallTextures?.byteLength}/${wallTextureExpectedBytes}`,
    );
  }
  lightToBank = new Int8Array(32);
  lightToBank.fill(-1);
  lightBankCount = 0;
  for (let sector = 0; sector < sectorLight.length; sector += 1) {
    const map = Math.max(
      0, Math.min(31, Math.floor((255 - sectorLight[sector]) / 8)));
    if (lightToBank[map] < 0) {
      lightToBank[map] = lightBankCount;
      lightBankCount += 1;
    }
  }
  litTextures = new Uint8Array(wallTextureElements * lightBankCount);
  for (let map = 0; map < 32; map += 1) {
    const bank = lightToBank[map];
    if (bank < 0) continue;
    const target = bank * wallTextureElements;
    for (let texel = 0; texel < wallTextureElements; texel += 1) {
      const encodedAt = texel * 2;
      const encoded = (wallTextures[encodedAt] << 8)
        | wallTextures[encodedAt + 1];
      const sample = encoded === 0 ? 0 : encoded - 1;
      litTextures[target + texel] = colormaps[map * 256 + sample];
    }
  }
  const loadedBytes = wallTextures.byteLength;
  wallTextures = undefined;
  return loadedBytes;
}

function cachedWallSegment(
    texture, textureX, wallHeight, projectedTop,
    drawTop, drawBottom, lightMap, verticalOffset) {
  const width = textureWidth[texture];
  const height = textureHeight[texture];
  textureX %= width;
  if (textureX < 0) textureX += width;
  let normalizedOffset = verticalOffset % height;
  if (normalizedOffset < 0) normalizedOffset += height;
  const keyA = (texture | (textureX << 16)) | 0;
  const keyB = (
    (Math.min(65535, wallHeight) & 0xffff)
    | (lightMap << 16)
    | (normalizedOffset << 21)
  ) | 0;
  const keyC = (
    (projectedTop & 0xffff)
    | (drawTop << 16)
    | (drawBottom << 24)
  ) | 0;
  let hash = keyA ^ Math.imul(keyB, 40503) ^ Math.imul(keyC, 7919);
  hash ^= hash >>> 13;
  hash = Math.imul(hash, -1640531527);
  hash ^= hash >>> 16;
  const slot = (hash >>> 0) & (CACHE_SIZE - 1);
  let column = cacheColumns[slot];
  if (column !== undefined
      && cacheKeyA[slot] === keyA
      && cacheKeyB[slot] === keyB
      && cacheKeyC[slot] === keyC) {
    cacheHits += 1;
    return column;
  }
  cacheMisses += 1;
  const length = drawBottom - drawTop + 1;
  if (column === undefined || column.length !== length) {
    column = new Uint8Array(length);
  }
  let textureY = normalizedOffset
    + (drawTop - projectedTop) * 128 / wallHeight;
  const textureStep = 128 / wallHeight;
  const base = textureBase[texture];
  const bank = lightToBank[lightMap] * wallTextureElements;
  for (let output = 0; output < length; output += 1) {
    let sourceY = Math.floor(textureY) % height;
    if (sourceY < 0) sourceY += height;
    column[output] = litTextures[
      bank + base + sourceY * width + textureX
    ];
    textureY += textureStep;
  }
  cacheKeyA[slot] = keyA;
  cacheKeyB[slot] = keyB;
  cacheKeyC[slot] = keyC;
  cacheColumns[slot] = column;
  return column;
}

export function renderFrame(pose) {
  if (!(litTextures instanceof Uint8Array)) {
    throw new Error('hybrid wall textures are not finalized');
  }
  clearFrame();
  generateCommands(pose);
  rasterizeCommands();
  return retainedCommandCount
    + frame[pose % PIXELS]
    + (frame[(pose * 997) % PIXELS] << 8);
}

export function renderFrameHalfWidth(pose) {
  if (!(litTextures instanceof Uint8Array)) {
    throw new Error('hybrid wall textures are not finalized');
  }
  clearFrame();
  generateCommandsHalfWidth(pose);
  rasterizeCommands();
  return retainedCommandCount
    + frame[pose % PIXELS]
    + (frame[(pose * 997) % PIXELS] << 8);
}

export function clearFrame() {
  for (let x = 0; x < WIDTH; x += 1) {
    frame.set(backgroundColumn, x * HEIGHT);
  }
  return PIXELS;
}

export function generateCommands(pose) {
  const commandCount = geometry.renderCommands(pose);
  retainedPixelScale = 1;
  return retainGeneratedCommands(commandCount);
}

export function generateCommandsHalfWidth(pose) {
  const commandCount = geometry.renderCommandsHalfWidth(pose);
  retainedPixelScale = 2;
  return retainGeneratedCommands(commandCount);
}

function retainGeneratedCommands(commandCount) {
  const exported = geometry.commandBufferByRef();
  if (!ArrayBuffer.isView(exported)
      || !Number.isInteger(commandCount)
      || commandCount < 0
      || commandCount * COMMAND_BYTES > exported.byteLength) {
    throw new Error(
      `invalid generated command tape ${commandCount}/${exported?.byteLength}`,
    );
  }
  retainedCommands = new DataView(
    exported.buffer, exported.byteOffset, commandCount * COMMAND_BYTES);
  retainedCommandCount = commandCount;
  return commandCount;
}

export function rasterizeCommands() {
  if (!(retainedCommands instanceof DataView)
      || !Number.isInteger(retainedCommandCount)
      || retainedCommandCount < 0) {
    throw new Error('hybrid wall command tape is absent');
  }
  cacheHits = 0;
  cacheMisses = 0;
  for (let command = 0; command < retainedCommandCount; command += 1) {
    const at = command * COMMAND_BYTES;
    const screenX = retainedCommands.getUint16(at, true);
    const texture = retainedCommands.getUint16(at + 2, true);
    const textureX = retainedCommands.getInt32(at + 4, true);
    const wallHeight = retainedCommands.getUint16(at + 8, true);
    const lightMap = retainedCommands.getUint8(at + 10);
    const projectedTop = retainedCommands.getInt32(at + 12, true);
    const drawTop = retainedCommands.getUint16(at + 16, true);
    const drawBottom = retainedCommands.getUint16(at + 18, true);
    const verticalOffset = retainedCommands.getInt32(at + 20, true);
    if (screenX * retainedPixelScale >= WIDTH || texture >= textureBase.length
        || wallHeight < 1 || lightToBank[lightMap] < 0
        || drawTop > drawBottom || drawBottom >= HEIGHT) {
      throw new Error(`invalid generated wall command ${command}`);
    }
    const column = cachedWallSegment(
      texture, textureX, wallHeight, projectedTop,
      drawTop, drawBottom, lightMap, verticalOffset,
    );
    const outputX = screenX * retainedPixelScale;
    frame.set(column, outputX * HEIGHT + drawTop);
    if (retainedPixelScale === 2) {
      frame.set(column, (outputX + 1) * HEIGHT + drawTop);
    }
  }
  return retainedCommandCount;
}

export function renderFrameBatch(start, count) {
  if (!Number.isInteger(start) || !Number.isInteger(count)
      || start < 0 || count < 1) {
    throw new Error(`invalid hybrid frame batch ${start}/${count}`);
  }
  let checksum = 0;
  for (let index = 0; index < count; index += 1) {
    checksum += renderFrame(start + index);
  }
  return checksum;
}

export function frameByRef() {
  return frame;
}

export function frameChunk(offset, length) {
  if (!Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length < 0 || offset + length > PIXELS) {
    throw new Error(`hybrid frame chunk is outside framebuffer ${offset}/${length}`);
  }
  return frame.subarray(offset, offset + length);
}

export function stats() {
  return `${retainedCommandCount}|${cacheHits}|${cacheMisses}`;
}
