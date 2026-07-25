#!/usr/bin/env node
import {createHash} from 'node:crypto';
import fs from 'node:fs';

function digest(text) {
  const rows = text.split(/\r?\n/).filter(Boolean);
  if (rows.length === 0) throw new Error('command stream is empty');
  const hash = createHash('sha256');
  for (const [index, row] of rows.entries()) {
    const parts = row.split('|');
    if (parts.length !== 3
        || !/^[1-9][0-9]*$/.test(parts[0])
        || Number(parts[0]) !== index + 1
        || !/^[0-9]+$/.test(parts[1])
        || Number(parts[1]) > 255
        || !/^[0-9a-f]{64}$/.test(parts[2])) {
      throw new Error(`invalid command-stream row ${index + 1}`);
    }
    hash.update(Buffer.from([Number(parts[1])]));
    hash.update(Buffer.from(parts[2], 'hex'));
  }
  return hash.digest('hex');
}

if (process.argv[2] === '--self-test') {
  const valid = `1|3|${'00'.repeat(32)}\n2|1|${'ff'.repeat(32)}\n`;
  const expected = createHash('sha256')
    .update(Buffer.concat([
      Buffer.from([3]), Buffer.alloc(32),
      Buffer.from([1]), Buffer.alloc(32, 255),
    ]))
    .digest('hex');
  if (digest(valid) !== expected) {
    throw new Error('binary command-stream digest self-test failed');
  }
  for (const invalid of [
    '',
    `2|3|${'00'.repeat(32)}\n`,
    `1|256|${'00'.repeat(32)}\n`,
    `1|3|${'00'.repeat(31)}\n`,
    `1|3|${'00'.repeat(32)}|extra\n`,
  ]) {
    let rejected = false;
    try {
      digest(invalid);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error('invalid command stream was accepted');
  }
  console.log('PASS PMLE-EXPANDED-COMMAND-STREAM-HASH-SELF-TEST');
} else {
  const input = process.argv[2];
  if (!input) {
    throw new Error('usage: hash-expanded-command-stream.mjs FILE');
  }
  process.stdout.write(digest(fs.readFileSync(input, 'utf8')));
}
