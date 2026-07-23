import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {authorityRootChainSha, commitAuthorityTransition,
  decodeAuthorityTransition} from '../client/staging/authority.js';

function transition({tic, generation, epoch, previous, canonical = null, audio = []}) {
  const audioBytes = Buffer.from(JSON.stringify(audio));
  const bytes = Buffer.alloc(150 + audioBytes.length);
  bytes.write('DMD1', 0, 'ascii');
  bytes.writeUInt32BE(tic, 4);bytes.writeUInt32BE(generation, 8);
  bytes.writeUInt32BE(epoch, 12);bytes[16] = 3;bytes[17] = 2;
  bytes.writeUInt16BE(canonical === null ? 0 : 1, 18);
  Buffer.from(previous, 'hex').copy(bytes, 20);
  if (canonical !== null) Buffer.from(canonical, 'hex').copy(bytes, 84);
  for (let index = 0; index < 32; index += 1) bytes[116 + index] = (tic * 17 + index) & 255;
  bytes.writeUInt16BE(audioBytes.length, 148);audioBytes.copy(bytes, 150);
  const material = Buffer.concat([bytes.subarray(0, 52), bytes.subarray(84)]);
  createHash('sha256').update(material).digest().copy(bytes, 52);
  return bytes;
}

const zero = '00'.repeat(32);
assert.equal(await authorityRootChainSha(
  '9d1a73965594881f27d4ab7652e0d951', 2),
  '1eac3eca868e8a21b9291bf13509708065ad99698a2b28fb45271368ee4c273b');
const canonical = createHash('sha256').update('canonical tic 1').digest('hex');
const first = transition({tic: 1, generation: 1, epoch: 7, previous: zero,
  canonical, audio: [[1, 0, 'DSPISTOL', 127, 128]]});
const state = {tic: 0, generation: 1, membershipEpoch: 7, chainSha: zero};
const decodedFirst = await decodeAuthorityTransition(first.toString('base64'), state);
assert.equal(decodedFirst.tic, 1);assert.equal(decodedFirst.canonicalStateSha, canonical);
assert.deepEqual(decodedFirst.audio, [[1, 0, 'DSPISTOL', 127, 128]]);
assert.equal(state.chainSha, zero);commitAuthorityTransition(state, decodedFirst);
assert.equal(state.chainSha, decodedFirst.chainSha);

const second = transition({tic: 2, generation: 2, epoch: 7,
  previous: decodedFirst.chainSha});
const decodedSecond = await decodeAuthorityTransition(second.toString('base64'), state);
assert.equal(decodedSecond.tic, 2);assert.equal(decodedSecond.canonicalStateSha, undefined);
assert.equal(state.generation, 1);commitAuthorityTransition(state, decodedSecond);
assert.equal(state.generation, 2);

const tampered = Buffer.from(second);tampered[117] ^= 1;
await assert.rejects(decodeAuthorityTransition(tampered.toString('base64')),
  /chain hash is invalid/);
await assert.rejects(decodeAuthorityTransition(second.toString('base64'),
  {tic: 0, generation: 1, membershipEpoch: 7, chainSha: zero}),
  /stream fence changed/);
console.log('PASS DMD1 authoritative transition chain/fences/tamper rejection');
