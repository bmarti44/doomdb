#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  oneDbRecord,
  selfTestDbOutput,
} from './lib/db-output.mjs';

if (process.argv[2] === '--self-test') {
  selfTestDbOutput();
  const fixture = [
    'Session altered.',
    'PMLE_REQUIRE_RECORD|PASS|sha=abc',
    '',
  ].join('\n');
  assert.equal(oneDbRecord(fixture, 'PMLE_REQUIRE_RECORD|'),
    'PMLE_REQUIRE_RECORD|PASS|sha=abc');
  console.log('PASS DB-RECORD-REQUIRE-SELF-TEST');
  process.exit(0);
}

if (process.argv[2] === '--one') {
  const [, , , file, prefix] = process.argv;
  assert.ok(file && prefix,
    'usage: require-db-record.mjs --one FILE PREFIX');
  console.log(oneDbRecord(fs.readFileSync(file, 'utf8'), prefix));
  process.exit(0);
}

const [file, prefix, expected] = process.argv.slice(2);
assert.ok(file && prefix && expected,
  'usage: require-db-record.mjs FILE PREFIX EXPECTED_RECORD');
assert.equal(oneDbRecord(fs.readFileSync(file, 'utf8'), prefix), expected);
