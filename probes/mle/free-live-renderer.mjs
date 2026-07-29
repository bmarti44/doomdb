const WIDTH = 320;
const HEIGHT = 200;
const PIXELS = WIDTH * HEIGHT;
const MAGIC = 0x31465244;
let pack;
let view;
let frame;
let backgroundColumn;
let lineX1;
let lineY1;
let lineX2;
let lineY2;
let cellOffsets;
let cellLines;
let sinTable;
let cosTable;
let wallTextures;
let wallTextureExpectedBytes;
let wallTextureElements;
let litTextures;
let flatTextures;
let flatTextureExpectedBytes;
let flatTextureElements;
let litFlats;
let lightToBank;
let lightBankCount = 0;
let textureBase;
let textureWidth;
let textureHeight;
let lineTexture;
let lineXOffset;
let lineYOffset;
let lineLeftXOffset;
let lineLeftYOffset;
let lineRightSector;
let lineLeftSector;
let lineRightUpper;
let lineRightLower;
let lineRightMiddle;
let lineLeftUpper;
let lineLeftLower;
let lineLeftMiddle;
let lineFlags;
let lineRightSide;
let lineLeftSide;
let sectorFloor;
let sectorCeiling;
let sectorLight;
let sectorFloorAsset;
let sectorCeilingAsset;
let subsectorSector;
let colormaps;
let runtimeWallToAsset;
let runtimeFlatToAsset;
let sideCount;
let dynamicSideTop;
let dynamicSideBottom;
let dynamicSideMiddle;
let liveDynamicsActive = false;
let poseOffset;
let poseCount;
let poseRecordBytes;
let originX;
let originY;
let blockColumns;
let blockRows;
let lineTests = 0;
let cellsVisited = 0;
const CACHE_SIZE = 262144;
const WALL_HEIGHT_QUANTUM = 1;
const WALL_TOP_QUANTUM = 1;
const WALL_TEXTURE_X_QUANTUM = 1;
const PLANE_X_STEP = 1;
let cacheKeyA;
let cacheKeyB;
let cacheKeyC;
let cacheColumns;
let cacheHits = 0;
let cacheMisses = 0;
let cacheColdMisses = 0;
let cacheReplacements = 0;
let portalHits = 0;
let solidHits = 0;
let maxPortalDepth = 0;
let lineSeen;
let rayStamp = 0;
const localHitDistance = new Float64Array(32);
const localHitLine = new Uint16Array(32);
let segX1;
let segY1;
let segX2;
let segY2;
let segLine;
let segDirection;
let ssectorFirst;
let ssectorCount;
let nodeX;
let nodeY;
let nodeDx;
let nodeDy;
let nodeChild0;
let nodeChild1;
let nodeBbox0Top;
let nodeBbox0Bottom;
let nodeBbox0Left;
let nodeBbox0Right;
let nodeBbox1Top;
let nodeBbox1Bottom;
let nodeBbox1Left;
let nodeBbox1Right;
let nodeCount;
let bspStack;
let bspStackCheck;
let columnClipTop;
let columnClipBottom;
let columnPortalDepth;
let bspSegsVisited = 0;
let bspSubsectorsVisited = 0;
let bspBboxChecks = 0;
let bspBboxRejects = 0;
let emptyPortalSegsSkipped = 0;
let clipOnlyPortalColumns = 0;
let planeTop;
let planeBottom;
let planeStamp;
let planeMinX;
let planeMaxX;
let touchedPlanes;
let touchedPlaneCount = 0;
let planeSerial = 0;
let spanStart;
let planePixelWrites = 0;
let renderStartColumn = 0;
let renderEndColumn = WIDTH - 1;
let captureCommandOnly = false;
let wallCommandCount = 0;
let planeCommandCount = 0;

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

export function allocateWallTextures(length) {
  if (!Number.isInteger(length) || length < 1 || length > 10000000) {
    throw new Error(`invalid wall-texture pack length ${length}`);
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
    throw new Error('wall-texture chunk is outside allocation');
  }
  wallTextures.set(chunk, offset);
  return offset + chunk.byteLength;
}

export function finalizeWallTextures() {
  if (wallTextures === undefined
      || wallTextures.byteLength !== wallTextureExpectedBytes) {
    throw new Error(
      `wall-texture length mismatch ${wallTextures?.byteLength}`
      + `/${wallTextureExpectedBytes}`,
    );
  }
  lightToBank = new Int8Array(32);
  lightToBank.fill(-1);
  for (let sector = 0; sector < sectorLight.length; sector += 1) {
    const lightMap = Math.max(
      0, Math.min(31, Math.floor((255 - sectorLight[sector]) / 8)));
    if (lightToBank[lightMap] < 0) {
      lightToBank[lightMap] = lightBankCount;
      lightBankCount += 1;
    }
  }
  litTextures = new Uint8Array(wallTextureElements * lightBankCount);
  for (let lightMap = 0; lightMap < 32; lightMap += 1) {
    const bank = lightToBank[lightMap];
    if (bank < 0) continue;
    const target = bank * wallTextureElements;
    const map = lightMap * 256;
    for (let texel = 0; texel < wallTextureElements; texel += 1) {
      const encodedAt = texel * 2;
      const encoded = (wallTextures[encodedAt] << 8)
        | wallTextures[encodedAt + 1];
      const sample = encoded === 0 ? 0 : encoded - 1;
      litTextures[target + texel] = colormaps[map + sample];
    }
  }
  const loadedBytes = wallTextures.byteLength;
  wallTextures = undefined;
  return loadedBytes;
}

export function allocateFlatTextures(length) {
  if (!Number.isInteger(length) || length < 1
      || length !== flatTextureExpectedBytes) {
    throw new Error(`invalid flat-texture pack length ${length}`);
  }
  flatTextures = new Uint8Array(length);
  return length;
}

export function loadFlatTextureChunk(offset, chunk) {
  if (!(chunk instanceof Uint8Array)
      || !Number.isInteger(offset)
      || offset < 0
      || flatTextures === undefined
      || offset + chunk.byteLength > flatTextures.byteLength) {
    throw new Error('flat-texture chunk is outside allocation');
  }
  flatTextures.set(chunk, offset);
  return offset + chunk.byteLength;
}

export function finalizeFlatTextures() {
  if (flatTextures === undefined
      || flatTextures.byteLength !== flatTextureExpectedBytes
      || lightToBank === undefined) {
    throw new Error(
      `flat-texture length mismatch ${flatTextures?.byteLength}`
      + `/${flatTextureExpectedBytes}`);
  }
  litFlats = new Uint8Array(flatTextureElements * lightBankCount);
  for (let lightMap = 0; lightMap < 32; lightMap += 1) {
    const bank = lightToBank[lightMap];
    if (bank < 0) continue;
    const target = bank * flatTextureElements;
    const map = lightMap * 256;
    for (let texel = 0; texel < flatTextureElements; texel += 1) {
      const encodedAt = texel * 2;
      const encoded = (flatTextures[encodedAt] << 8)
        | flatTextures[encodedAt + 1];
      const sample = encoded === 0 ? 0 : encoded - 1;
      litFlats[target + texel] = colormaps[map + sample];
    }
  }
  const loadedBytes = flatTextures.byteLength;
  flatTextures = undefined;
  return loadedBytes;
}

function u32(offset) {
  return view.getUint32(offset, true);
}

