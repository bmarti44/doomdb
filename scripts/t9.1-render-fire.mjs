import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import zlib from 'node:zlib';

const root = path.resolve(import.meta.dirname, '..');
const output = path.resolve(process.argv[2]
  ?? path.join(root, 'client/dist/review/model-fire.apng'));
const result = spawnSync(path.join(root, 'scripts/db_sql.sh'),
  [path.join(root, 'scripts/t9.1-export-fire.sql')],
  {cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
if (result.status !== 0) throw Error(result.stderr || result.stdout);
const width = 160, height = 96, frameCount = 150;
const frames = Array.from({length: frameCount}, () => Buffer.alloc(width * height));
const offsets = new Int32Array(frameCount);
let runCount = 0;
for (const line of result.stdout.split(/\r?\n/)) {
  if (!/^\d+\|\d+\|\d+\|\d+$/.test(line)) continue;
  const [frame, start, length, intensity] = line.split('|').map(Number);
  assert.ok(frame >= 0 && frame < frameCount && start === offsets[frame]);
  assert.ok(length > 0 && start + length <= width * height);
  assert.ok(intensity >= 0 && intensity <= 36);
  frames[frame].fill(intensity, start, start + length);
  offsets[frame] += length; runCount += 1;
}
assert.equal(runCount, 604369);
assert.ok([...offsets].every(value => value === width * height));
const animationSha = createHash('sha256').update(Buffer.concat(frames)).digest('hex');
assert.equal(animationSha,
  'b1eac353252af51494cfe4ca77a80ac2bad502761bbaf79dd382f1146cb7e4ba',
  'database animation does not match the frozen T9.1 identity');

const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n += 1) {
  let crc = n;
  for (let bit = 0; bit < 8; bit += 1) crc = (crc & 1)
    ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  crcTable[n] = crc >>> 0;
}
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function u32(value) { const out = Buffer.alloc(4); out.writeUInt32BE(value); return out; }
function chunk(type, data) {
  const name = Buffer.from(type, 'ascii'), body = Buffer.concat([name, data]);
  return Buffer.concat([u32(data.length), body, u32(crc32(body))]);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
ihdr[8] = 8; ihdr[9] = 3;
const palette = Buffer.alloc(37 * 3);
for (let value = 0; value <= 36; value += 1) {
  const phase = value / 36;
  palette[value * 3] = Math.round(255 * Math.min(1, phase * 2.4));
  palette[value * 3 + 1] = Math.round(255 * Math.max(0, Math.min(1, phase * 2.4 - .65)));
  palette[value * 3 + 2] = Math.round(120 * Math.max(0, phase * 2.4 - 1.55));
}
const parts = [Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', ihdr),
  chunk('PLTE', palette), chunk('acTL', Buffer.concat([u32(frameCount), u32(0)]))];
let sequence = 0;
for (let frame = 0; frame < frameCount; frame += 1) {
  const control = Buffer.alloc(26);
  control.writeUInt32BE(sequence++, 0); control.writeUInt32BE(width, 4);
  control.writeUInt32BE(height, 8); control.writeUInt16BE(1, 20);
  control.writeUInt16BE(35, 22); control[24] = 0; control[25] = 0;
  parts.push(chunk('fcTL', control));
  const scanlines = Buffer.alloc((width + 1) * height);
  for (let y = 0; y < height; y += 1)
    frames[frame].copy(scanlines, y * (width + 1) + 1, y * width, (y + 1) * width);
  const compressed = zlib.deflateSync(scanlines, {level: 9});
  parts.push(frame === 0 ? chunk('IDAT', compressed)
    : chunk('fdAT', Buffer.concat([u32(sequence++), compressed])));
}
parts.push(chunk('IEND', Buffer.alloc(0)));
fs.mkdirSync(path.dirname(output), {recursive: true});
const animation = Buffer.concat(parts);
fs.writeFileSync(output, animation);
const artifactSha = createHash('sha256').update(animation).digest('hex');
const reviewFrames = [0, 35, 75, 110, 149];
const reviewWidth = width * reviewFrames.length;
const reviewIhdr = Buffer.alloc(13);
reviewIhdr.writeUInt32BE(reviewWidth, 0); reviewIhdr.writeUInt32BE(height, 4);
reviewIhdr[8] = 8; reviewIhdr[9] = 3;
const reviewScanlines = Buffer.alloc((reviewWidth + 1) * height);
for (let y = 0; y < height; y += 1) {
  for (let panel = 0; panel < reviewFrames.length; panel += 1) {
    frames[reviewFrames[panel]].copy(reviewScanlines,
      y * (reviewWidth + 1) + 1 + panel * width, y * width, (y + 1) * width);
  }
}
const review = Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'),
  chunk('IHDR', reviewIhdr), chunk('PLTE', palette),
  chunk('IDAT', zlib.deflateSync(reviewScanlines, {level: 9})),
  chunk('IEND', Buffer.alloc(0))]);
const reviewOutput = output.replace(/\.apng$/i, '-review.png');
fs.writeFileSync(reviewOutput, review);
process.stdout.write(`WROTE ${output} (${frameCount} frames, ${runCount} database runs, ` +
  `animation ${animationSha}, artifact ${artifactSha}, review ${reviewFrames.join('/')})\n`);
