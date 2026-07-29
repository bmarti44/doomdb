#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const [input, output, layout = 'column'] = process.argv.slice(2);
if (!input || !output || !['column', 'row'].includes(layout)) {
  throw new Error(
    'usage: indexed-frame-to-ppm.mjs INPUT OUTPUT [column|row]');
}
const root = path.resolve(import.meta.dirname, '../..');
const iwad = fs.readFileSync(path.join(
  root, 'probes/mle/teavm-engine/target/iwad-smoke/freedoom1.wad'));
const frame = fs.readFileSync(input);
if (frame.length !== 320 * 200) {
  throw new Error(`frame must contain 64,000 bytes: ${frame.length}`);
}
const lumpCount = iwad.readUInt32LE(4);
const directory = iwad.readUInt32LE(8);
let palette;
for (let index = 0; index < lumpCount; index++) {
  const at = directory + index * 16;
  const name = iwad.toString('ascii', at + 8, at + 16)
    .replace(/\0.*$/s, '');
  if (name === 'PLAYPAL') {
    const offset = iwad.readUInt32LE(at);
    palette = iwad.subarray(offset, offset + 768);
    break;
  }
}
if (!palette || palette.length !== 768) {
  throw new Error('PLAYPAL palette is absent');
}
const rgb = Buffer.alloc(320 * 200 * 3);
for (let y = 0; y < 200; y++) {
  for (let x = 0; x < 320; x++) {
    const source = layout === 'column' ? x * 200 + y : y * 320 + x;
    const color = frame[source] * 3;
    palette.copy(rgb, (y * 320 + x) * 3, color, color + 3);
  }
}
fs.writeFileSync(
  output, Buffer.concat([Buffer.from('P6\n320 200\n255\n'), rgb]));
