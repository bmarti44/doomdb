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
let sectorFloor;
let sectorCeiling;
let sectorLight;
let colormaps;
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

function u32(offset) {
  return view.getUint32(offset, true);
}

export function finalizePack() {
  if (pack === undefined) throw new Error('live-render pack is absent');
  view = new DataView(pack.buffer, pack.byteOffset, pack.byteLength);
  if (u32(0) !== MAGIC || u32(4) !== 3 || u32(76) !== pack.byteLength) {
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
  return pack.byteLength;
}

function cachedWallSegment(
    texture, textureX, wallHeight, projectedTop, drawTop, drawBottom,
    lightMap, verticalOffset) {
  textureX %= textureWidth[texture];
  if (textureX < 0) textureX += textureWidth[texture];
  let normalizedOffset = verticalOffset % textureHeight[texture];
  if (normalizedOffset < 0) normalizedOffset += textureHeight[texture];
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
  if (cacheColumns[slot] !== undefined
      && cacheKeyA[slot] === keyA
      && cacheKeyB[slot] === keyB
      && cacheKeyC[slot] === keyC) {
    cacheHits += 1;
    return cacheColumns[slot];
  }
  cacheMisses += 1;
  let column = cacheColumns[slot];
  const length = drawBottom - drawTop + 1;
  if (column === undefined || column.length !== length) {
    cacheColdMisses += 1;
    column = new Uint8Array(length);
  } else {
    cacheReplacements += 1;
  }
  const width = textureWidth[texture];
  const height = textureHeight[texture];
  const base = textureBase[texture];
  let textureY = normalizedOffset
    + (drawTop - projectedTop) * 128 / wallHeight;
  const textureStep = 128 / wallHeight;
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
  frame.set(cachedWallSegment(
    texture, textureX, wallHeight, projectedTop, drawTop, drawBottom,
    lightMap, verticalOffset,
  ), columnBase + drawTop);
}

function renderRayReference(index) {
  if (view === undefined || frame === undefined) {
    throw new Error('live-render pack has not been finalized');
  }
  if (litTextures === undefined) {
    throw new Error('wall textures have not been finalized');
  }
  index %= poseCount;
  const at = poseOffset + index * poseRecordBytes;
  const playerX = view.getInt32(at, true) / 65536;
  const playerY = view.getInt32(at + 4, true) / 65536;
  const angle = (view.getUint32(at + 8, true) >>> 5) & 2047;
  const viewZ = view.getInt32(at + 12, true) / 65536;
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

  for (let screenX = 0; screenX < WIDTH; screenX += 1) {
    const columnBase = screenX * HEIGHT;
    frame.set(backgroundColumn, columnBase);
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
        const upperTexture = fromRight
          ? lineRightUpper[hitLine] : lineLeftUpper[hitLine];
        const lowerTexture = fromRight
          ? lineRightLower[hitLine] : lineLeftLower[hitLine];
        let middleTexture = fromRight
          ? lineRightMiddle[hitLine] : lineLeftMiddle[hitLine];
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

  if (farSector === 0xffff) {
    let middleTexture = fromRight
      ? lineRightMiddle[line] : lineLeftMiddle[line];
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
  const upperTexture = fromRight ? lineRightUpper[line] : lineLeftUpper[line];
  const lowerTexture = fromRight ? lineRightLower[line] : lineLeftLower[line];
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
  const start = Math.max(0, Math.floor(minimumScreen));
  const end = Math.min(WIDTH - 1, Math.ceil(maximumScreen));
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

function render(index) {
  if (view === undefined || frame === undefined || litTextures === undefined) {
    throw new Error('BSP live renderer is not finalized');
  }
  index %= poseCount;
  const at = poseOffset + index * poseRecordBytes;
  const playerX = view.getInt32(at, true) / 65536;
  const playerY = view.getInt32(at + 4, true) / 65536;
  const angle = (view.getUint32(at + 8, true) >>> 5) & 2047;
  const viewZ = view.getInt32(at + 12, true) / 65536;
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
  columnClipTop.fill(0);
  columnClipBottom.fill(HEIGHT - 1);
  columnPortalDepth.fill(0);
  for (let screenX = 0; screenX < WIDTH; screenX += 1) {
    frame.set(backgroundColumn, screenX * HEIGHT);
  }

  let stackSize = 1;
  bspStack[0] = nodeCount - 1;
  bspStackCheck[0] = -1;
  let openColumns = WIDTH;
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
      const middleTexture = fromRight
        ? lineRightMiddle[line] : lineLeftMiddle[line];
      if (farSector !== 0xffff
          && middleTexture === 0xffff
          && sectorFloor[nearSector] === sectorFloor[farSector]
          && sectorCeiling[nearSector] === sectorCeiling[farSector]) {
        emptyPortalSegsSkipped += 1;
        continue;
      }
      const upperTexture = fromRight
        ? lineRightUpper[line] : lineLeftUpper[line];
      const lowerTexture = fromRight
        ? lineRightLower[line] : lineLeftLower[line];
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
        0, Math.ceil(Math.min(projectedA, projectedB) - 0.5));
      const endX = Math.min(
        WIDTH - 1, Math.floor(Math.max(projectedA, projectedB) - 0.5));
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
  return (
    Math.imul(frame[index % PIXELS], 65537)
    + frame[(index * 997) % PIXELS]
    + lineTests
    + bspSegsVisited
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
      || offset < 0 || length < 1 || length > 32000
      || frame === undefined || offset + length > frame.byteLength) {
    throw new Error('frame chunk outside retained framebuffer');
  }
  return frame.slice(offset, offset + length);
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
    + `|lightBanks=${lightBankCount}|litTextureBytes=${litTextures?.byteLength}`;
}

export function release() {
  pack = view = frame = backgroundColumn = undefined;
  lineX1 = lineY1 = lineX2 = lineY2 = undefined;
  cellOffsets = cellLines = sinTable = cosTable = undefined;
  wallTextures = litTextures = lightToBank = undefined;
  textureBase = textureWidth = textureHeight = undefined;
  lineTexture = lineXOffset = lineYOffset = undefined;
  lineLeftXOffset = lineLeftYOffset = lineFlags = undefined;
  lineRightSector = lineLeftSector = undefined;
  lineRightUpper = lineRightLower = lineRightMiddle = undefined;
  lineLeftUpper = lineLeftLower = lineLeftMiddle = undefined;
  sectorFloor = sectorCeiling = sectorLight = colormaps = undefined;
  cacheKeyA = cacheKeyB = cacheKeyC = cacheColumns = undefined;
  lineSeen = undefined;
  segX1 = segY1 = segX2 = segY2 = segLine = segDirection = undefined;
  ssectorFirst = ssectorCount = undefined;
  nodeX = nodeY = nodeDx = nodeDy = nodeChild0 = nodeChild1 = undefined;
  nodeBbox0Top = nodeBbox0Bottom = nodeBbox0Left = nodeBbox0Right = undefined;
  nodeBbox1Top = nodeBbox1Bottom = nodeBbox1Left = nodeBbox1Right = undefined;
  bspStack = bspStackCheck = undefined;
  columnClipTop = columnClipBottom = columnPortalDepth = undefined;
}