export function finalizePack() {
  if (pack === undefined) throw new Error('live-render pack is absent');
  view = new DataView(pack.buffer, pack.byteOffset, pack.byteLength);
  if (u32(0) !== MAGIC || u32(4) !== 7 || u32(76) !== pack.byteLength) {
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
  const textureCount = u32(80);
  wallTextureElements = u32(84);
  wallTextureExpectedBytes = wallTextureElements * 2;
  textureBase = new Uint32Array(
    pack.buffer, pack.byteOffset + u32(88), textureCount);
  textureWidth = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(92), textureCount);
  textureHeight = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(96), textureCount);
  lineTexture = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(100), lineCount);
  lineXOffset = new Int16Array(
    pack.buffer, pack.byteOffset + u32(104), lineCount);
  lineYOffset = new Int16Array(
    pack.buffer, pack.byteOffset + u32(108), lineCount);
  lineRightSector = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(112), lineCount);
  lineLeftSector = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(116), lineCount);
  lineRightUpper = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(140), lineCount);
  lineRightLower = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(144), lineCount);
  lineRightMiddle = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(148), lineCount);
  lineLeftUpper = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(152), lineCount);
  lineLeftLower = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(156), lineCount);
  lineLeftMiddle = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(160), lineCount);
  lineLeftXOffset = new Int16Array(
    pack.buffer, pack.byteOffset + u32(164), lineCount);
  lineLeftYOffset = new Int16Array(
    pack.buffer, pack.byteOffset + u32(168), lineCount);
  lineFlags = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(172), lineCount);
  poseRecordBytes = u32(176);
  if (poseRecordBytes !== 32) {
    throw new Error(`live-render state record mismatch ${poseRecordBytes}`);
  }
  const segCount = u32(180);
  const subsectorCount = u32(184);
  nodeCount = u32(188);
  segX1 = new Int32Array(pack.buffer, pack.byteOffset + u32(192), segCount);
  segY1 = new Int32Array(pack.buffer, pack.byteOffset + u32(196), segCount);
  segX2 = new Int32Array(pack.buffer, pack.byteOffset + u32(200), segCount);
  segY2 = new Int32Array(pack.buffer, pack.byteOffset + u32(204), segCount);
  segLine = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(208), segCount);
  segDirection = new Uint8Array(
    pack.buffer, pack.byteOffset + u32(212), segCount);
  ssectorFirst = new Uint32Array(
    pack.buffer, pack.byteOffset + u32(216), subsectorCount);
  ssectorCount = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(220), subsectorCount);
  nodeX = new Int32Array(pack.buffer, pack.byteOffset + u32(224), nodeCount);
  nodeY = new Int32Array(pack.buffer, pack.byteOffset + u32(228), nodeCount);
  nodeDx = new Int32Array(pack.buffer, pack.byteOffset + u32(232), nodeCount);
  nodeDy = new Int32Array(pack.buffer, pack.byteOffset + u32(236), nodeCount);
  nodeChild0 = new Int32Array(
    pack.buffer, pack.byteOffset + u32(240), nodeCount);
  nodeChild1 = new Int32Array(
    pack.buffer, pack.byteOffset + u32(244), nodeCount);
  nodeBbox0Top = new Int32Array(
    pack.buffer, pack.byteOffset + u32(248), nodeCount);
  nodeBbox0Bottom = new Int32Array(
    pack.buffer, pack.byteOffset + u32(252), nodeCount);
  nodeBbox0Left = new Int32Array(
    pack.buffer, pack.byteOffset + u32(256), nodeCount);
  nodeBbox0Right = new Int32Array(
    pack.buffer, pack.byteOffset + u32(260), nodeCount);
  nodeBbox1Top = new Int32Array(
    pack.buffer, pack.byteOffset + u32(264), nodeCount);
  nodeBbox1Bottom = new Int32Array(
    pack.buffer, pack.byteOffset + u32(268), nodeCount);
  nodeBbox1Left = new Int32Array(
    pack.buffer, pack.byteOffset + u32(272), nodeCount);
  nodeBbox1Right = new Int32Array(
    pack.buffer, pack.byteOffset + u32(276), nodeCount);
  const sectorCount = u32(120);
  sectorFloor = new Int16Array(
    pack.buffer, pack.byteOffset + u32(124), sectorCount);
  sectorCeiling = new Int16Array(
    pack.buffer, pack.byteOffset + u32(128), sectorCount);
  sectorLight = new Uint8Array(
    pack.buffer, pack.byteOffset + u32(132), sectorCount);
  sectorFloorAsset = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(280), sectorCount);
  sectorCeilingAsset = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(284), sectorCount);
  const flatTextureCount = u32(288);
  flatTextureElements = u32(292);
  flatTextureExpectedBytes = flatTextureElements * 2;
  subsectorSector = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(296), subsectorCount);
  if (flatTextureCount < 1
      || flatTextureElements !== flatTextureCount * 4096) {
    throw new Error('flat-texture cardinality mismatch');
  }
  runtimeWallToAsset = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(464), u32(468));
  runtimeFlatToAsset = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(472), u32(476));
  lineRightSide = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(480), lineCount);
  lineLeftSide = new Uint16Array(
    pack.buffer, pack.byteOffset + u32(484), lineCount);
  sideCount = u32(488);
  if (u32(492) !== 208 || sideCount < 1
      || runtimeWallToAsset.length < 1
      || runtimeFlatToAsset.length < 1) {
    throw new Error('DVL2 mapping cardinality mismatch');
  }
  dynamicSideTop = new Uint16Array(sideCount);
  dynamicSideBottom = new Uint16Array(sideCount);
  dynamicSideMiddle = new Uint16Array(sideCount);
  colormaps = new Uint8Array(pack.buffer, pack.byteOffset + u32(136), 8192);
  frame = new Uint8Array(PIXELS);
  backgroundColumn = new Uint8Array(HEIGHT);
  for (let y = 0; y < HEIGHT; y += 1) {
    backgroundColumn[y] = y < HEIGHT / 2 ? 96 : 48;
  }
  cacheKeyA = new Int32Array(CACHE_SIZE);
  cacheKeyB = new Int32Array(CACHE_SIZE);
  cacheKeyC = new Int32Array(CACHE_SIZE);
  cacheColumns = new Array(CACHE_SIZE);
  lineSeen = new Int32Array(lineCount);
  bspStack = new Int32Array(nodeCount + subsectorCount + 8);
  bspStackCheck = new Int16Array(nodeCount + subsectorCount + 8);
  columnClipTop = new Int16Array(WIDTH);
  columnClipBottom = new Int16Array(WIDTH);
  columnPortalDepth = new Uint8Array(WIDTH);
  const planeCount = sectorCount * 2;
  planeTop = new Int16Array(planeCount * WIDTH);
  planeBottom = new Int16Array(planeCount * WIDTH);
  planeStamp = new Int32Array(planeCount);
  planeMinX = new Int16Array(planeCount);
  planeMaxX = new Int16Array(planeCount);
  touchedPlanes = new Uint16Array(planeCount);
  spanStart = new Int16Array(HEIGHT);
  return pack.byteLength;
}

function quantizedWallHeight(wallHeight) {
  return Math.max(
    WALL_HEIGHT_QUANTUM,
    Math.round(wallHeight / WALL_HEIGHT_QUANTUM) * WALL_HEIGHT_QUANTUM);
}

