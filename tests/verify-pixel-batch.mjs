import assert from 'node:assert/strict';
import {gzipSync} from 'node:zlib';
import {
  databasePixelBatchDisposition,decodeDatabasePixelBatch,
  decodeDatabasePixelTransport
}
  from '../client/staging/pixel-batch.js';

const frame0=Buffer.alloc(64_000,7);
const frame1=Buffer.alloc(64_000,19);
const payload=Buffer.alloc(8+2*(8+64_000));
payload.write('DPB2',0,'ascii');
payload.writeUInt32BE(2,4);
payload.writeUInt32BE(41,8);
payload.writeUInt8(7,12);
frame0.copy(payload,16);
payload.writeUInt32BE(42,16+64_000);
payload.writeUInt8(11,20+64_000);
frame1.copy(payload,24+64_000);

const decoded=decodeDatabasePixelBatch(new Uint8Array(payload));
assert.equal(decoded.length,2);
assert.equal(decoded[0].tic,41);
assert.equal(decoded[1].tic,42);
assert.equal(decoded[0].paletteIndex,7);
assert.equal(decoded[1].paletteIndex,11);
assert.deepEqual(Buffer.from(decoded[0].indices),frame0);
assert.deepEqual(Buffer.from(decoded[1].indices),frame1);
assert.equal(decoded[0].indices.buffer,decoded[1].indices.buffer,
  'decoded frames must share one zero-copy batch backing buffer');
const compressedDecoded=await decodeDatabasePixelTransport(
  new Uint8Array(gzipSync(payload)),0);
assert.equal(compressedDecoded.length,2);
assert.deepEqual(Buffer.from(compressedDecoded[0].indices),frame0);
assert.deepEqual(Buffer.from(compressedDecoded[1].indices),frame1);
await assert.rejects(()=>decodeDatabasePixelTransport(
  new Uint8Array(Buffer.from([0x1f,0x8b,0x08,0x00,0x01]))));

const shared=Buffer.alloc(16+2*64_000);
shared.write('DPD1',0,'ascii');
shared.writeUInt32BE(77,4);
shared.writeUInt8(3,8);
shared.writeUInt8(2,9);
shared.writeUInt8(9,10);
frame0.copy(shared,16);
frame1.copy(shared,16+64_000);
const shared0=decodeDatabasePixelBatch(new Uint8Array(shared),0);
const shared1=decodeDatabasePixelBatch(new Uint8Array(shared),1);
assert.equal(shared0.length,1);
assert.equal(shared1.length,1);
assert.equal(shared0[0].tic,77);
assert.equal(shared1[0].tic,77);
assert.equal(shared0[0].paletteIndex,2);
assert.equal(shared1[0].paletteIndex,9);
assert.deepEqual(Buffer.from(shared0[0].indices),frame0);
assert.deepEqual(Buffer.from(shared1[0].indices),frame1);
assert.throws(()=>decodeDatabasePixelBatch(
  new Uint8Array(Buffer.from(shared).fill(2,11,12)),0));
assert.throws(()=>decodeDatabasePixelBatch(new Uint8Array(shared),2));

for(const mutation of [
  payload.subarray(0,payload.length-1),
  Buffer.from(payload).fill(0,0,4),
  (()=>{const value=Buffer.from(payload);value.writeUInt8(14,12);return value;})(),
  (()=>{const value=Buffer.from(payload);value.writeUInt8(1,13);return value;})(),
  (()=>{const value=Buffer.from(payload);value.writeUInt32BE(41,16+64_000);return value;})(),
  (()=>{const value=Buffer.from(payload);value.writeUInt32BE(43,16+64_000);return value;})(),
]) {
  assert.throws(()=>decodeDatabasePixelBatch(new Uint8Array(mutation)));
}
assert.equal(databasePixelBatchDisposition(4,41,4,42),'CONTINUE');
assert.equal(databasePixelBatchDisposition(4,41,5,null),'RESET_GENERATION');
assert.equal(databasePixelBatchDisposition(4,41,4,45),'RESET_GAP');
assert.throws(()=>databasePixelBatchDisposition(5,41,4,42),
  /generation regressed/);
process.stdout.write(
  'PASS PIXEL-BATCH DPB2/DPD1 palette/exact/length/magic/order/viewpoint\n');
