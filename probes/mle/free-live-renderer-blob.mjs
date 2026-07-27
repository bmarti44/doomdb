import * as geometry from 'doom_free_generated_renderer';

const WIDTH = 320;
const HEIGHT = 200;
const PIXELS = WIDTH * HEIGHT;
const CACHE_SIZE = 262144;
const TAPE_MAGIC = 0x31575244;

const background = new Uint8Array(HEIGHT);
for (let y = 0; y < HEIGHT; y += 1) {
  background[y] = y < HEIGHT / 2 ? 96 : 48;
}
const cache = new Array(CACHE_SIZE);
const spanAt = new Array(PIXELS);
const touched = new Int32Array(4096);
let frame;
let retainedStats = '0|0|0|0';

export function allocatePack(length) {
  return geometry.allocatePack(length);
}

export function loadPackChunk(offset, chunk) {
  return geometry.loadPackChunk(offset, chunk);
}

export function finalizePack() {
  return geometry.finalizePack();
}

export function allocateWallTextures(length) {
  return geometry.allocateWallTextures(length);
}

export function loadWallTextureChunk(offset, chunk) {
  return geometry.loadWallTextureChunk(offset, chunk);
}

export function finalizeWallTextures() {
  return geometry.finalizeWallTextures();
}

export function reset() {
  cache.fill(undefined);
  for (let index = 0; index < touched.length; index += 1) {
    const target = touched[index];
    if (target >= 0 && target < PIXELS) spanAt[target] = undefined;
    touched[index] = 0;
  }
  geometry.resetNativeCache();
  frame = undefined;
  retainedStats = '0|0|0|0';
  return CACHE_SIZE;
}

export async function renderFrame(pose) {
  const tapeLength = geometry.renderNativeTape(pose);
  const tape = geometry.commandBufferByRef();
  if (!ArrayBuffer.isView(tape) || tapeLength < 16
      || tapeLength > tape.byteLength) {
    throw new Error(`invalid generated native tape ${tapeLength}`);
  }
  const view = new DataView(tape.buffer, tape.byteOffset, tapeLength);
  if (view.getUint32(0, true) !== TAPE_MAGIC
      || view.getUint32(12, true) !== tapeLength) {
    throw new Error('generated native tape header mismatch');
  }
  const expectedCommands = view.getUint32(4, true);
  const expectedMisses = view.getUint32(8, true);
  if (expectedCommands > touched.length) {
    throw new Error(`native tape command overflow ${expectedCommands}`);
  }

  let at = 16;
  let commandCount = 0;
  let missCount = 0;
  while (at < tapeLength) {
    if (at + 8 > tapeLength) throw new Error('truncated native tape record');
    const slot = view.getUint32(at, false);
    const target = view.getUint16(at + 4, false);
    const length = view.getUint8(at + 6);
    const miss = view.getUint8(at + 7);
    at += 8;
    if (slot >= CACHE_SIZE || target + length > PIXELS
        || length < 1 || miss > 1 || spanAt[target] !== undefined) {
      throw new Error(`invalid or duplicate native tape target ${target}`);
    }
    let pixels;
    if (miss === 1) {
      if (at + length > tapeLength) {
        throw new Error('truncated native tape literal');
      }
      pixels = tape.slice(at, at + length);
      cache[slot] = pixels;
      at += length;
      missCount += 1;
    } else {
      pixels = cache[slot];
      if (!(pixels instanceof Int8Array || pixels instanceof Uint8Array)
          || pixels.byteLength !== length) {
        throw new Error(`native tape dictionary desync ${slot}`);
      }
    }
    spanAt[target] = pixels;
    touched[commandCount] = target;
    commandCount += 1;
  }
  if (at !== tapeLength || commandCount !== expectedCommands
      || missCount !== expectedMisses) {
    throw new Error('native tape counter mismatch');
  }

  const parts = [];
  let consumed = 0;
  for (let x = 0; x < WIDTH; x += 1) {
    const base = x * HEIGHT;
    let cursor = 0;
    for (let y = 0; y < HEIGHT;) {
      const pixels = spanAt[base + y];
      if (pixels === undefined) {
        y += 1;
        continue;
      }
      if (y > cursor) parts.push(background.subarray(cursor, y));
      parts.push(pixels);
      cursor = y + pixels.byteLength;
      y = cursor;
      consumed += 1;
    }
    if (cursor < HEIGHT) parts.push(background.subarray(cursor));
  }
  if (consumed !== commandCount) {
    throw new Error(`overlapping native spans ${consumed}/${commandCount}`);
  }

  frame = new Uint8Array(await new Blob(parts).arrayBuffer());
  if (frame.byteLength !== PIXELS) {
    throw new Error(`native Blob framebuffer length ${frame.byteLength}`);
  }
  for (let index = 0; index < commandCount; index += 1) {
    spanAt[touched[index]] = undefined;
  }
  retainedStats = `${commandCount}|${missCount}|${parts.length}|${tapeLength}`;
  return frame;
}

export function frameChunk(offset, length) {
  if (!(frame instanceof Uint8Array)
      || !Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length < 0 || length > 32767
      || offset + length > frame.byteLength) {
    throw new Error('Blob framebuffer chunk outside frame');
  }
  return frame.subarray(offset, offset + length);
}

export function stats() {
  return retainedStats;
}

export function renderReference(pose) {
  return geometry.renderFrame(pose);
}

export function referenceChunk(offset, length) {
  return geometry.frameChunk(offset, length);
}