function cachedScaledWallColumn(texture, textureX, wallHeight, lightMap) {
  textureX %= textureWidth[texture];
  if (textureX < 0) textureX += textureWidth[texture];
  textureX -= textureX % WALL_TEXTURE_X_QUANTUM;
  wallHeight = quantizedWallHeight(wallHeight);
  const keyA = (texture | (textureX << 16)) | 0;
  const keyB = ((Math.min(65535, wallHeight) & 0xffff)
    | (lightMap << 16)) | 0;
  const keyC = 0;
  let hash = keyA ^ Math.imul(keyB, 40503) ^ Math.imul(keyC, 7919);
  hash ^= hash >>> 13;
  hash = Math.imul(hash, -1640531527);
  hash ^= hash >>> 16;
  const slot = (hash >>> 0) & (CACHE_SIZE - 1);
  if (cacheColumns[slot] !== undefined
      && cacheKeyA[slot] === keyA
      && cacheKeyB[slot] === keyB
      && cacheKeyC[slot] === keyC) {
    cacheHits += 1;
    return cacheColumns[slot];
  }
  cacheMisses += 1;
  let column = cacheColumns[slot];
  const length = wallHeight;
  if (column === undefined || column.length !== length) {
    cacheColdMisses += 1;
    column = new Uint8Array(length);
  } else {
    cacheReplacements += 1;
  }
  const width = textureWidth[texture];
  const height = textureHeight[texture];
  const base = textureBase[texture];
  let textureY = 0;
  const textureStep = 128 / length;
  for (let output = 0; output < length; output += 1) {
    let sourceY = Math.floor(textureY) % height;
    if (sourceY < 0) sourceY += height;
    const bank = lightToBank[lightMap];
    column[output] = litTextures[
      bank * wallTextureElements + base + sourceY * width + textureX
    ];
    textureY += textureStep;
  }
  cacheKeyA[slot] = keyA;
  cacheKeyB[slot] = keyB;
  cacheKeyC[slot] = keyC;
  cacheColumns[slot] = column;
  return column;
}

function drawWallSegment(
    columnBase, texture, textureX, wallHeight, projectedTop,
    projectedBottom, clipTop, clipBottom, lightMap, verticalOffset) {
  if (texture === 0xffff || projectedTop > clipBottom
      || projectedBottom < clipTop || projectedTop > projectedBottom) {
    return;
  }
  const drawTop = Math.max(clipTop, projectedTop, 0);
  const drawBottom = Math.min(clipBottom, projectedBottom, HEIGHT - 1);
  if (drawTop > drawBottom) return;
  if (captureCommandOnly) {
    wallCommandCount += 1;
    return;
  }
  const scaledHeight = quantizedWallHeight(wallHeight);
  const scaledTop = Math.round(projectedTop / WALL_TOP_QUANTUM)
    * WALL_TOP_QUANTUM;
  const column = cachedScaledWallColumn(
    texture, textureX, scaledHeight, lightMap);
  let normalizedOffset = verticalOffset % textureHeight[texture];
  if (normalizedOffset < 0) normalizedOffset += textureHeight[texture];
  let source = Math.floor(normalizedOffset * scaledHeight / 128)
    + drawTop - scaledTop;
  source %= scaledHeight;
  if (source < 0) source += scaledHeight;
  let destination = columnBase + drawTop;
  let remaining = drawBottom - drawTop + 1;
  while (remaining > 0) {
    const copied = Math.min(remaining, scaledHeight - source);
    frame.set(column.subarray(source, source + copied), destination);
    destination += copied;
    remaining -= copied;
    source = 0;
  }
}

function drawPlaneBackground(
    sector, playerX, playerY, viewZ, directionX, directionY) {
  const lightMap = Math.max(
    0, Math.min(31, Math.floor((255 - sectorLight[sector]) / 8)));
  const lightBank = lightToBank[lightMap] * flatTextureElements;
  const floorBase = lightBank + sectorFloorAsset[sector] * 4096;
  const ceilingAsset = sectorCeilingAsset[sector];
  const ceilingBase = ceilingAsset === 0xffff
    ? -1 : lightBank + ceilingAsset * 4096;
  for (let y = 0; y < HEIGHT; y += 1) {
    if (y === HEIGHT / 2) {
      for (let x = 0; x < WIDTH; x += 1) {
        frame[x * HEIGHT + y] = backgroundColumn[y];
      }
      continue;
    }
    const ceiling = y < HEIGHT / 2;
    if (ceiling && ceilingBase < 0) {
      for (let x = 0; x < WIDTH; x += 1) {
        frame[x * HEIGHT + y] = backgroundColumn[y];
      }
      continue;
    }
    const planeHeight = ceiling
      ? sectorCeiling[sector] - viewZ : viewZ - sectorFloor[sector];
    const distance = planeHeight * (WIDTH / 2)
      / Math.abs(y + 0.5 - HEIGHT / 2);
    const firstCamera = 0.5 / (WIDTH / 2) - 1;
    const rayX = directionX - directionY * firstCamera;
    const rayY = directionY + directionX * firstCamera;
    let worldX = Math.floor((playerX + rayX * distance) * 65536);
    let worldY = Math.floor((playerY + rayY * distance) * 65536);
    const stepX = Math.floor((-directionY / (WIDTH / 2) * distance) * 65536);
    const stepY = Math.floor((directionX / (WIDTH / 2) * distance) * 65536);
    const assetBase = (ceiling ? ceilingBase : floorBase);
    for (let x = 0; x < WIDTH; x += 1) {
      const source = ((worldY >> 10) & 4032) + ((worldX >> 16) & 63);
      frame[x * HEIGHT + y] = litFlats[assetBase + source];
      worldX += stepX;
      worldY += stepY;
    }
  }
}

