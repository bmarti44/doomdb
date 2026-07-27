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
if (poses.length !== 5250 * 12) {
  throw new Error(`pose length mismatch: ${poses.length}`);
}

const HEADER = 96;
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
const pack = Buffer.alloc(cursor);

pack.writeUInt32LE(0x31465244, 0); // DRF1
pack.writeUInt32LE(1, 4);
pack.writeInt32LE(originX, 8);
pack.writeInt32LE(originY, 12);
pack.writeUInt32LE(columns, 16);
pack.writeUInt32LE(rowsCount, 20);
pack.writeUInt32LE(lines.length, 24);
pack.writeUInt32LE(cellCount, 28);
pack.writeUInt32LE(cellLines.length, 32);
pack.writeUInt32LE(poses.length / 12, 36);
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
fs.mkdirSync(path.dirname(outputFile), {recursive: true});
fs.writeFileSync(outputFile, pack);
process.stdout.write(
  `PMLE_FREE_LIVE_PACK|PASS|bytes=${pack.length}|lines=${lines.length}`
  + `|cells=${cellCount}|cellRefs=${cellLines.length}|poses=${poses.length / 12}`
  + `|originX=${originX}|originY=${originY}|columns=${columns}|rows=${rowsCount}\n`,
);
