#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

export function extract(text) {
  assert.ok(!/(^|\n)\s*(?:SKIP|NOT RUN|TODO|TIMEOUT|Bail out!|FAIL)\b/i.test(text), 'no failure or skip marker');
  const matches = [...text.matchAll(/^T103_RUN_RECORD (\{.*\})$/gm)];
  assert.equal(matches.length, 1, 'exactly one run record');
  const record = JSON.parse(matches[0][1]);
  assert.equal(record.task, 'T10.3');
  return `${JSON.stringify(record)}\n`;
}

if (process.argv[2] === '--self-test') {
  const good = 'PASS X (1/1)\nT103_RUN_RECORD {"task":"T10.3","schema":1}\n';
  assert.equal(JSON.parse(extract(good)).task, 'T10.3');
  assert.throws(() => extract(''));
  assert.throws(() => extract(`${good}${good}`));
  assert.throws(() => extract(`SKIP nope\n${good}`));
  process.stdout.write('PASS T10.3-RECORD-UNIT (4/4 extraction mutations checked)\n');
} else {
  assert.equal(process.argv.length, 4, 'usage: extract input.log output.json');
  const result = extract(fs.readFileSync(process.argv[2], 'utf8'));
  fs.writeFileSync(process.argv[3], result, {encoding:'utf8',mode:0o600,flag:'wx'});
}
