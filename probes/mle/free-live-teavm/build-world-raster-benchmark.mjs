#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  throw new Error('usage: INPUT.sql OUTPUT.sql');
}
const source = fs.readFileSync(input, 'utf8');
const units = source.split(/\n\/\n/);
const removed = [];
const retained = units.filter(unit => {
  if (unit.includes('doom_free_gen_sprite_')) {
    removed.push('SPRITE_LOAD');
    return false;
  }
  if (unit.includes('doom_free_gen_ui_')) {
    removed.push('UI_LOAD');
    return false;
  }
  return true;
});
if (removed.join(',') !== 'SPRITE_LOAD,UI_LOAD') {
  throw new Error(`world benchmark removal mismatch: ${removed.join(',')}`);
}
const result = retained.join('\n/\n');
for (const required of [
  'PMLE_FREE_LIVE_TEAVM_RASTER_LOAD',
  'PMLE_FREE_LIVE_TEAVM_RASTER_PASS',
  'PMLE_FREE_LIVE_TEAVM_COARSE',
  'PMLE_FREE_LIVE_COARSE_FRAME_CAPTURE',
]) {
  if (!result.includes(required)) {
    throw new Error(`world benchmark lost ${required}`);
  }
}
fs.mkdirSync(path.dirname(output), {recursive: true});
fs.writeFileSync(output, result);
process.stdout.write(
  `PMLE_FREE_LIVE_WORLD_BENCHMARK|PASS|bytes=${Buffer.byteLength(result)}` +
    '|removed=SPRITE_LOAD,UI_LOAD\n',
);
