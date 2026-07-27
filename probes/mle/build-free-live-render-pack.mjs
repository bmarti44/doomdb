#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

function rows(file, marker) {
  const text = fs.readFileSync(file, 'utf8');
  const result = [];
  const pattern = new RegExp(`${marker}[^\\n]*VALUES \\(([^\\n]+)\\)`, 'g');
  for (const match of text.matchAll(pattern)) {
    result.push(match[1].split(',').map(value => value.trim()));
  }
  if (result.length === 0) throw new Error(`no ${marker} rows in ${file}`);
  return result;
}

function align(value, boundary) {
  return Math.ceil(value / boundary) * boundary;
}

function unsignedWord(bytes, word) {
  const offset = word * 2;
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function signedWord(value) {
  return value >= 0x8000 ? value - 0x10000 : value;
}

const [root, poseFile, outputFile] = process.argv.slice(2);
if (!root || !poseFile || !outputFile) {
  throw new Error('usage: ROOT POSES OUTPUT');
}

const vertexRows = rows(
  path.join(root, 'sql/seed/020_vertices.sql'),
  'DOOM_MAP_VERTEX',
);
const lineRows = rows(
  path.join(root, 'sql/seed/030_linedefs.sql'),
  'DOOM_MAP_LINEDEF',
);
const byteRows = rows(
  path.join(root, 'sql/seed/100_blockmap_bytes.sql'),
  'DOOM_BLOCKMAP_BYTE',
);
const assetRows = rows(
  path.join(root, 'sql/seed/140_assets.sql'),
  'DOOM_ASSET',
);
const sideRows = rows(
  path.join(root, 'sql/seed/040_sidedefs.sql'),
  'DOOM_MAP_SIDEDEF',
);
const sectorRows = rows(
  path.join(root, 'sql/seed/050_sectors.sql'),
  'DOOM_MAP_SECTOR',
);
const segRows = rows(
  path.join(root, 'sql/seed/060_segs.sql'),
  'DOOM_MAP_SEG',
);
const ssectorRows = rows(
  path.join(root, 'sql/seed/070_ssectors.sql'),
  'DOOM_MAP_SSECTOR',
);
const nodeRows = rows(
  path.join(root, 'sql/seed/080_nodes.sql'),
  'DOOM_MAP_NODE',
);
const colormapRows = rows(
  path.join(root, 'sql/seed/120_colormap_texels.sql'),
  'DOOM_COLORMAP_TEXEL',
);
const text = value => value === 'NULL'
  ? null : value.replace(/^'(.*)'$/, '$1').replace(/''/g, "'");
const vertices = new Map(vertexRows.map(row => [
  Number(row[0]),
  [Number(row[1]), Number(row[2])],
]));
const lines = lineRows.map(row => {
  const start = vertices.get(Number(row[1]));
  const end = vertices.get(Number(row[2]));
  if (!start || !end) throw new Error(`linedef ${row[0]} vertex missing`);
  return [start[0], start[1], end[0], end[1]];
});
const wallAssets = assetRows
  .filter(row => text(row[1]) === 'wall_texture')
  .map(row => ({
    id: Number(row[0]),
    name: text(row[2]),
    width: Number(row[3]),
    height: Number(row[4]),
  }))
  .sort((left, right) => left.id - right.id);
let wallElements = 0;
for (let index = 0; index < wallAssets.length; index += 1) {
  wallAssets[index].index = index;
  wallAssets[index].base = wallElements;
  wallElements += wallAssets[index].width * wallAssets[index].height;
}
const wallByName = new Map(wallAssets.map(asset => [asset.name, asset]));
const textureIndex = name => name === '-' || !wallByName.has(name)
  ? 0xffff : wallByName.get(name).index;
const sides = new Map(sideRows.map(row => [Number(row[0]), {
  xOffset: Number(row[1]),
  yOffset: Number(row[2]),
  upper: text(row[3]),
  lower: text(row[4]),
  middle: text(row[5]),
  sector: Number(row[6]),
}]));
const sectors = sectorRows.map(row => ({
  floor: Number(row[1]),
  ceiling: Number(row[2]),
  light: Number(row[5]),
}));
const segs = segRows.map((row, index) => {
  if (Number(row[0]) !== index) throw new Error(`non-dense seg id ${row[0]}`);
  const start = vertices.get(Number(row[1]));
  const end = vertices.get(Number(row[2]));
  if (!start || !end) throw new Error(`seg ${row[0]} vertex missing`);
  return {
    x1: start[0], y1: start[1], x2: end[0], y2: end[1],
    line: Number(row[4]), direction: Number(row[5]),
  };
});
const ssectors = ssectorRows.map((row, index) => {
  if (Number(row[0]) !== index) {
    throw new Error(`non-dense subsector id ${row[0]}`);
  }
  return {count: Number(row[1]), first: Number(row[2])};
});
const nodes = nodeRows.map((row, index) => {
  if (Number(row[0]) !== index) throw new Error(`non-dense node id ${row[0]}`);
  const child = side => {
    const isSubsector = Number(row[13 + side * 2]);
    const id = Number(row[14 + side * 2]);
    return isSubsector === 1 ? (id | 0x80000000) : id;
  };
  return {
    x: Number(row[1]), y: Number(row[2]),
    dx: Number(row[3]), dy: Number(row[4]),
    bbox0: {
      top: Number(row[5]), bottom: Number(row[6]),
      left: Number(row[7]), right: Number(row[8]),
    },
    bbox1: {
      top: Number(row[9]), bottom: Number(row[10]),
      left: Number(row[11]), right: Number(row[12]),
    },
    child0: child(0), child1: child(1),
  };
});
const colormaps = Buffer.alloc(32 * 256);
for (const row of colormapRows) {
  colormaps[Number(row[0]) * 256 + Number(row[1])] = Number(row[2]);
}
const linePresentation = lineRows.map(row => {
  const right = sides.get(Number(row[6]));
  const left = row[7] === 'NULL' ? null : sides.get(Number(row[7]));
  if (!right || (row[7] !== 'NULL' && !left)) {
    throw new Error(`linedef ${row[0]} sidedef missing`);
  }
  const textureName = [right.middle, right.upper, right.lower,
    left?.middle, left?.upper, left?.lower]
    .find(name => name !== '-' && wallByName.has(name));
  const texture = textureName === undefined
    ? wallAssets[0] : wallByName.get(textureName);
  return {
    texture: texture.index,
    xOffset: right.xOffset,
    yOffset: right.yOffset,
    rightSector: right.sector,
    leftSector: left === null ? 0xffff : left.sector,
    rightUpper: textureIndex(right.upper),
    rightLower: textureIndex(right.lower),
    rightMiddle: textureIndex(right.middle),
    leftUpper: left === null ? 0xffff : textureIndex(left.upper),
    leftLower: left === null ? 0xffff : textureIndex(left.lower),
    leftMiddle: left === null ? 0xffff : textureIndex(left.middle),
    leftXOffset: left === null ? 0 : left.xOffset,
    leftYOffset: left === null ? 0 : left.yOffset,
    flags: Number(row[3]),
  };
});

const blockBytes = Buffer.alloc(byteRows.length);
for (const row of byteRows) blockBytes[Number(row[0])] = Number(row[1]);
const originX = signedWord(unsignedWord(blockBytes, 0));
const originY = signedWord(unsignedWord(blockBytes, 1));
const columns = unsignedWord(blockBytes, 2);
const rowsCount = unsignedWord(blockBytes, 3);
const cellCount = columns * rowsCount;
const cellOffsets = new Uint32Array(cellCount + 1);
const cellLines = [];
for (let cell = 0; cell < cellCount; cell += 1) {
  cellOffsets[cell] = cellLines.length;
  let word = unsignedWord(blockBytes, 4 + cell);
  if (unsignedWord(blockBytes, word) !== 0) {
    throw new Error(`block cell ${cell} list header is not zero`);
  }
  word += 1;
  while (unsignedWord(blockBytes, word) !== 0xffff) {
    const line = unsignedWord(blockBytes, word);
    if (line >= lines.length) throw new Error(`block line ${line} unavailable`);
    cellLines.push(line);
    word += 1;
  }
}
cellOffsets[cellCount] = cellLines.length;

const poses = fs.readFileSync(poseFile);
const poseRecordBytes = poses.length / 5250;
if (!Number.isInteger(poseRecordBytes)
    || (poseRecordBytes !== 12 && poseRecordBytes !== 32)) {
  throw new Error(`pose length mismatch: ${poses.length}`);
}

const HEADER = 288;
let cursor = HEADER;
const offsets = {};
for (const name of ['lineX1', 'lineY1', 'lineX2', 'lineY2']) {
  offsets[name] = cursor;
  cursor += lines.length * 4;
}
offsets.cellOffsets = cursor;
cursor += cellOffsets.length * 4;
offsets.cellLines = cursor;
cursor += cellLines.length * 2;
cursor = align(cursor, 4);
offsets.poses = cursor;
cursor += poses.length;
cursor = align(cursor, 2);
offsets.sin = cursor;
cursor += 2048 * 2;
offsets.cos = cursor;
cursor += 2048 * 2;
cursor = align(cursor, 4);
offsets.textureBase = cursor;
cursor += wallAssets.length * 4;
offsets.textureWidth = cursor;
cursor += wallAssets.length * 2;
offsets.textureHeight = cursor;
cursor += wallAssets.length * 2;
offsets.lineTexture = cursor;
cursor += lines.length * 2;
offsets.lineXOffset = cursor;
cursor += lines.length * 2;
offsets.lineYOffset = cursor;
cursor += lines.length * 2;
offsets.lineRightSector = cursor;
cursor += lines.length * 2;
offsets.lineLeftSector = cursor;
cursor += lines.length * 2;
for (const name of [
  'lineRightUpper', 'lineRightLower', 'lineRightMiddle',
  'lineLeftUpper', 'lineLeftLower', 'lineLeftMiddle',
]) {
  offsets[name] = cursor;
  cursor += lines.length * 2;
}
offsets.lineLeftXOffset = cursor;
cursor += lines.length * 2;
offsets.lineLeftYOffset = cursor;
cursor += lines.length * 2;
offsets.lineFlags = cursor;
cursor += lines.length * 2;
for (const name of ['segX1', 'segY1', 'segX2', 'segY2']) {
  cursor = align(cursor, 4);
  offsets[name] = cursor;
  cursor += segs.length * 4;
}
offsets.segLine = cursor;
cursor += segs.length * 2;
offsets.segDirection = cursor;
cursor += segs.length;
cursor = align(cursor, 4);
offsets.ssectorFirst = cursor;
cursor += ssectors.length * 4;
offsets.ssectorCount = cursor;
cursor += ssectors.length * 2;
for (const name of ['nodeX', 'nodeY', 'nodeDx', 'nodeDy',
  'nodeChild0', 'nodeChild1']) {
  cursor = align(cursor, 4);
  offsets[name] = cursor;
  cursor += nodes.length * 4;
}
for (const name of [
  'nodeBbox0Top', 'nodeBbox0Bottom', 'nodeBbox0Left', 'nodeBbox0Right',
  'nodeBbox1Top', 'nodeBbox1Bottom', 'nodeBbox1Left', 'nodeBbox1Right',
]) {
  cursor = align(cursor, 4);
  offsets[name] = cursor;
  cursor += nodes.length * 4;
}
offsets.sectorFloor = cursor;
cursor += sectors.length * 2;
offsets.sectorCeiling = cursor;
cursor += sectors.length * 2;
offsets.sectorLight = cursor;
cursor += sectors.length;
offsets.colormaps = cursor;
cursor += colormaps.length;
const pack = Buffer.alloc(cursor);

pack.writeUInt32LE(0x31465244, 0); // DRF1
pack.writeUInt32LE(3, 4);
pack.writeInt32LE(originX, 8);
pack.writeInt32LE(originY, 12);
pack.writeUInt32LE(columns, 16);
pack.writeUInt32LE(rowsCount, 20);
pack.writeUInt32LE(lines.length, 24);
pack.writeUInt32LE(cellCount, 28);
pack.writeUInt32LE(cellLines.length, 32);
pack.writeUInt32LE(poses.length / poseRecordBytes, 36);
pack.writeUInt32LE(offsets.lineX1, 40);
pack.writeUInt32LE(offsets.lineY1, 44);
pack.writeUInt32LE(offsets.lineX2, 48);
pack.writeUInt32LE(offsets.lineY2, 52);
pack.writeUInt32LE(offsets.cellOffsets, 56);
pack.writeUInt32LE(offsets.cellLines, 60);
pack.writeUInt32LE(offsets.poses, 64);
pack.writeUInt32LE(offsets.sin, 68);
pack.writeUInt32LE(offsets.cos, 72);
pack.writeUInt32LE(pack.length, 76);
pack.writeUInt32LE(wallAssets.length, 80);
pack.writeUInt32LE(wallElements, 84);
pack.writeUInt32LE(offsets.textureBase, 88);
pack.writeUInt32LE(offsets.textureWidth, 92);
pack.writeUInt32LE(offsets.textureHeight, 96);
pack.writeUInt32LE(offsets.lineTexture, 100);
pack.writeUInt32LE(offsets.lineXOffset, 104);
pack.writeUInt32LE(offsets.lineYOffset, 108);
pack.writeUInt32LE(offsets.lineRightSector, 112);
pack.writeUInt32LE(offsets.lineLeftSector, 116);
pack.writeUInt32LE(sectors.length, 120);
pack.writeUInt32LE(offsets.sectorFloor, 124);
pack.writeUInt32LE(offsets.sectorCeiling, 128);
pack.writeUInt32LE(offsets.sectorLight, 132);
pack.writeUInt32LE(offsets.colormaps, 136);
pack.writeUInt32LE(offsets.lineRightUpper, 140);
pack.writeUInt32LE(offsets.lineRightLower, 144);
pack.writeUInt32LE(offsets.lineRightMiddle, 148);
pack.writeUInt32LE(offsets.lineLeftUpper, 152);
pack.writeUInt32LE(offsets.lineLeftLower, 156);
pack.writeUInt32LE(offsets.lineLeftMiddle, 160);
pack.writeUInt32LE(offsets.lineLeftXOffset, 164);
pack.writeUInt32LE(offsets.lineLeftYOffset, 168);
pack.writeUInt32LE(offsets.lineFlags, 172);
pack.writeUInt32LE(poseRecordBytes, 176);
pack.writeUInt32LE(segs.length, 180);
pack.writeUInt32LE(ssectors.length, 184);
pack.writeUInt32LE(nodes.length, 188);
pack.writeUInt32LE(offsets.segX1, 192);
pack.writeUInt32LE(offsets.segY1, 196);
pack.writeUInt32LE(offsets.segX2, 200);
pack.writeUInt32LE(offsets.segY2, 204);
pack.writeUInt32LE(offsets.segLine, 208);
pack.writeUInt32LE(offsets.segDirection, 212);
pack.writeUInt32LE(offsets.ssectorFirst, 216);
pack.writeUInt32LE(offsets.ssectorCount, 220);
pack.writeUInt32LE(offsets.nodeX, 224);
pack.writeUInt32LE(offsets.nodeY, 228);
pack.writeUInt32LE(offsets.nodeDx, 232);
pack.writeUInt32LE(offsets.nodeDy, 236);
pack.writeUInt32LE(offsets.nodeChild0, 240);
pack.writeUInt32LE(offsets.nodeChild1, 244);
pack.writeUInt32LE(offsets.nodeBbox0Top, 248);
pack.writeUInt32LE(offsets.nodeBbox0Bottom, 252);
pack.writeUInt32LE(offsets.nodeBbox0Left, 256);
pack.writeUInt32LE(offsets.nodeBbox0Right, 260);
pack.writeUInt32LE(offsets.nodeBbox1Top, 264);
pack.writeUInt32LE(offsets.nodeBbox1Bottom, 268);
pack.writeUInt32LE(offsets.nodeBbox1Left, 272);
pack.writeUInt32LE(offsets.nodeBbox1Right, 276);

for (let index = 0; index < lines.length; index += 1) {
  pack.writeInt32LE(lines[index][0], offsets.lineX1 + index * 4);
  pack.writeInt32LE(lines[index][1], offsets.lineY1 + index * 4);
  pack.writeInt32LE(lines[index][2], offsets.lineX2 + index * 4);
  pack.writeInt32LE(lines[index][3], offsets.lineY2 + index * 4);
}
for (let index = 0; index < cellOffsets.length; index += 1) {
  pack.writeUInt32LE(cellOffsets[index], offsets.cellOffsets + index * 4);
}
for (let index = 0; index < cellLines.length; index += 1) {
  pack.writeUInt16LE(cellLines[index], offsets.cellLines + index * 2);
}
poses.copy(pack, offsets.poses);
for (let index = 0; index < 2048; index += 1) {
  const radians = index * Math.PI * 2 / 2048;
  pack.writeInt16LE(Math.round(Math.sin(radians) * 32767), offsets.sin + index * 2);
  pack.writeInt16LE(Math.round(Math.cos(radians) * 32767), offsets.cos + index * 2);
}
for (let index = 0; index < wallAssets.length; index += 1) {
  pack.writeUInt32LE(wallAssets[index].base, offsets.textureBase + index * 4);
  pack.writeUInt16LE(wallAssets[index].width, offsets.textureWidth + index * 2);
  pack.writeUInt16LE(wallAssets[index].height, offsets.textureHeight + index * 2);
}
for (let index = 0; index < linePresentation.length; index += 1) {
  const line = linePresentation[index];
  pack.writeUInt16LE(line.texture, offsets.lineTexture + index * 2);
  pack.writeInt16LE(line.xOffset, offsets.lineXOffset + index * 2);
  pack.writeInt16LE(line.yOffset, offsets.lineYOffset + index * 2);
  pack.writeUInt16LE(line.rightSector, offsets.lineRightSector + index * 2);
  pack.writeUInt16LE(line.leftSector, offsets.lineLeftSector + index * 2);
  pack.writeUInt16LE(line.rightUpper, offsets.lineRightUpper + index * 2);
  pack.writeUInt16LE(line.rightLower, offsets.lineRightLower + index * 2);
  pack.writeUInt16LE(line.rightMiddle, offsets.lineRightMiddle + index * 2);
  pack.writeUInt16LE(line.leftUpper, offsets.lineLeftUpper + index * 2);
  pack.writeUInt16LE(line.leftLower, offsets.lineLeftLower + index * 2);
  pack.writeUInt16LE(line.leftMiddle, offsets.lineLeftMiddle + index * 2);
  pack.writeInt16LE(line.leftXOffset, offsets.lineLeftXOffset + index * 2);
  pack.writeInt16LE(line.leftYOffset, offsets.lineLeftYOffset + index * 2);
  pack.writeUInt16LE(line.flags, offsets.lineFlags + index * 2);
}
for (let index = 0; index < segs.length; index += 1) {
  const seg = segs[index];
  pack.writeInt32LE(seg.x1, offsets.segX1 + index * 4);
  pack.writeInt32LE(seg.y1, offsets.segY1 + index * 4);
  pack.writeInt32LE(seg.x2, offsets.segX2 + index * 4);
  pack.writeInt32LE(seg.y2, offsets.segY2 + index * 4);
  pack.writeUInt16LE(seg.line, offsets.segLine + index * 2);
  pack[offsets.segDirection + index] = seg.direction;
}
for (let index = 0; index < ssectors.length; index += 1) {
  pack.writeUInt32LE(ssectors[index].first, offsets.ssectorFirst + index * 4);
  pack.writeUInt16LE(ssectors[index].count, offsets.ssectorCount + index * 2);
}
for (let index = 0; index < nodes.length; index += 1) {
  const node = nodes[index];
  pack.writeInt32LE(node.x, offsets.nodeX + index * 4);
  pack.writeInt32LE(node.y, offsets.nodeY + index * 4);
  pack.writeInt32LE(node.dx, offsets.nodeDx + index * 4);
  pack.writeInt32LE(node.dy, offsets.nodeDy + index * 4);
  pack.writeInt32LE(node.child0, offsets.nodeChild0 + index * 4);
  pack.writeInt32LE(node.child1, offsets.nodeChild1 + index * 4);
  pack.writeInt32LE(node.bbox0.top, offsets.nodeBbox0Top + index * 4);
  pack.writeInt32LE(node.bbox0.bottom, offsets.nodeBbox0Bottom + index * 4);
  pack.writeInt32LE(node.bbox0.left, offsets.nodeBbox0Left + index * 4);
  pack.writeInt32LE(node.bbox0.right, offsets.nodeBbox0Right + index * 4);
  pack.writeInt32LE(node.bbox1.top, offsets.nodeBbox1Top + index * 4);
  pack.writeInt32LE(node.bbox1.bottom, offsets.nodeBbox1Bottom + index * 4);
  pack.writeInt32LE(node.bbox1.left, offsets.nodeBbox1Left + index * 4);
  pack.writeInt32LE(node.bbox1.right, offsets.nodeBbox1Right + index * 4);
}
for (let index = 0; index < sectors.length; index += 1) {
  pack.writeInt16LE(sectors[index].floor, offsets.sectorFloor + index * 2);
  pack.writeInt16LE(sectors[index].ceiling, offsets.sectorCeiling + index * 2);
  pack[offsets.sectorLight + index] = sectors[index].light;
}
colormaps.copy(pack, offsets.colormaps);
fs.mkdirSync(path.dirname(outputFile), {recursive: true});
fs.writeFileSync(outputFile, pack);
process.stdout.write(
  `PMLE_FREE_LIVE_PACK|PASS|bytes=${pack.length}|lines=${lines.length}`
  + `|cells=${cellCount}|cellRefs=${cellLines.length}`
  + `|poses=${poses.length / poseRecordBytes}|poseRecordBytes=${poseRecordBytes}`
  + `|originX=${originX}|originY=${originY}|columns=${columns}|rows=${rowsCount}`
  + `|wallTextures=${wallAssets.length}|wallElements=${wallElements}`
  + `|sectors=${sectors.length}|segs=${segs.length}`
  + `|ssectors=${ssectors.length}|nodes=${nodes.length}\n`,
);