function renderRayReference(index, snapshot) {
  if (view === undefined || frame === undefined) {
    throw new Error('live-render pack has not been finalized');
  }
  if (litTextures === undefined) {
    throw new Error('wall textures have not been finalized');
  }
  index %= poseCount;
  const at = poseOffset + index * poseRecordBytes;
  const snapshotView = snapshot === undefined ? undefined : new DataView(
    snapshot.buffer, snapshot.byteOffset, snapshot.byteLength);
  const playerX = snapshotView === undefined
    ? view.getInt32(at, true) / 65536
    : snapshotView.getInt32(36, true) / 65536;
  const playerY = snapshotView === undefined
    ? view.getInt32(at + 4, true) / 65536
    : snapshotView.getInt32(40, true) / 65536;
  const angle = snapshotView === undefined
    ? (view.getUint32(at + 8, true) >>> 5) & 2047
    : (snapshotView.getUint32(48, true) >>> 5) & 2047;
  const viewZ = snapshotView === undefined
    ? view.getInt32(at + 12, true) / 65536
    : snapshotView.getInt32(52, true) / 65536;
  const directionX = cosTable[angle] / 32767;
  const directionY = sinTable[angle] / 32767;
  lineTests = 0;
  cellsVisited = 0;
  cacheHits = 0;
  cacheMisses = 0;
  cacheColdMisses = 0;
  cacheReplacements = 0;
  portalHits = 0;
  solidHits = 0;
  maxPortalDepth = 0;
  if (litFlats !== undefined) {
    drawPlaneBackground(
      pointSector(playerX, playerY),
      playerX, playerY, viewZ, directionX, directionY);
  }

  for (let screenX = 0; screenX < WIDTH; screenX += 1) {
    const columnBase = screenX * HEIGHT;
    if (litFlats === undefined) frame.set(backgroundColumn, columnBase);
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
    let clipTop = 0;
    let clipBottom = HEIGHT - 1;
    let portalDepth = 0;
    let stopped = false;
    rayStamp += 1;
    if (rayStamp === 2147483647) {
      lineSeen.fill(0);
      rayStamp = 1;
    }

    for (let cellStep = 0; cellStep < 64; cellStep += 1) {
      if (cellX < 0 || cellY < 0
          || cellX >= blockColumns || cellY >= blockRows) break;
      cellsVisited += 1;
      const cell = cellY * blockColumns + cellX;
      const boundary = sideX < sideY ? sideX : sideY;
      const end = cellOffsets[cell + 1];
      let hitCount = 0;
      for (let member = cellOffsets[cell]; member < end; member += 1) {
        const line = cellLines[member];
        if (lineSeen[line] === rayStamp) continue;
        const segmentX = lineX2[line] - lineX1[line];
        const segmentY = lineY2[line] - lineY1[line];
        const denominator = rayX * segmentY - rayY * segmentX;
        if (denominator > -0.000001 && denominator < 0.000001) continue;
        lineTests += 1;
        const offsetX = lineX1[line] - playerX;
        const offsetY = lineY1[line] - playerY;
        const distance = (offsetX * segmentY - offsetY * segmentX)
          / denominator;
        if (distance <= 0.01 || distance > boundary + 0.001) continue;
        const along = (offsetX * rayY - offsetY * rayX) / denominator;
        if (along >= 0 && along <= 1) {
          lineSeen[line] = rayStamp;
          if (hitCount < localHitLine.length) {
            let position = hitCount;
            while (position > 0
                && localHitDistance[position - 1] > distance) {
              localHitDistance[position] = localHitDistance[position - 1];
              localHitLine[position] = localHitLine[position - 1];
              position -= 1;
            }
            localHitDistance[position] = distance;
            localHitLine[position] = line;
            hitCount += 1;
          }
        }
      }
      for (let hit = 0; hit < hitCount && !stopped; hit += 1) {
        const hitDistance = localHitDistance[hit];
        const hitLine = localHitLine[hit];
        const segmentX = lineX2[hitLine] - lineX1[hitLine];
        const segmentY = lineY2[hitLine] - lineY1[hitLine];
        const playerSide = (playerX - lineX1[hitLine]) * segmentY
          - (playerY - lineY1[hitLine]) * segmentX;
        const fromRight = playerSide >= 0;
        const nearSector = fromRight
          ? lineRightSector[hitLine] : lineLeftSector[hitLine];
        const farSector = fromRight
          ? lineLeftSector[hitLine] : lineRightSector[hitLine];
        if (nearSector === 0xffff) continue;
        const xOffset = fromRight
          ? lineXOffset[hitLine] : lineLeftXOffset[hitLine];
        const yOffset = fromRight
          ? lineYOffset[hitLine] : lineLeftYOffset[hitLine];
        const sideIndex = fromRight
          ? lineRightSide[hitLine] : lineLeftSide[hitLine];
        const upperTexture = liveDynamicsActive && sideIndex !== 0xffff
          ? dynamicSideTop[sideIndex]
          : (fromRight ? lineRightUpper[hitLine] : lineLeftUpper[hitLine]);
        const lowerTexture = liveDynamicsActive && sideIndex !== 0xffff
          ? dynamicSideBottom[sideIndex]
          : (fromRight ? lineRightLower[hitLine] : lineLeftLower[hitLine]);
        let middleTexture = liveDynamicsActive && sideIndex !== 0xffff
          ? dynamicSideMiddle[sideIndex]
          : (fromRight ? lineRightMiddle[hitLine] : lineLeftMiddle[hitLine]);
        if (middleTexture === 0xffff && farSector === 0xffff) {
          middleTexture = lineTexture[hitLine];
        }
        const corrected = Math.max(0.25, hitDistance);
        const wallHeight = Math.min(
          65535, Math.max(1, Math.floor(128 * 160 / corrected)));
        const hitX = playerX + rayX * hitDistance;
        const hitY = playerY + rayY * hitDistance;
        const along = Math.abs(segmentX) >= Math.abs(segmentY)
          ? Math.abs(hitX - lineX1[hitLine])
          : Math.abs(hitY - lineY1[hitLine]);
        const textureX = Math.floor(along) + xOffset;
        const lightMap = Math.max(
          0, Math.min(31, Math.floor((255 - sectorLight[nearSector]) / 8)));
        const nearCeiling = sectorCeiling[nearSector];
        const nearFloor = sectorFloor[nearSector];
        const nearTop = Math.floor(
          HEIGHT / 2 - (nearCeiling - viewZ) * wallHeight / 128);
        const nearBottom = Math.ceil(
          HEIGHT / 2 - (nearFloor - viewZ) * wallHeight / 128) - 1;

        if (farSector === 0xffff) {
          solidHits += 1;
          drawWallSegment(
            columnBase, middleTexture, textureX, wallHeight,
            nearTop, nearBottom, clipTop, clipBottom, lightMap, yOffset,
          );
          stopped = true;
          break;
        }

        portalHits += 1;
        portalDepth += 1;
        const farCeiling = sectorCeiling[farSector];
        const farFloor = sectorFloor[farSector];
        const openingCeiling = Math.min(nearCeiling, farCeiling);
        const openingFloor = Math.max(nearFloor, farFloor);
        const openingTop = Math.floor(
          HEIGHT / 2 - (openingCeiling - viewZ) * wallHeight / 128);
        const openingBottom = Math.ceil(
          HEIGHT / 2 - (openingFloor - viewZ) * wallHeight / 128) - 1;
        if (farCeiling < nearCeiling) {
          drawWallSegment(
            columnBase, upperTexture, textureX, wallHeight,
            nearTop, openingTop - 1, clipTop, clipBottom, lightMap, yOffset,
          );
        }
        if (farFloor > nearFloor) {
          drawWallSegment(
            columnBase, lowerTexture, textureX, wallHeight,
            openingBottom + 1, nearBottom, clipTop, clipBottom,
            lightMap, yOffset,
          );
        }
        clipTop = Math.max(clipTop, openingTop);
        clipBottom = Math.min(clipBottom, openingBottom);
        if (clipTop > clipBottom || portalDepth >= 24) stopped = true;
      }
      if (stopped) break;
      if (sideX < sideY) {
        sideX += deltaX;
        cellX += stepX;
      } else {
        sideY += deltaY;
        cellY += stepY;
      }
    }
    if (portalDepth > maxPortalDepth) maxPortalDepth = portalDepth;
  }
  return (
    Math.imul(frame[index % PIXELS], 65537)
    + frame[(index * 997) % PIXELS]
    + lineTests
    + cellsVisited
  ) | 0;
}

