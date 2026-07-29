#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import zlib from 'node:zlib';

const [logFile, outputFile, mode = 'normal'] = process.argv.slice(2);
if (!logFile || !outputFile) {
  throw new Error('usage: RANK_LOG OUTPUT.png [normal|coarse]');
}
if (!['normal', 'coarse'].includes(mode)) {
  throw new Error('frame extraction mode must be normal or coarse');
}

const input = fs.readFileSync(logFile);
let columnMajor;
let source;
if (input.length === 320 * 200) {
  columnMajor = input;
  source = 'RAW_FRAME';
} else {
  const log = input.toString('utf8');
  const chunks = new Map();
  const prefix = mode === 'coarse'
    ? 'PMLE_FREE_LIVE_COARSE_FRAME' : 'PMLE_FREE_LIVE_FRAME';
  const pose = mode === 'coarse' ? 751 : 750;
  const chunkPattern = new RegExp(
    `^${prefix}_CHUNK\\|PASS\\|pose=${pose}` +
      '\\|part=(\\d+)\\|bytes=8000\\|hex=([0-9A-F]{16000})$',
    'gm',
  );
  for (const match of log.matchAll(chunkPattern)) {
    chunks.set(Number(match[1]), Buffer.from(match[2], 'hex'));
  }
  if (chunks.size !== 8
      || !log.includes(
        `${prefix}_CAPTURE|PASS|pose=${pose}|bytes=64000`,
      )) {
    throw new Error(`incomplete frame capture: ${chunks.size}/8 chunks`);
  }
  columnMajor = Buffer.concat(
    Array.from({length: 8}, (_, part) => chunks.get(part)),
  );
  source = 'OCI_CAPTURE_LOG';
}

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const paletteSql = fs.readFileSync(
  path.join(root, 'sql/seed/110_palette_texels.sql'),
  'utf8',
);
const palette = Array.from({length: 256}, () => [0, 0, 0]);
let paletteEntries = 0;
for (const match of paletteSql.matchAll(
  /VALUES \((\d+), (\d+), (\d+), (\d+)\)/g,
)) {
  palette[Number(match[1])] = [
    Number(match[2]), Number(match[3]), Number(match[4]),
  ];
  paletteEntries += 1;
}
if (paletteEntries !== 256) {
  throw new Error(`incomplete palette: ${paletteEntries}/256 entries`);
}

const width = 320;
const height = 200;
const scanlines = Buffer.alloc((width * 3 + 1) * height);
for (let y = 0; y < height; y += 1) {
  const row = y * (width * 3 + 1);
  scanlines[row] = 0;
  for (let x = 0; x < width; x += 1) {
    const rgb = palette[columnMajor[x * height + y]];
    const output = row + 1 + x * 3;
    scanlines[output] = rgb[0];
    scanlines[output + 1] = rgb[1];
    scanlines[output + 2] = rgb[2];
  }
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const value of bytes) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(kind, data) {
  const type = Buffer.from(kind, 'ascii');
  const result = Buffer.alloc(12 + data.length);
  result.writeUInt32BE(data.length, 0);
  type.copy(result, 4);
  data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([type, data])), 8 + data.length);
  return result;
}

const header = Buffer.alloc(13);
header.writeUInt32BE(width, 0);
header.writeUInt32BE(height, 4);
header[8] = 8;
header[9] = 2;
const png = Buffer.concat([
  Buffer.from('89504e470d0a1a0a', 'hex'),
  pngChunk('IHDR', header),
  pngChunk('IDAT', zlib.deflateSync(scanlines, {level: 9})),
  pngChunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(outputFile, png);
process.stdout.write(
  `PMLE_FREE_LIVE_FRAME_EXTRACT|PASS|source=${source}|bytes=${columnMajor.length}`
    + `|png_bytes=${png.length}|output=${outputFile}\n`,
);
