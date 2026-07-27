const WIDTH = 160;
const HEIGHT = 100;
const PIXELS = WIDTH * HEIGHT;
const MAGIC = 0x31465244;
let pack;
let view;
let frame;
let background;
let lineX1;
let lineY1;
let lineX2;
let lineY2;
let cellOffsets;
let cellLines;
let sinTable;
let cosTable;
let poseOffset;
let poseCount;
let originX;
let originY;
let blockColumns;
let blockRows;
let lineTests = 0;
let cellsVisited = 0;

export function allocatePack(length) {
  if (!Number.isInteger(length) || length < 96 || length > 1000000) {
    throw new Error(`invalid live-render pack length ${length}`);
  }
  pack = new Uint8Array(length);
  view = undefined;
  return length;
}

export function loadPackChunk(offset, chunk) {
  if (!(chunk instanceof Uint8Array)
      || !Number.isInteger(offset)
      || offset < 0
      || pack === undefined
      || offset + chunk.byteLength > pack.byteLength) {
    throw new Error('live-render pack chunk is outside allocation');
  }
  pack.set(chunk, offset);
  return offset + chunk.byteLength;
}

function u32(offset) {
  return view.getUint32(offset, true);
}

export function finalizePack() {
  if (pack === undefined) throw new Error('live-render pack is absent');
  view = new DataView(pack.buffer, pack.byteOffset, pack.byteLength);
  if (u32(0) !== MAGIC || u32(4) !== 1 || u32(76) !== pack.byteLength) {
    throw new Error('live-render pack header mismatch');
  }
  originX = view.getInt32(8, true);
  originY = view.getInt32(12, true);
  blockColumns = u32(16);
  blockRows = u32(20);
  const lineCount = u32(24);
  const cellCount = u32(28);
  const cellRefCount = u32(32);
  poseCount = u32(36);
  if (cellCount !== blockColumns * blockRows || poseCount !== 5250) {
    throw new Error('live-render pack cardinality mismatch');
  }
  lineX1 = new Int32Array(pack.buffer, pack.byteOffset + u32(40), lineCount);
  lineY1 = new Int32Array(pack.buffer, pack.byteOffset + u32(44), lineCount);
  lineX2 = new Int32Array(pack.buffer, pack.byteOffset + u32(48), lineCount);
  lineY2 = new Int32Array(pack.buffer, pack.byteOffset + u32(52), lineCount);
  cellOffsets = new Uint32Array(
    pack.buffer, pack.byteOffset + u32(56), cellCount + 1);
  cellLines = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(60), cellRefCount);
  poseOffset = u32(64);
  sinTable = new Int16Array(pack.buffer, pack.byteOffset + u32(68), 2048);
  cosTable = new Int16Array(pack.buffer, pack.byteOffset + u32(72), 2048);
  frame = new Uint8Array(PIXELS);
  background = new Uint8Array(PIXELS);
  for (let y = 0; y < HEIGHT; y += 1) {
    const color = y < HEIGHT / 2 ? 96 : 48;
    for (let x = 0; x < WIDTH; x += 1) {
      background[y * WIDTH + x] = color;
    }
  }
  return pack.byteLength;
}