function renderBspWallColumn(
    screenX, line, fromRight, wallHeight, numerator, denominator,
    playerX, playerY, viewZ, directionX, directionY) {
  const clipTop = columnClipTop[screenX];
  const clipBottom = columnClipBottom[screenX];
  if (clipTop > clipBottom) return;
  const nearSector = fromRight
    ? lineRightSector[line] : lineLeftSector[line];
  const farSector = fromRight
    ? lineLeftSector[line] : lineRightSector[line];
  if (nearSector === 0xffff) return;
  const nearCeiling = sectorCeiling[nearSector];
  const nearFloor = sectorFloor[nearSector];
  const nearTop = Math.floor(
    HEIGHT / 2 - (nearCeiling - viewZ) * wallHeight / 128);
  const nearBottom = Math.ceil(
    HEIGHT / 2 - (nearFloor - viewZ) * wallHeight / 128) - 1;
  const columnBase = screenX * HEIGHT;
  const sideIndex = fromRight ? lineRightSide[line] : lineLeftSide[line];

  if (farSector === 0xffff) {
    let middleTexture = liveDynamicsActive && sideIndex !== 0xffff
      ? dynamicSideMiddle[sideIndex]
      : (fromRight ? lineRightMiddle[line] : lineLeftMiddle[line]);
    if (middleTexture === 0xffff) middleTexture = lineTexture[line];
    const segmentX = lineX2[line] - lineX1[line];
    const segmentY = lineY2[line] - lineY1[line];
    const cameraX = (screenX * 2 + 1) / WIDTH - 1;
    const rayX = directionX - directionY * cameraX;
    const rayY = directionY + directionX * cameraX;
    const distance = numerator / denominator;
    const hitX = playerX + rayX * distance;
    const hitY = playerY + rayY * distance;
    const along = Math.abs(segmentX) >= Math.abs(segmentY)
      ? Math.abs(hitX - lineX1[line])
      : Math.abs(hitY - lineY1[line]);
    const textureX = Math.floor(along)
      + (fromRight ? lineXOffset[line] : lineLeftXOffset[line]);
    const lightMap = Math.max(
      0, Math.min(31, Math.floor((255 - sectorLight[nearSector]) / 8)));
    solidHits += 1;
    drawWallSegment(
      columnBase, middleTexture, textureX, wallHeight,
      nearTop, nearBottom, clipTop, clipBottom, lightMap,
      fromRight ? lineYOffset[line] : lineLeftYOffset[line],
    );
    columnClipTop[screenX] = 1;
    columnClipBottom[screenX] = 0;
    return;
  }

  portalHits += 1;
  const depth = columnPortalDepth[screenX] + 1;
  columnPortalDepth[screenX] = depth;
  if (depth > maxPortalDepth) maxPortalDepth = depth;
  const farCeiling = sectorCeiling[farSector];
  const farFloor = sectorFloor[farSector];
  const openingCeiling = Math.min(nearCeiling, farCeiling);
  const openingFloor = Math.max(nearFloor, farFloor);
  const openingTop = Math.floor(
    HEIGHT / 2 - (openingCeiling - viewZ) * wallHeight / 128);
  const openingBottom = Math.ceil(
    HEIGHT / 2 - (openingFloor - viewZ) * wallHeight / 128) - 1;
  const upperTexture = liveDynamicsActive && sideIndex !== 0xffff
    ? dynamicSideTop[sideIndex]
    : (fromRight ? lineRightUpper[line] : lineLeftUpper[line]);
  const lowerTexture = liveDynamicsActive && sideIndex !== 0xffff
    ? dynamicSideBottom[sideIndex]
    : (fromRight ? lineRightLower[line] : lineLeftLower[line]);
  const drawUpper = farCeiling < nearCeiling
    && upperTexture !== 0xffff
    && nearTop <= clipBottom && openingTop - 1 >= clipTop;
  const drawLower = farFloor > nearFloor
    && lowerTexture !== 0xffff
    && openingBottom + 1 <= clipBottom && nearBottom >= clipTop;
  if (drawUpper || drawLower) {
    const segmentX = lineX2[line] - lineX1[line];
    const segmentY = lineY2[line] - lineY1[line];
    const cameraX = (screenX * 2 + 1) / WIDTH - 1;
    const rayX = directionX - directionY * cameraX;
    const rayY = directionY + directionX * cameraX;
    const distance = numerator / denominator;
    const hitX = playerX + rayX * distance;
    const hitY = playerY + rayY * distance;
    const along = Math.abs(segmentX) >= Math.abs(segmentY)
      ? Math.abs(hitX - lineX1[line])
      : Math.abs(hitY - lineY1[line]);
    const textureX = Math.floor(along)
      + (fromRight ? lineXOffset[line] : lineLeftXOffset[line]);
    const lightMap = Math.max(
      0, Math.min(31, Math.floor((255 - sectorLight[nearSector]) / 8)));
    const yOffset = fromRight ? lineYOffset[line] : lineLeftYOffset[line];
    if (drawUpper) {
      drawWallSegment(
        columnBase, upperTexture, textureX, wallHeight,
        nearTop, openingTop - 1, clipTop, clipBottom, lightMap, yOffset,
      );
    }
    if (drawLower) {
      drawWallSegment(
        columnBase, lowerTexture, textureX, wallHeight,
        openingBottom + 1, nearBottom, clipTop, clipBottom, lightMap, yOffset,
      );
    }
  }
  columnClipTop[screenX] = Math.max(clipTop, openingTop);
  columnClipBottom[screenX] = Math.min(clipBottom, openingBottom);
}

function bspBboxMayBeVisible(
    check, playerX, playerY, directionX, directionY) {
  bspBboxChecks += 1;
  const node = check >> 1;
  const side = check & 1;
  const top = side === 0 ? nodeBbox0Top[node] : nodeBbox1Top[node];
  const bottom = side === 0
    ? nodeBbox0Bottom[node] : nodeBbox1Bottom[node];
  const left = side === 0 ? nodeBbox0Left[node] : nodeBbox1Left[node];
  const right = side === 0 ? nodeBbox0Right[node] : nodeBbox1Right[node];
  if (playerX >= left && playerX <= right
      && playerY >= bottom && playerY <= top) return true;

  let minimumDepth = 1e30;
  let maximumDepth = -1e30;
  let minimumScreen = 1e30;
  let maximumScreen = -1e30;
  for (let corner = 0; corner < 4; corner += 1) {
    const x = (corner & 1) === 0 ? left : right;
    const y = (corner & 2) === 0 ? bottom : top;
    const relativeX = x - playerX;
    const relativeY = y - playerY;
    const depth = relativeX * directionX + relativeY * directionY;
    if (depth < minimumDepth) minimumDepth = depth;
    if (depth > maximumDepth) maximumDepth = depth;
    if (depth > 0.01) {
      const sideways = -relativeX * directionY + relativeY * directionX;
      const screen = WIDTH / 2 + sideways / depth * WIDTH / 2;
      if (screen < minimumScreen) minimumScreen = screen;
      if (screen > maximumScreen) maximumScreen = screen;
    }
  }
  if (maximumDepth <= 0.01) {
    bspBboxRejects += 1;
    return false;
  }
  if (minimumDepth <= 0.01) return true;
  const start = Math.max(renderStartColumn, Math.floor(minimumScreen));
  const end = Math.min(renderEndColumn, Math.ceil(maximumScreen));
  if (start > end) {
    bspBboxRejects += 1;
    return false;
  }
  for (let screenX = start; screenX <= end; screenX += 1) {
    if (columnClipTop[screenX] <= columnClipBottom[screenX]) return true;
  }
  bspBboxRejects += 1;
  return false;
}

function pointSector(playerX, playerY) {
  let child = nodeCount - 1;
  while (child >= 0) {
    const side = (
      (playerX - nodeX[child]) * nodeDy[child]
      - (playerY - nodeY[child]) * nodeDx[child]
    ) >= 0 ? 0 : 1;
    child = side === 0 ? nodeChild0[child] : nodeChild1[child];
  }
  const subsector = child & 0x7fffffff;
  if (subsector >= subsectorSector.length) {
    throw new Error('player subsector outside map');
  }
  return subsectorSector[subsector];
}

function startPlaneFrame() {
  planeSerial = (planeSerial + 1) | 0;
  if (planeSerial === 0) {
    planeStamp.fill(0);
    planeSerial = 1;
  }
  touchedPlaneCount = 0;
  planePixelWrites = 0;
}

function recordPlaneRange(sector, ceiling, x, top, bottom) {
  top = Math.max(0, top);
  bottom = Math.min(HEIGHT - 1, bottom);
  if (top > bottom || x < 0 || x >= WIDTH) return;
  const plane = sector * 2 + (ceiling ? 0 : 1);
  const base = plane * WIDTH;
  if (planeStamp[plane] !== planeSerial) {
    planeStamp[plane] = planeSerial;
    touchedPlanes[touchedPlaneCount++] = plane;
    planeMinX[plane] = x;
    planeMaxX[plane] = x;
    planeTop.fill(HEIGHT, base, base + WIDTH);
    planeBottom.fill(-1, base, base + WIDTH);
  } else {
    if (x < planeMinX[plane]) planeMinX[plane] = x;
    if (x > planeMaxX[plane]) planeMaxX[plane] = x;
  }
  const at = base + x;
  if (top < planeTop[at]) planeTop[at] = top;
  if (bottom > planeBottom[at]) planeBottom[at] = bottom;
}

