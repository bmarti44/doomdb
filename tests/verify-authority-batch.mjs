import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {decodeAuthorityBatch} from '../client/staging/authority-batch.js';

function transition({tic, generation, epoch, previous}) {
  const audio = Buffer.from('[]');const bytes = Buffer.alloc(150 + audio.length);
  bytes.write('DMD1');bytes.writeUInt32BE(tic, 4);bytes.writeUInt32BE(generation, 8);
  bytes.writeUInt32BE(epoch, 12);bytes[16] = 3;bytes[17] = 2;
  Buffer.from(previous, 'hex').copy(bytes, 20);
  for (let index = 0; index < 32; index += 1) bytes[116 + index] = tic + index;
  bytes.writeUInt16BE(audio.length, 148);audio.copy(bytes, 150);
  createHash('sha256').update(Buffer.concat([bytes.subarray(0, 52), bytes.subarray(84)]))
    .digest().copy(bytes, 52);
  return bytes;
}

function batch({records, generation = 1, epoch = 7, after = 0,
                frontier = after + records.length, flags = 0, hold = 4}) {
  const header = Buffer.alloc(32);header.write('DMB1');header.writeUInt16BE(1, 4);
  header.writeUInt16BE(flags, 6);header.writeUInt16BE(records.length, 8);
  header.writeUInt32BE(generation, 12);header.writeUInt32BE(epoch, 16);
  header.writeUInt32BE(after, 20);header.writeUInt32BE(frontier, 24);
  header.writeUInt32BE(hold, 28);
  const framed = records.flatMap(record => {
    const length = Buffer.alloc(4);length.writeUInt32BE(record.length);
    return [length, record];
  });
  return Buffer.concat([header, ...framed]);
}

const zero = '00'.repeat(32);
const first = transition({tic: 1, generation: 1, epoch: 7, previous: zero});
const firstChain = first.subarray(52, 84).toString('hex');
const second = transition({tic: 2, generation: 2, epoch: 7, previous: firstChain});
const state = {tic: 0, generation: 1, membershipEpoch: 7, chainSha: zero};
const decoded = await decodeAuthorityBatch(batch({records: [first, second], generation: 2})
  .toString('base64'), state);
assert.equal(decoded.transitions.length, 2);assert.equal(decoded.committedFrontierTic, 2);
assert.equal(decoded.timedOut, false);assert.equal(decoded.moreAvailable, false);
assert.equal(state.tic, 0, 'batch decode must not commit caller frontier');

const partial = await decodeAuthorityBatch(batch({records: [first], frontier: 2, flags: 2})
  .toString('base64'), state);
assert.equal(partial.moreAvailable, true);

const timeout = await decodeAuthorityBatch(batch({records: [], flags: 1, hold: 500})
  .toString('base64'), state);
assert.equal(timeout.timedOut, true);assert.equal(timeout.transitions.length, 0);
const throttledTimeout = await decodeAuthorityBatch(
  batch({records: [], flags: 1, hold: 1005}).toString('base64'), state);
assert.equal(throttledTimeout.holdElapsedMs, 1005,
  'resource-manager resume delay is not the requested hold bound');

const badLength = batch({records: [first]});badLength.writeUInt32BE(first.length + 1, 32);
await assert.rejects(decodeAuthorityBatch(badLength.toString('base64'), state),
  /record length|truncated/);
const badFence = batch({records: [first], after: 1, frontier: 2});
await assert.rejects(decodeAuthorityBatch(badFence.toString('base64'), state),
  /batch fence changed/);
console.log('PASS DMB1 consecutive batch/frontier/timeout/tamper fences');
