#!/usr/bin/env node
import {createHash} from 'node:crypto';
import fs from 'node:fs';

const [fixturePath, outputPath] = process.argv.slice(2);
if (!fixturePath || !outputPath) {
  throw new Error('usage: expand-real-draw-fixture.mjs FIXTURE OUTPUT');
}
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
if (fixture.schema !== 1 || fixture.players !== 2 || fixture.tics !== 5250) {
  throw new Error('unexpected real-draw fixture contract');
}
const records = [];
for (const run of fixture.runs) {
  if (!Number.isInteger(run.membership)
      || !/^[0-9a-f]{64}$/.test(run.command)
      || !Number.isInteger(run.repeat) || run.repeat < 1) {
    throw new Error('invalid real-draw fixture run');
  }
  const command = Buffer.from(run.command, 'hex');
  for (let index = 0; index < run.repeat; index += 1) {
    records.push(Buffer.concat([Buffer.from([run.membership]), command]));
  }
}
if (records.length !== fixture.tics) {
  throw new Error(`expanded tic count ${records.length}`);
}
const expanded = Buffer.concat(records);
const expandedForDigest = Buffer.concat(records.map(record =>
  Buffer.concat([record.subarray(0, 1), record.subarray(1)])));
const digest = createHash('sha256').update(expandedForDigest).digest('hex');
if (digest !== fixture.expandedSha256) {
  throw new Error(`expanded digest ${digest}`);
}
fs.writeFileSync(outputPath, expanded);
process.stdout.write(
  `PMLE_REAL_DRAW_FIXTURE|PASS|tics=${records.length}`
  + `|bytes=${expanded.length}|sha256=${digest}\n`,
);