function drawPlaneSpan(
    plane, y, x1, x2, playerX, playerY, viewZ,
    directionX, directionY) {
  if (x1 > x2 || y === HEIGHT / 2) return;
  if (captureCommandOnly) {
    planeCommandCount += 1;
    return;
  }
  const sector = plane >> 1;
  const ceiling = (plane & 1) === 0;
  const asset = ceiling
    ? sectorCeilingAsset[sector] : sectorFloorAsset[sector];
  if (ceiling && asset === 0xffff) {
    const pixel = backgroundColumn[y];
    for (let x = x1; x <= x2; x += 1) frame[x * HEIGHT + y] = pixel;
    planePixelWrites += x2 - x1 + 1;
    return;
  }
  const planeHeight = ceiling
    ? sectorCeiling[sector] - viewZ : viewZ - sectorFloor[sector];
  const distance = planeHeight * (WIDTH / 2)
    / Math.abs(y + 0.5 - HEIGHT / 2);
  const cameraX = (x1 * 2 + 1) / WIDTH - 1;
  const rayX = directionX - directionY * cameraX;
  const rayY = directionY + directionX * cameraX;
  let worldX = Math.floor((playerX + rayX * distance) * 65536);
  let worldY = Math.floor((playerY + rayY * distance) * 65536);
  const stepX = Math.floor((-directionY / (WIDTH / 2) * distance) * 65536);
  const stepY = Math.floor((directionX / (WIDTH / 2) * distance) * 65536);
  const lightMap = Math.max(
    0, Math.min(31, Math.floor((255 - sectorLight[sector]) / 8)));
  const bank = lightToBank[lightMap] * flatTextureElements;
  const assetBase = bank + asset * 4096;
  for (let x = x1; x <= x2; x += PLANE_X_STEP) {
    const source = ((worldY >> 10) & 4032) + ((worldX >> 16) & 63);
    const pixel = litFlats[assetBase + source];
    frame[x * HEIGHT + y] = pixel;
    if (x + 1 <= x2) frame[(x + 1) * HEIGHT + y] = pixel;
    worldX += stepX * PLANE_X_STEP;
    worldY += stepY * PLANE_X_STEP;
  }
  planePixelWrites += x2 - x1 + 1;
}

function drawRecordedPlanes(
    playerX, playerY, viewZ, directionX, directionY) {
  for (let touched = 0; touched < touchedPlaneCount; touched += 1) {
    const plane = touchedPlanes[touched];
    const base = plane * WIDTH;
    const minimum = planeMinX[plane];
    const maximum = planeMaxX[plane];
    let previousTop = HEIGHT;
    let previousBottom = -1;
    for (let x = minimum; x <= maximum + 1; x += 1) {
      let top = x <= maximum ? planeTop[base + x] : HEIGHT;
      let bottom = x <= maximum ? planeBottom[base + x] : -1;
      while (previousTop < top && previousTop <= previousBottom) {
        drawPlaneSpan(
          plane, previousTop, spanStart[previousTop], x - 1,
          playerX, playerY, viewZ, directionX, directionY);
        previousTop += 1;
      }
      while (previousBottom > bottom && previousBottom >= previousTop) {
        drawPlaneSpan(
          plane, previousBottom, spanStart[previousBottom], x - 1,
          playerX, playerY, viewZ, directionX, directionY);
        previousBottom -= 1;
      }
      while (top < previousTop && top <= bottom) spanStart[top++] = x;
      while (bottom > previousBottom && bottom >= top) spanStart[bottom--] = x;
      previousTop = x <= maximum ? planeTop[base + x] : HEIGHT;
      previousBottom = x <= maximum ? planeBottom[base + x] : -1;
    }
  }
}