function render(index) {
  if (view === undefined || frame === undefined) {
    throw new Error('live-render pack has not been finalized');
  }
  index %= poseCount;
  const at = poseOffset + index * 12;
  const playerX = view.getInt32(at, true) / 65536;
  const playerY = view.getInt32(at + 4, true) / 65536;
  const angle = (view.getUint32(at + 8, true) >>> 5) & 2047;
  const directionX = cosTable[angle] / 32767;
  const directionY = sinTable[angle] / 32767;
  frame.set(background);
  lineTests = 0;
  cellsVisited = 0;

  for (let screenX = 0; screenX < WIDTH; screenX += 1) {
    const cameraX = (screenX * 2 + 1) / WIDTH - 1;
    const rayX = directionX - directionY * cameraX;
    const rayY = directionY + directionX * cameraX;
    let cellX = Math.floor((playerX - originX) / 128);
    let cellY = Math.floor((playerY - originY) / 128);
    const stepX = rayX < 0 ? -1 : 1;
    const stepY = rayY < 0 ? -1 : 1;
    const deltaX = rayX === 0 ? 1e30 : Math.abs(128 / rayX);
    const deltaY = rayY === 0 ? 1e30 : Math.abs(128 / rayY);
    let sideX = rayX < 0
      ? (playerX - (originX + cellX * 128)) / -rayX
      : (originX + (cellX + 1) * 128 - playerX) / rayX;
    let sideY = rayY < 0
      ? (playerY - (originY + cellY * 128)) / -rayY
      : (originY + (cellY + 1) * 128 - playerY) / rayY;
    let hitDistance = 4096;
    let hitLine = 0;

    for (let cellStep = 0; cellStep < 64; cellStep += 1) {
      if (cellX < 0 || cellY < 0
          || cellX >= blockColumns || cellY >= blockRows) break;
      cellsVisited += 1;
      const cell = cellY * blockColumns + cellX;
      const end = cellOffsets[cell + 1];
      for (let member = cellOffsets[cell]; member < end; member += 1) {
        const line = cellLines[member];
        const segmentX = lineX2[line] - lineX1[line];
        const segmentY = lineY2[line] - lineY1[line];
        const denominator = rayX * segmentY - rayY * segmentX;
        if (denominator > -0.000001 && denominator < 0.000001) continue;
        lineTests += 1;
        const offsetX = lineX1[line] - playerX;
        const offsetY = lineY1[line] - playerY;
        const distance = (offsetX * segmentY - offsetY * segmentX)
          / denominator;
        if (distance <= 0.01 || distance >= hitDistance) continue;
        const along = (offsetX * rayY - offsetY * rayX) / denominator;
        if (along >= 0 && along <= 1) {
          hitDistance = distance;
          hitLine = line;
        }
      }
      const boundary = sideX < sideY ? sideX : sideY;
      if (hitDistance <= boundary + 0.001) break;
      if (sideX < sideY) {
        sideX += deltaX;
        cellX += stepX;
      } else {
        sideY += deltaY;
        cellY += stepY;
      }
    }

    const corrected = Math.max(1, hitDistance);
    const wallHeight = Math.min(HEIGHT, Math.max(1, Math.floor(6400 / corrected)));
    const top = Math.max(0, (HEIGHT - wallHeight) >> 1);
    const bottom = Math.min(HEIGHT - 1, top + wallHeight - 1);
    const wallColor = 64 + (Math.imul(hitLine, 13) & 63);
    for (let y = top; y <= bottom; y += 1) {
      frame[y * WIDTH + screenX] = wallColor;
    }
  }
  return (
    Math.imul(frame[index % PIXELS], 65537)
    + frame[(index * 997) % PIXELS]
    + lineTests
    + cellsVisited
  ) | 0;
}

export function renderPose(index) {
  if (!Number.isInteger(index) || index < 0) return -1;
  return render(index);
}

export function renderBatch(start, count) {
  if (!Number.isInteger(start) || !Number.isInteger(count)
      || start < 0 || count < 1 || count > 1000) return -1;
  let checksum = 0;
  for (let index = 0; index < count; index += 1) {
    checksum = (checksum + render(start + index)) | 0;
  }
  return checksum;
}

export function frameChunk(offset, length) {
  if (!Number.isInteger(offset) || !Number.isInteger(length)
      || offset < 0 || length < 1 || length > 16000
      || frame === undefined || offset + length > frame.byteLength) {
    throw new Error('frame chunk outside retained framebuffer');
  }
  return frame.slice(offset, offset + length);
}

export function stats() {
  return `width=${WIDTH}|height=${HEIGHT}|poses=${poseCount}`
    + `|lineTests=${lineTests}|cellsVisited=${cellsVisited}`;
}

export function release() {
  pack = view = frame = background = undefined;
  lineX1 = lineY1 = lineX2 = lineY2 = undefined;
  cellOffsets = cellLines = sinTable = cosTable = undefined;
}
