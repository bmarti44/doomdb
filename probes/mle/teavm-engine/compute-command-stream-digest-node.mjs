#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const authorityPath = process.argv[2];
const fixturePath = process.argv[3];
const iwadPath = process.argv[4];
const tablePath = process.argv[5];
if ([authorityPath, fixturePath, iwadPath, tablePath]
    .some(value => value === undefined)) {
  throw new Error(
    'usage: compute-command-stream-digest-node.mjs '
    + 'AUTHORITY.js FIXTURE.json IWAD TABLE_PACK',
  );
}

const authorityBytes = fs.readFileSync(authorityPath);
const fixtureBytes = fs.readFileSync(fixturePath);
const fixture = JSON.parse(fixtureBytes);
const iwad = fs.readFileSync(iwadPath);
const tables = fs.readFileSync(tablePath);
const authority = await import(new URL(`file://${fs.realpathSync(authorityPath)}`));
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest();
const hex = bytes => Buffer.from(bytes).toString('hex');

function load(bytes, allocate, write) {
  assert.equal(authority[allocate](bytes.length), bytes.length);
  for (let offset = 0; offset < bytes.length; offset += 1024 * 1024) {
    const chunk = bytes.subarray(offset,
      Math.min(bytes.length, offset + 1024 * 1024));
    assert.equal(authority[write](offset, chunk), offset + chunk.length);
  }
}

function canonical() {
  const length = authority.canonicalStateLength();
  assert.ok(length > 0);
  const bytes = Buffer.alloc(length);
  for (let offset = 0; offset < length; offset += 32767) {
    const chunk = authority.canonicalStateChunk(
      offset, Math.min(32767, length - offset));
    Buffer.from(chunk).copy(bytes, offset);
  }
  return bytes;
}

assert.equal(fixture.schema, 1);
assert.equal(fixture.tics, 5250);
assert.equal(fixture.players, 2);
assert.equal(fixture.mode, 'DEATHMATCH');
load(iwad, 'allocateIwad', 'loadIwadChunk');
load(tables, 'allocateTablePack', 'loadTablePackChunk');
assert.match(authority.initializeMultiplayerGame(
  fixture.players, 1, fixture.skill, fixture.episode, fixture.map),
/state=multiplayer-initialized\|gametic=0\|/);

let cumulative = Buffer.alloc(32);
let tic = 0;
let finalCanonical;
for (const run of fixture.runs) {
  const command = Uint8Array.from(Buffer.from(run.command, 'hex'));
  for (let repeat = 0; repeat < run.repeat; repeat += 1) {
    tic += 1;
    assert.equal(authority.stepMultiplayerAuthoritative(
      fixture.players, run.membership, command), tic);
    finalCanonical = canonical();
    const ticBytes = Buffer.alloc(4);
    ticBytes.writeInt32BE(tic);
    cumulative = sha256(Buffer.concat([
      cumulative, ticBytes, sha256(finalCanonical),
    ]));
    if (tic % 500 === 0) {
      process.stdout.write(
        `PMLE_COMMAND_DIGEST_PROGRESS|venue=NODE|tic=${tic}` +
        `|cumulative_sha256=${hex(cumulative)}\n`,
      );
    }
  }
}
assert.equal(tic, fixture.tics);
const finalSha = hex(sha256(finalCanonical));
assert.equal(finalSha,
  'b3f667c9395455fd42e31586dd79006fc9c091132cb09c8b1f4627a7d93a9907',
  'terminal canonical SHA must match the accepted local parity record');
process.stdout.write(
  `PMLE_COMMAND_DIGEST|PASS|venue=NODE|tics=${tic}` +
  `|authority_sha256=${hex(sha256(authorityBytes))}` +
  `|stream_sha256=${fixture.expandedSha256}` +
  `|canonical_sha256=${finalSha}` +
  `|cumulative_sha256=${hex(cumulative)}\n`,
);
authority.release();