function render(index, snapshot, planes = true) {
  if (view === undefined || frame === undefined || litTextures === undefined) {
    throw new Error('BSP live renderer is not finalized');
  }
  index %= poseCount;
  const at = poseOffset + index * poseRecordBytes;
  const snapshotView = snapshot === undefined ? undefined : new DataView(
    snapshot.buffer, snapshot.byteOffset, snapshot.byteLength);
  const playerX = snapshotView === undefined
    ? view.getInt32(at, true) / 65536
    : snapshotView.getInt32(36, true) / 65536;
  const playerY = snapshotView === undefined
    ? view.getInt32(at + 4, true) / 65536
    : snapshotView.getInt32(40, true) / 65536;
  const angle = snapshotView === undefined
    ? (view.getUint32(at + 8, true) >>> 5) & 2047
    : (snapshotView.getUint32(48, true) >>> 5) & 2047;
  const viewZ = snapshotView === undefined
    ? view.getInt32(at + 12, true) / 65536
    : snapshotView.getInt32(52, true) / 65536;
  const directionX = cosTable[angle] / 32767;
  const directionY = sinTable[angle] / 32767;
  lineTests = 0;
  cellsVisited = 0;
  cacheHits = 0;
  cacheMisses = 0;
  cacheColdMisses = 0;
  cacheReplacements = 0;
  portalHits = 0;
  solidHits = 0;
  maxPortalDepth = 0;
  bspSegsVisited = 0;
  bspSubsectorsVisited = 0;
  bspBboxChecks = 0;
  bspBboxRejects = 0;
  emptyPortalSegsSkipped = 0;
  clipOnlyPortalColumns = 0;
  columnClipTop.fill(1);
  columnClipBottom.fill(0);
  columnClipTop.fill(0, renderStartColumn, renderEndColumn + 1);
  columnClipBottom.fill(
    HEIGHT - 1, renderStartColumn, renderEndColumn + 1);
  columnPortalDepth.fill(0);
  if (planes && litFlats !== undefined) startPlaneFrame();
  for (let screenX = renderStartColumn;
    screenX <= renderEndColumn; screenX += 1) {
    frame.set(backgroundColumn, screenX * HEIGHT);
  }

  let stackSize = 1;
  bspStack[0] = nodeCount - 1;
  bspStackCheck[0] = -1;
  let openColumns = renderEndColumn - renderStartColumn + 1;
  while (stackSize > 0 && openColumns > 0) {
    const item = bspStack[--stackSize];
    const pendingCheck = bspStackCheck[stackSize];
    if (pendingCheck >= 0 && !bspBboxMayBeVisible(
      pendingCheck, playerX, playerY, directionX, directionY,
    )) continue;
    if (item >= 0) {
      const side = (
        (playerX - nodeX[item]) * nodeDy[item]
        - (playerY - nodeY[item]) * nodeDx[item]
      ) >= 0 ? 0 : 1;
      const front = side === 0 ? nodeChild0[item] : nodeChild1[item];
      const back = side === 0 ? nodeChild1[item] : nodeChild0[item];
      bspStack[stackSize++] = back;
      bspStackCheck[stackSize - 1] = item * 2 + (side ^ 1);
      bspStack[stackSize++] = front;
      bspStackCheck[stackSize - 1] = -1;
      continue;
    }

    const subsector = item & 0x7fffffff;
    bspSubsectorsVisited += 1;
    const first = ssectorFirst[subsector];
    const end = first + ssectorCount[subsector];
    for (let seg = first; seg < end; seg += 1) {
      bspSegsVisited += 1;
      const line = segLine[seg];
      const fromRight = segDirection[seg] === 0;
      const playerSide = (
        (playerX - lineX1[line]) * (lineY2[line] - lineY1[line])
        - (playerY - lineY1[line]) * (lineX2[line] - lineX1[line])
      ) >= 0;
      if (playerSide !== fromRight) continue;
      const nearSector = fromRight
        ? lineRightSector[line] : lineLeftSector[line];
      const farSector = fromRight
        ? lineLeftSector[line] : lineRightSector[line];
      const sideIndex = fromRight ? lineRightSide[line] : lineLeftSide[line];
      const middleTexture = liveDynamicsActive && sideIndex !== 0xffff
        ? dynamicSideMiddle[sideIndex]
        : (fromRight ? lineRightMiddle[line] : lineLeftMiddle[line]);
      if (farSector !== 0xffff
          && middleTexture === 0xffff
          && sectorFloor[nearSector] === sectorFloor[farSector]
          && sectorCeiling[nearSector] === sectorCeiling[farSector]) {
        emptyPortalSegsSkipped += 1;
        continue;
      }
      const upperTexture = liveDynamicsActive && sideIndex !== 0xffff
        ? dynamicSideTop[sideIndex]
        : (fromRight ? lineRightUpper[line] : lineLeftUpper[line]);
      const lowerTexture = liveDynamicsActive && sideIndex !== 0xffff
        ? dynamicSideBottom[sideIndex]
        : (fromRight ? lineRightLower[line] : lineLeftLower[line]);
      const clipOnlyPortal = farSector !== 0xffff
        && !(sectorCeiling[farSector] < sectorCeiling[nearSector]
          && upperTexture !== 0xffff)
        && !(sectorFloor[farSector] > sectorFloor[nearSector]
          && lowerTexture !== 0xffff);
      const clipOpeningCeiling = clipOnlyPortal
        ? Math.min(sectorCeiling[nearSector], sectorCeiling[farSector]) : 0;
      const clipOpeningFloor = clipOnlyPortal
        ? Math.max(sectorFloor[nearSector], sectorFloor[farSector]) : 0;

      let ax = segX1[seg] - playerX;
      let ay = segY1[seg] - playerY;
      let bx = segX2[seg] - playerX;
      let by = segY2[seg] - playerY;
      let ad = ax * directionX + ay * directionY;
      let bd = bx * directionX + by * directionY;
      let as = -ax * directionY + ay * directionX;
      let bs = -bx * directionY + by * directionX;
      if (ad <= 0.01 && bd <= 0.01) continue;
      if (ad <= 0.01) {
        const fraction = (0.01 - ad) / (bd - ad);
        as += (bs - as) * fraction;
        ad = 0.01;
      } else if (bd <= 0.01) {
        const fraction = (0.01 - bd) / (ad - bd);
        bs += (as - bs) * fraction;
        bd = 0.01;
      }
      const projectedA = WIDTH / 2 + as / ad * WIDTH / 2;
      const projectedB = WIDTH / 2 + bs / bd * WIDTH / 2;
      let startX = Math.max(
        renderStartColumn,
        Math.ceil(Math.min(projectedA, projectedB) - 0.5));
      const endX = Math.min(
        renderEndColumn,
        Math.floor(Math.max(projectedA, projectedB) - 0.5));
      if (startX > endX) continue;

      const segmentX = segX2[seg] - segX1[seg];
      const segmentY = segY2[seg] - segY1[seg];
      const offsetX = segX1[seg] - playerX;
      const offsetY = segY1[seg] - playerY;
      const numerator = offsetX * segmentY - offsetY * segmentX;
      const denominatorBase = directionX * segmentY - directionY * segmentX;
      const denominatorSlope = -directionY * segmentY
        - directionX * segmentX;
      let cameraX = (startX * 2 + 1) / WIDTH - 1;
      let denominator = denominatorBase + denominatorSlope * cameraX;
      const denominatorStep = denominatorSlope * 2 / WIDTH;
      for (; startX <= endX; startX += 1) {
        const currentDenominator = denominator;
        denominator += denominatorStep;
        if (columnClipTop[startX] > columnClipBottom[startX]) continue;
        if (currentDenominator > -0.000001
            && currentDenominator < 0.000001) continue;
        lineTests += 1;
        const height = Math.floor(20480 * currentDenominator / numerator);
        if (height < 1) continue;
        const wallHeight = Math.min(65535, height);
        if (clipOnlyPortal) {
          const nearTop = Math.floor(
            HEIGHT / 2
              - (sectorCeiling[nearSector] - viewZ) * wallHeight / 128);
          const nearBottom = Math.ceil(
            HEIGHT / 2
              - (sectorFloor[nearSector] - viewZ) * wallHeight / 128) - 1;
          if (planes && litFlats !== undefined) {
            recordPlaneRange(
              nearSector, true, startX, columnClipTop[startX],
              Math.min(columnClipBottom[startX], nearTop - 1));
            recordPlaneRange(
              nearSector, false, startX,
              Math.max(columnClipTop[startX], nearBottom + 1),
              columnClipBottom[startX]);
          }
          clipOnlyPortalColumns += 1;
          portalHits += 1;
          const depth = columnPortalDepth[startX] + 1;
          columnPortalDepth[startX] = depth;
          if (depth > maxPortalDepth) maxPortalDepth = depth;
          const openingTop = Math.floor(
            HEIGHT / 2 - (clipOpeningCeiling - viewZ) * wallHeight / 128);
          const openingBottom = Math.ceil(
            HEIGHT / 2 - (clipOpeningFloor - viewZ) * wallHeight / 128) - 1;
          columnClipTop[startX] = Math.max(
            columnClipTop[startX], openingTop);
          columnClipBottom[startX] = Math.min(
            columnClipBottom[startX], openingBottom);
        } else {
          if (planes && litFlats !== undefined) {
            const nearTop = Math.floor(
              HEIGHT / 2
                - (sectorCeiling[nearSector] - viewZ) * wallHeight / 128);
            const nearBottom = Math.ceil(
              HEIGHT / 2
                - (sectorFloor[nearSector] - viewZ) * wallHeight / 128) - 1;
            recordPlaneRange(
              nearSector, true, startX, columnClipTop[startX],
              Math.min(columnClipBottom[startX], nearTop - 1));
            recordPlaneRange(
              nearSector, false, startX,
              Math.max(columnClipTop[startX], nearBottom + 1),
              columnClipBottom[startX]);
          }
          renderBspWallColumn(
            startX, line, fromRight, wallHeight, numerator, currentDenominator,
            playerX, playerY, viewZ, directionX, directionY,
          );
        }
        if (columnClipTop[startX] > columnClipBottom[startX]) {
          openColumns -= 1;
        }
      }
    }
  }
  if (planes && litFlats !== undefined) {
    drawRecordedPlanes(playerX, playerY, viewZ, directionX, directionY);
  }
  return (
    Math.imul(frame[index % PIXELS], 65537)
    + frame[(index * 997) % PIXELS]
    + lineTests
    + bspSegsVisited
  ) | 0;
}

function translatedWall(runtimeTexture) {
  if (runtimeTexture === 0 || runtimeTexture >= runtimeWallToAsset.length) {
    return 0xffff;
  }
  return runtimeWallToAsset[runtimeTexture];
}

function translatedFlat(runtimeLump, fallback) {
  if (runtimeLump >= runtimeFlatToAsset.length) return fallback;
  const asset = runtimeFlatToAsset[runtimeLump];
  return asset === 0xffff ? fallback : asset;
}

