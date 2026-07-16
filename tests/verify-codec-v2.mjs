import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {decodePayload} from '../client/staging/codec.js';

const transport = Buffer.alloc(320 * 200);
for (let x = 0; x < 320; x += 1) {
  for (let y = 0; y < 200; y += 1) transport[x * 200 + y] = (x * 17 + y * 29) & 255;
}
const frameSha = createHash('sha256').update(transport).digest('hex');
const document = {
  v: 2,
  tic: 37,
  w: 320,
  h: 200,
  mode: 'game',
  state_sha: '1'.repeat(64),
  frame_sha: frameSha,
  frame_b64: transport.toString('base64'),
  audio: [],
  complete: 0
};
const encoded = gzipSync(Buffer.from(JSON.stringify(document))).toString('base64');
const decoded = await decodePayload(encoded);
assert.equal(decoded.tic, 37);
assert.equal(decoded.frameSha, frameSha);
for (let x = 0; x < 320; x += 1) {
  for (let y = 0; y < 200; y += 1) {
    assert.equal(decoded.indices[y * 320 + x], transport[x * 200 + y]);
  }
}

document.frame_b64 = Buffer.alloc(63_999).toString('base64');
await assert.rejects(
  decodePayload(gzipSync(Buffer.from(JSON.stringify(document))).toString('base64')),
  /packed frame is invalid/
);

process.stdout.write('PASS codec v2 packed indexed frame\n');
