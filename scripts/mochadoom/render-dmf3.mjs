import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {encodeIndexedPng} from '../../evaluator/t4.3/reference.mjs';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw Error('usage: node render-dmf3.mjs input.dmf3 output.png');
const base = process.env.DOOM_API_BASE ?? 'http://localhost:8080/ords/doom/doom_api/';
const value = (document, key) => document[key] ?? document[key.toUpperCase()]
  ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];
async function asset(name) {
  let response;
  for (const path of ['GET_ASSET', 'get_asset/']) {
    response = await fetch(new URL(path, base), {method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({p_asset_name: name}), redirect: 'error'});
    if (response.status !== 404) break;
  }
  if (!response?.ok) throw Error(`GET_ASSET: ${response?.status} ${await response?.text()}`);
  return Buffer.from(value(await response.json(), 'p_payload'), 'base64');
}

const payload = fs.readFileSync(input);
assert.equal(payload.subarray(0, 4).toString(), 'DMF3');
const audioLength = payload.readUInt16BE(138), pixelOffset = 140 + audioLength;
assert.equal(payload.length, pixelOffset + 320 * 200);
const columnMajor = payload.subarray(pixelOffset);
const rowMajor = Buffer.alloc(columnMajor.length);
for (let x = 0; x < 320; x += 1) for (let y = 0; y < 200; y += 1) {
  rowMajor[y * 320 + x] = columnMajor[x * 200 + y];
}
const frameSha = payload.subarray(74, 138).toString();
assert.equal(crypto.createHash('sha256').update(rowMajor).digest('hex'), frameSha,
  'DMF3 canonical frame identity');
const palette = await asset('PLAYPAL');
assert.equal(palette.length, 256 * 3);
const entries = Array.from({length: 256}, (_, index) =>
  [...palette.subarray(index * 3, index * 3 + 3)]);
const png = encodeIndexedPng(columnMajor, entries);
fs.writeFileSync(output, png);
process.stdout.write(`WROTE ${output} (tic ${payload.readInt32BE(4)}, frame ${frameSha})\n`);