function loadWorldDynamics(snapshot) {
  if (!ArrayBuffer.isView(snapshot) || snapshot.byteLength < 208) {
    throw new Error('invalid DVL2 world snapshot');
  }
  if (!(snapshot instanceof Uint8Array)) {
    snapshot = new Uint8Array(
      snapshot.buffer, snapshot.byteOffset, snapshot.byteLength);
  }
  const state = new DataView(
    snapshot.buffer, snapshot.byteOffset, snapshot.byteLength);
  const sectors = state.getUint32(16, true);
  const mobjs = state.getUint32(20, true);
  const sectorOffset = state.getUint32(24, true);
  const mobjOffset = state.getUint32(28, true);
  const length = state.getUint32(32, true);
  const sides = state.getUint32(192, true);
  const sideOffset = state.getUint32(196, true);
  if (state.getUint32(0, true) !== 0x324c5644
      || state.getUint32(4, true) !== 2
      || sectors !== sectorFloor.length || sectorOffset !== 208
      || sides !== sideCount || state.getUint32(200, true) !== 8
      || state.getUint32(204, true) !== sectorOffset
      || sideOffset !== sectorOffset + sectors * 16
      || mobjOffset !== sideOffset + sides * 8
      || length !== mobjOffset + mobjs * 32
      || length !== snapshot.byteLength) {
    throw new Error('DVL2 world snapshot layout mismatch');
  }
  for (let sector = 0; sector < sectors; sector += 1) {
    const at = sectorOffset + sector * 16;
    sectorFloor[sector] = state.getInt32(at, true) >> 16;
    sectorCeiling[sector] = state.getInt32(at + 4, true) >> 16;
    sectorLight[sector] = state.getInt16(at + 8, true);
    sectorFloorAsset[sector] = translatedFlat(
      state.getUint16(at + 10, true), sectorFloorAsset[sector]);
    sectorCeilingAsset[sector] = translatedFlat(
      state.getUint16(at + 12, true), sectorCeilingAsset[sector]);
  }
  for (let side = 0; side < sides; side += 1) {
    const at = sideOffset + side * 8;
    dynamicSideTop[side] = translatedWall(state.getUint16(at, true));
    dynamicSideBottom[side] = translatedWall(state.getUint16(at + 2, true));
    dynamicSideMiddle[side] = translatedWall(state.getUint16(at + 4, true));
  }
  return state.getUint32(8, true);
}

export function renderWorldGeometry(snapshot) {
  const tic = loadWorldDynamics(snapshot);
  liveDynamicsActive = true;
  try {
    return render(tic, snapshot, true);
  } finally {
    liveDynamicsActive = false;
  }
}

export function setColumnRange(start, end) {
  if (!Number.isInteger(start) || !Number.isInteger(end)
      || start < 0 || end < start || end >= WIDTH) {
    throw new Error(`invalid renderer column range ${start}/${end}`);
  }
  renderStartColumn = start;
  renderEndColumn = end;
  return end - start + 1;
}

export function renderWorldGeometryStatic(snapshot) {
  if (!ArrayBuffer.isView(snapshot) || snapshot.byteLength < 208) {
    throw new Error('invalid static DVL2 pose snapshot');
  }
  return render(0, snapshot, true);
}

export function renderWorldFastGeometryStatic(snapshot) {
  if (!ArrayBuffer.isView(snapshot) || snapshot.byteLength < 208) {
    throw new Error('invalid fast DVL2 pose snapshot');
  }
  return renderRayReference(0, snapshot);
}

export function renderWorldCommandGeometryStatic(snapshot) {
  if (!ArrayBuffer.isView(snapshot) || snapshot.byteLength < 208) {
    throw new Error('invalid command DVL2 pose snapshot');
  }
  wallCommandCount = 0;
  planeCommandCount = 0;
  captureCommandOnly = true;
  try {
    render(0, snapshot, true);
  } finally {
    captureCommandOnly = false;
  }
  return wallCommandCount + planeCommandCount;
}

export function loadWorldDynamicsStage(snapshot) {
  return loadWorldDynamics(snapshot);
}

export function renderLoadedWorldWalls(snapshot) {
  liveDynamicsActive = true;
  try {
    return render(0, snapshot, false);
  } finally {
    liveDynamicsActive = false;
  }
}

export function renderLoadedWorldGeometry(snapshot) {
  liveDynamicsActive = true;
  try {
    return render(0, snapshot, true);
  } finally {
    liveDynamicsActive = false;
  }
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
      || offset < 0 || length < 1 || length > 32000
      || frame === undefined || offset + length > frame.byteLength) {
    throw new Error('frame chunk outside retained framebuffer');
  }
  return frame.slice(offset, offset + length);
}

export function frameByRef() {
  if (!(frame instanceof Uint8Array) || frame.byteLength !== PIXELS) {
    throw new Error('retained framebuffer is unavailable');
  }
  return frame;
}

export function stats() {
  return `width=${WIDTH}|height=${HEIGHT}|poses=${poseCount}`
    + `|layout=COLUMN_MAJOR_INDEXED`
    + `|lineTests=${lineTests}|cellsVisited=${cellsVisited}`
    + `|cacheHits=${cacheHits}|cacheMisses=${cacheMisses}`
    + `|cacheColdMisses=${cacheColdMisses}`
    + `|cacheReplacements=${cacheReplacements}`
    + `|portalHits=${portalHits}|solidHits=${solidHits}`
    + `|maxPortalDepth=${maxPortalDepth}`
    + `|bspSegsVisited=${bspSegsVisited}`
    + `|bspSubsectorsVisited=${bspSubsectorsVisited}`
    + `|bspBboxChecks=${bspBboxChecks}|bspBboxRejects=${bspBboxRejects}`
    + `|emptyPortalSegsSkipped=${emptyPortalSegsSkipped}`
    + `|clipOnlyPortalColumns=${clipOnlyPortalColumns}`
    + `|planePixelWrites=${planePixelWrites}`
    + `|wallCommands=${wallCommandCount}|planeCommands=${planeCommandCount}`
    + `|lightBanks=${lightBankCount}|litTextureBytes=${litTextures?.byteLength}`
    + `|litFlatBytes=${litFlats?.byteLength}`;
}

export function release() {
  pack = view = frame = backgroundColumn = undefined;
  lineX1 = lineY1 = lineX2 = lineY2 = undefined;
  cellOffsets = cellLines = sinTable = cosTable = undefined;
  wallTextures = litTextures = lightToBank = undefined;
  flatTextures = litFlats = undefined;
  textureBase = textureWidth = textureHeight = undefined;
  lineTexture = lineXOffset = lineYOffset = undefined;
  lineLeftXOffset = lineLeftYOffset = lineFlags = undefined;
  lineRightSector = lineLeftSector = undefined;
  lineRightUpper = lineRightLower = lineRightMiddle = undefined;
  lineLeftUpper = lineLeftLower = lineLeftMiddle = undefined;
  lineRightSide = lineLeftSide = undefined;
  sectorFloor = sectorCeiling = sectorLight = colormaps = undefined;
  sectorFloorAsset = sectorCeilingAsset = subsectorSector = undefined;
  runtimeWallToAsset = runtimeFlatToAsset = undefined;
  dynamicSideTop = dynamicSideBottom = dynamicSideMiddle = undefined;
  cacheKeyA = cacheKeyB = cacheKeyC = cacheColumns = undefined;
  lineSeen = undefined;
  segX1 = segY1 = segX2 = segY2 = segLine = segDirection = undefined;
  ssectorFirst = ssectorCount = undefined;
  nodeX = nodeY = nodeDx = nodeDy = nodeChild0 = nodeChild1 = undefined;
  nodeBbox0Top = nodeBbox0Bottom = nodeBbox0Left = nodeBbox0Right = undefined;
  nodeBbox1Top = nodeBbox1Bottom = nodeBbox1Left = nodeBbox1Right = undefined;
  bspStack = bspStackCheck = undefined;
  columnClipTop = columnClipBottom = columnPortalDepth = undefined;
  planeTop = planeBottom = planeStamp = undefined;
  planeMinX = planeMaxX = touchedPlanes = spanStart = undefined;
}
