#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const [baseFile, currentFile, outputFile] = process.argv.slice(2);
if (!baseFile || !currentFile || !outputFile) {
  throw new Error('usage: BASE_V4.pack CURRENT_V7.pack OUTPUT.pack');
}
const base = fs.readFileSync(baseFile);
const current = fs.readFileSync(currentFile);
const magic = 0x31465244;
if (base.readUInt32LE(0) !== magic || base.readUInt32LE(4) !== 4
    || base.readUInt32LE(76) !== base.length) {
  throw new Error('invalid pinned v4 world pack');
}
if (current.readUInt32LE(0) !== magic || current.readUInt32LE(4) !== 7
    || current.readUInt32LE(76) !== current.length
    || current.readUInt32LE(492) !== 208) {
  throw new Error('invalid current v7 live pack');
}
const lineCount = base.readUInt32LE(24);
if (current.readUInt32LE(24) !== lineCount) {
  throw new Error('world/live line cardinality mismatch');
}
const sideCount = current.readUInt32LE(488);
const wallCount = current.readUInt32LE(468);
const flatCount = current.readUInt32LE(476);
const rightSource = current.readUInt32LE(480);
const leftSource = current.readUInt32LE(484);
const wallSource = current.readUInt32LE(464);
const flatSource = current.readUInt32LE(472);
const extension = (base.length + 3) & ~3;
const headerBytes = 40;
const rightOffset = extension + headerBytes;
const leftOffset = rightOffset + lineCount * 2;
const wallOffset = leftOffset + lineCount * 2;
const flatOffset = wallOffset + wallCount * 2;
const total = flatOffset + flatCount * 2;
const output = Buffer.alloc(total);
base.copy(output);
current.copy(output, rightOffset, rightSource, rightSource + lineCount * 2);
current.copy(output, leftOffset, leftSource, leftSource + lineCount * 2);
current.copy(output, wallOffset, wallSource, wallSource + wallCount * 2);
current.copy(output, flatOffset, flatSource, flatSource + flatCount * 2);
output.writeUInt32LE(5, 4);
output.writeUInt32LE(total, 76);
output.writeUInt32LE(extension, 300);
output.writeUInt32LE(0x314d4c44, extension); // DLM1
output.writeUInt32LE(sideCount, extension + 4);
output.writeUInt32LE(lineCount, extension + 8);
output.writeUInt32LE(wallCount, extension + 12);
output.writeUInt32LE(flatCount, extension + 16);
output.writeUInt32LE(rightOffset, extension + 20);
output.writeUInt32LE(leftOffset, extension + 24);
output.writeUInt32LE(wallOffset, extension + 28);
output.writeUInt32LE(flatOffset, extension + 32);
output.writeUInt32LE(total, extension + 36);
fs.mkdirSync(path.dirname(outputFile), {recursive: true});
fs.writeFileSync(outputFile, output);
process.stdout.write(
  `PMLE_FREE_LIVE_WORLD_PACK_EXTEND|PASS|bytes=${total}` +
  `|lines=${lineCount}|sides=${sideCount}` +
  `|runtime_walls=${wallCount}|runtime_flats=${flatCount}\n`,
);
